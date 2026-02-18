defmodule JidoStudio.TracesLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Evals
  alias JidoStudio.TraceFilter
  alias JidoStudio.Tracing

  @default_range "1h"
  @default_limit 400
  @entity_types ["all", "agent", "model", "tool", "middleware", "scheduler", "sensor", "other"]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2_000, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Traces")
      |> assign(:filters, default_filters())
      |> assign(:traces, [])
      |> assign(:trace, nil)
      |> assign(:spans, [])
      |> assign(:events, [])
      |> assign(:entity_rollups, [])
      |> assign(:eval_runs, [])
      |> assign(:eval_enabled?, Evals.evals_enabled_for_ui?())
      |> assign(:entity_types, @entity_types)
      |> assign(:available_agents, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    traces = Tracing.list_traces(filters: filters, limit: @default_limit)

    available_agents =
      traces
      |> Enum.map(& &1[:agent_id])
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.sort()

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:traces, traces)
      |> assign(:available_agents, available_agents)

    case socket.assigns.live_action do
      :show ->
        trace_id = decode_segment(params["trace_id"])

        case Tracing.get_trace(trace_id) do
          {:ok, trace} ->
            trace_filters = trace_detail_filters(filters)

            spans =
              Tracing.list_trace_spans(trace_id,
                limit: TraceFilter.max_span_rows(),
                filters: trace_filters
              )

            events =
              Tracing.list_trace_events(trace_id,
                order: :asc,
                limit: 1_500,
                filters: trace_filters
              )

            rollups = Tracing.trace_entity_rollups(trace_id, filters: trace_filters)
            eval_runs = Evals.list_runs(trace_id, limit: 10)

            {:noreply,
             socket
             |> assign(:trace, trace)
             |> assign(:spans, spans)
             |> assign(:events, events)
             |> assign(:entity_rollups, rollups)
             |> assign(:eval_runs, eval_runs)}

          _ ->
            {:noreply,
             socket
             |> put_flash(:error, "Trace not found")
             |> assign(:trace, nil)
             |> assign(:spans, [])
             |> assign(:events, [])
             |> assign(:entity_rollups, [])
             |> assign(:eval_runs, [])}
        end

      _ ->
        {:noreply,
         socket
         |> assign(:trace, nil)
         |> assign(:spans, [])
         |> assign(:events, [])
         |> assign(:entity_rollups, [])
         |> assign(:eval_runs, [])}
    end
  end

  @impl true
  def handle_event("filters_change", %{"filters" => params}, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(normalize_filter_params(params))
      |> Map.update(:range, @default_range, fn value -> value || @default_range end)

    path =
      if socket.assigns.live_action == :show and is_map(socket.assigns[:trace]) do
        trace_id = socket.assigns.trace[:trace_id] || socket.assigns.trace[:id]
        detail_path(socket.assigns.prefix, trace_id, filters)
      else
        list_path(socket.assigns.prefix, filters)
      end

    {:noreply,
     push_patch(socket,
       to: path
     )}
  end

  @impl true
  def handle_event("evaluate_trace", _params, %{assigns: %{trace: trace}} = socket)
      when is_map(trace) do
    trace_id = trace[:trace_id] || trace[:id]

    case Evals.run_trace(trace_id, :default) do
      {:ok, _run} ->
        {:noreply,
         socket
         |> put_flash(:info, "Trace evaluation completed.")
         |> assign(:eval_runs, Evals.list_runs(trace_id, limit: 10))}

      {:error, :disabled} ->
        {:noreply, put_flash(socket, :error, "Trace evals are disabled in current config.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Trace evaluation failed: #{inspect(reason)}")}
    end
  end

  def handle_event("evaluate_trace", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:refresh, socket) do
    filters = socket.assigns.filters

    traces = Tracing.list_traces(filters: filters, limit: @default_limit)

    socket =
      socket
      |> assign(:traces, traces)
      |> assign(
        :available_agents,
        traces
        |> Enum.map(& &1[:agent_id])
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()
        |> Enum.sort()
      )

    socket =
      if socket.assigns.live_action == :show and socket.assigns.trace do
        trace_id = socket.assigns.trace[:trace_id] || socket.assigns.trace[:id]
        trace_filters = trace_detail_filters(filters)

        trace =
          case Tracing.get_trace(trace_id) do
            {:ok, t} -> t
            _ -> socket.assigns.trace
          end

        socket
        |> assign(:trace, trace)
        |> assign(
          :spans,
          Tracing.list_trace_spans(trace_id,
            limit: TraceFilter.max_span_rows(),
            filters: trace_filters
          )
        )
        |> assign(
          :events,
          Tracing.list_trace_events(trace_id, order: :asc, limit: 1_500, filters: trace_filters)
        )
        |> assign(:entity_rollups, Tracing.trace_entity_rollups(trace_id, filters: trace_filters))
        |> assign(:eval_runs, Evals.list_runs(trace_id, limit: 10))
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Trace Detail" subtitle="Span timeline, metadata, and correlation context">
        <:actions>
          <button
            :if={@trace && @eval_enabled?}
            type="button"
            phx-click="evaluate_trace"
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            Evaluate Trace
          </button>
          <.link
            navigate={list_path(@prefix, @filters)}
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            Back to Traces
          </.link>
        </:actions>
      </.page_header>

      <.card :if={is_nil(@trace)}>
        <.empty_state title="Trace not found" description="The selected trace is not available." />
      </.card>

      <%= if @trace do %>
        <.card>
          <form phx-change="filters_change" class="grid grid-cols-1 md:grid-cols-4 gap-2">
            <label class="text-xs text-js-text-muted">
              Span Query
              <input
                type="text"
                name="filters[query]"
                value={@filters.query || ""}
                placeholder="span/event/metadata text"
                class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
              />
            </label>

            <label class="text-xs text-js-text-muted">
              Entity Lane
              <select
                name="filters[entity_type]"
                class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
              >
                <option
                  :for={entity_type <- @entity_types}
                  value={entity_type}
                  selected={entity_type == (@filters.entity_type || "all")}
                >
                  {String.capitalize(entity_type)}
                </option>
              </select>
            </label>

            <label class="text-xs text-js-text-muted flex items-end gap-2">
              <input type="hidden" name="filters[hide_internal]" value="false" />
              <input
                type="checkbox"
                name="filters[hide_internal]"
                value="true"
                checked={@filters.hide_internal == true}
                class="rounded border-js-border bg-js-bg-elevated"
              /> Hide internal spans
            </label>

            <label class="text-xs text-js-text-muted flex items-end gap-2">
              <input type="hidden" name="filters[stream_only]" value="false" />
              <input
                type="checkbox"
                name="filters[stream_only]"
                value="true"
                checked={@filters.stream_only == true}
                class="rounded border-js-border bg-js-bg-elevated"
              /> Streaming chunks only
            </label>
          </form>
        </.card>

        <div class="grid grid-cols-1 lg:grid-cols-4 gap-4">
          <.card class="lg:col-span-1">
            <div class="space-y-2 text-xs text-js-text-muted">
              <div>
                <span class="text-js-text-subtle">Trace ID:</span>
                <code>{@trace.trace_id || @trace.id}</code>
              </div>
              <div><span class="text-js-text-subtle">Agent:</span> {@trace.agent_id || "—"}</div>
              <div><span class="text-js-text-subtle">Status:</span> {trace_status(@trace)}</div>
              <div>
                <span class="text-js-text-subtle">Started:</span> {format_datetime(@trace.started_at)}
              </div>
              <div>
                <span class="text-js-text-subtle">Ended:</span> {format_datetime(@trace.ended_at)}
              </div>
              <div>
                <span class="text-js-text-subtle">Duration:</span> {format_duration(
                  @trace.duration_ms
                )}
              </div>
              <div>
                <span class="text-js-text-subtle">Call ID:</span>
                <code>{@trace.call_id || "—"}</code>
              </div>
              <div>
                <span class="text-js-text-subtle">Causation ID:</span>
                <code>{@trace.causation_id || "—"}</code>
              </div>
              <div>
                <span class="text-js-text-subtle">Spans:</span> {@trace.span_count || length(@spans)}
              </div>
              <div>
                <span class="text-js-text-subtle">Events:</span> {@trace.event_count ||
                  length(@events)}
              </div>
              <div :if={@eval_runs != []}>
                <span class="text-js-text-subtle">Last Eval:</span>
                <.badge variant={if(hd(@eval_runs).status == :pass, do: :success, else: :error)}>
                  score {hd(@eval_runs).score}
                </.badge>
              </div>
            </div>
          </.card>

          <.card class="lg:col-span-3 p-0 overflow-hidden">
            <div class="px-3 py-2 border-b border-js-border">
              <h3 class="text-sm font-medium text-js-text">Timeline</h3>
              <p class="text-xs text-js-text-muted mt-1">
                Span hierarchy ordered by start time. Critical path spans are highlighted.
              </p>
            </div>

            <div :if={@spans == []} class="p-4">
              <.empty_state
                title="No spans"
                description="No span records were stored for this trace yet."
              />
            </div>

            <div :if={@spans != []} class="overflow-x-auto">
              <table class="w-full">
                <thead>
                  <tr class="border-b border-js-border">
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Span
                    </th>
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Status
                    </th>
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Offset
                    </th>
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Duration
                    </th>
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Entity
                    </th>
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Chunk
                    </th>
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Span ID
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-js-border">
                  <tr
                    :for={span <- @spans}
                    class={[
                      "hover:bg-js-bg-elevated/40",
                      if(span.critical_path, do: "bg-js-info/10")
                    ]}
                  >
                    <td class="px-3 py-2 text-xs text-js-text-muted font-mono">
                      <span style={"padding-left: #{(span.depth || 0) * 16}px"}>
                        {span.event_name}
                      </span>
                    </td>
                    <td class="px-3 py-2 text-xs">
                      <.badge variant={span_badge_variant(span.status)}>
                        {span.status || "running"}
                      </.badge>
                    </td>
                    <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                      {format_duration(span.offset_ms)}
                    </td>
                    <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                      {format_duration(span.duration_ms)}
                    </td>
                    <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                      {span.entity_type || "other"}
                    </td>
                    <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                      {format_chunk(span.chunk_index, span.chunk_count)}
                    </td>
                    <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">{span.span_id}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.card>
        </div>

        <.card :if={@entity_rollups != []}>
          <h3 class="text-sm font-medium text-js-text mb-2">Entity Duration Rollups</h3>
          <div class="flex flex-wrap gap-2">
            <.badge
              :for={rollup <- @entity_rollups}
              variant={if(rollup.errors > 0, do: :warning, else: :default)}
            >
              {rollup.entity_type}: {format_duration(rollup.duration_ms)} ({rollup.count})
            </.badge>
          </div>
        </.card>

        <.card :if={@eval_runs != []}>
          <h3 class="text-sm font-medium text-js-text mb-2">Eval History</h3>
          <div class="space-y-2">
            <div
              :for={run <- @eval_runs}
              class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2 text-xs"
            >
              <div class="flex items-center justify-between gap-2">
                <span class="text-js-text-subtle font-mono">{format_datetime(run.inserted_at)}</span>
                <.badge variant={if(run.status == :pass, do: :success, else: :error)}>
                  {run.status} / {run.score}
                </.badge>
              </div>
            </div>
          </div>
        </.card>

        <.card :if={@trace.error}>
          <h3 class="text-sm font-medium text-js-error mb-2">Error Payload</h3>
          <pre class="text-xs text-js-text-muted bg-js-bg-elevated border border-js-border rounded-md p-3 whitespace-pre-wrap break-words"><%= inspect(@trace.error_payload || %{}, pretty: true, limit: 80, printable_limit: 20_000) %></pre>
        </.card>

        <.card>
          <h3 class="text-sm font-medium text-js-text mb-2">Trace Events</h3>
          <div :if={@events == []} class="text-xs text-js-text-subtle">No events captured.</div>
          <div :if={@events != []} class="space-y-2 max-h-[24rem] overflow-y-auto js-scroll">
            <div
              :for={event <- @events}
              class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
            >
              <div class="flex items-center justify-between gap-2">
                <span class="text-[11px] font-mono text-js-text-subtle">
                  {format_timestamp(event.timestamp_ms)}
                </span>
                <.badge variant={event_badge_variant(event.type)}>{event.type || :event}</.badge>
              </div>
              <div class="mt-1 text-xs text-js-text font-mono">{event_name(event)}</div>
              <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                {event.entity_type || "other"} / {event.status || "running"} / {format_chunk(
                  event.chunk_index,
                  event.chunk_count
                )}
              </div>
            </div>
          </div>
        </.card>
      <% end %>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Traces" subtitle="Explore trace runs and execution timelines">
        <:actions>
          <.badge>showing {length(@traces)} traces</.badge>
        </:actions>
      </.page_header>

      <.card>
        <form phx-change="filters_change" class="grid grid-cols-1 md:grid-cols-4 lg:grid-cols-8 gap-2">
          <label class="text-xs text-js-text-muted">
            Agent
            <select
              name="filters[agent]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="">All</option>
              <option
                :for={agent <- @available_agents}
                value={agent}
                selected={agent == @filters.agent}
              >
                {agent}
              </option>
            </select>
          </label>

          <label class="text-xs text-js-text-muted">
            Status
            <select
              name="filters[status]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="all" selected={@filters.status == "all"}>All</option>
              <option value="running" selected={@filters.status == "running"}>Running</option>
              <option value="ok" selected={@filters.status == "ok"}>OK</option>
              <option value="error" selected={@filters.status == "error"}>Error</option>
            </select>
          </label>

          <label class="text-xs text-js-text-muted">
            Time Range
            <select
              name="filters[range]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="15m" selected={@filters.range == "15m"}>15m</option>
              <option value="1h" selected={@filters.range == "1h"}>1h</option>
              <option value="24h" selected={@filters.range == "24h"}>24h</option>
              <option value="custom" selected={@filters.range == "custom"}>Custom</option>
            </select>
          </label>

          <label class="text-xs text-js-text-muted">
            From
            <input
              type="datetime-local"
              name="filters[from]"
              value={@filters.from || ""}
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>

          <label class="text-xs text-js-text-muted">
            To
            <input
              type="datetime-local"
              name="filters[to]"
              value={@filters.to || ""}
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>

          <label class="text-xs text-js-text-muted">
            Span/Event Query
            <input
              type="text"
              name="filters[query]"
              value={@filters.query || ""}
              placeholder="tool failure, task_id..."
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>

          <label class="text-xs text-js-text-muted">
            Entity Type
            <select
              name="filters[entity_type]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option
                :for={entity_type <- @entity_types}
                value={entity_type}
                selected={entity_type == (@filters.entity_type || "all")}
              >
                {String.capitalize(entity_type)}
              </option>
            </select>
          </label>

          <label class="text-xs text-js-text-muted flex items-end gap-2">
            <input type="hidden" name="filters[hide_internal]" value="false" />
            <input
              type="checkbox"
              name="filters[hide_internal]"
              value="true"
              checked={@filters.hide_internal == true}
              class="rounded border-js-border bg-js-bg-elevated"
            /> Hide internal
          </label>

          <label class="text-xs text-js-text-muted flex items-end gap-2">
            <input type="hidden" name="filters[stream_only]" value="false" />
            <input
              type="checkbox"
              name="filters[stream_only]"
              value="true"
              checked={@filters.stream_only == true}
              class="rounded border-js-border bg-js-bg-elevated"
            /> Stream chunks
          </label>
        </form>
      </.card>

      <.card :if={@traces == []}>
        <.empty_state
          title="No traces"
          description="No trace runs matched the current filters."
        />
      </.card>

      <.card :if={@traces != []} class="p-0 overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead>
              <tr class="border-b border-js-border">
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Trace ID
                </th>
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Agent
                </th>
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Status
                </th>
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Started
                </th>
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Duration
                </th>
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Error?
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-js-border">
              <tr :for={trace <- @traces} class="hover:bg-js-bg-elevated/50">
                <td class="px-3 py-2 text-xs text-js-info font-mono">
                  <.link navigate={detail_path(@prefix, trace.trace_id || trace.id, @filters)}>
                    {trace.trace_id || trace.id}
                  </.link>
                </td>
                <td class="px-3 py-2 text-xs text-js-text-muted">{trace.agent_id || "—"}</td>
                <td class="px-3 py-2 text-xs">
                  <.badge variant={span_badge_variant(trace.status)}>
                    {trace.status || "running"}
                  </.badge>
                </td>
                <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                  {format_datetime(trace.started_at)}
                </td>
                <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                  {format_duration(trace.duration_ms)}
                </td>
                <td class="px-3 py-2 text-xs text-js-text-subtle">
                  {if(trace.error, do: "yes", else: "no")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.card>
    </div>
    """
  end

  defp default_filters do
    %{
      agent: nil,
      status: "all",
      range: @default_range,
      from: nil,
      to: nil,
      query: nil,
      entity_type: "all",
      hide_internal: TraceFilter.hide_internal_default?(),
      stream_only: false
    }
  end

  defp parse_filters(params) when is_map(params) do
    from_params = normalize_filter_params(params)

    default_filters()
    |> Map.merge(from_params)
    |> Map.put(:range, normalize_range(from_params[:range] || @default_range))
    |> maybe_clear_custom_bounds()
  end

  defp parse_filters(_), do: default_filters()

  defp normalize_filter_params(params) do
    source = params["filters"] || params

    %{
      agent: normalize_optional_string(source["agent"]),
      status: normalize_status(source["status"]),
      range: normalize_range(source["range"]),
      from: normalize_optional_string(source["from"]),
      to: normalize_optional_string(source["to"]),
      query: normalize_optional_string(source["query"]),
      entity_type: normalize_entity_type(source["entity_type"]),
      hide_internal:
        normalize_checkbox(source["hide_internal"], TraceFilter.hide_internal_default?()),
      stream_only: normalize_checkbox(source["stream_only"], false)
    }
  end

  defp maybe_clear_custom_bounds(%{range: "custom"} = filters), do: filters
  defp maybe_clear_custom_bounds(filters), do: %{filters | from: nil, to: nil}

  defp normalize_status(nil), do: "all"

  defp normalize_status(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))
    if normalized in ["all", "running", "ok", "error"], do: normalized, else: "all"
  end

  defp normalize_status(_), do: "all"

  defp normalize_range(nil), do: @default_range

  defp normalize_range(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))
    if normalized in ["15m", "1h", "24h", "custom"], do: normalized, else: @default_range
  end

  defp normalize_range(_), do: @default_range

  defp list_path(prefix, filters) do
    params = filter_query_params(filters)

    if map_size(params) == 0 do
      prefix <> "/traces"
    else
      prefix <> "/traces?" <> URI.encode_query(params)
    end
  end

  defp detail_path(prefix, trace_id, filters) do
    base = prefix <> "/traces/" <> URI.encode_www_form(to_string(trace_id))
    params = filter_query_params(filters)

    if map_size(params) == 0 do
      base
    else
      base <> "?" <> URI.encode_query(params)
    end
  end

  defp filter_query_params(filters) do
    %{}
    |> maybe_put("agent", filters.agent)
    |> maybe_put("status", if(filters.status == "all", do: nil, else: filters.status))
    |> maybe_put("range", if(filters.range == @default_range, do: nil, else: filters.range))
    |> maybe_put("from", if(filters.range == "custom", do: filters.from, else: nil))
    |> maybe_put("to", if(filters.range == "custom", do: filters.to, else: nil))
    |> maybe_put("query", filters.query)
    |> maybe_put(
      "entity_type",
      if(filters.entity_type in [nil, "all"], do: nil, else: filters.entity_type)
    )
    |> maybe_put(
      "hide_internal",
      if(filters.hide_internal == TraceFilter.hide_internal_default?(),
        do: nil,
        else: to_string(filters.hide_internal)
      )
    )
    |> maybe_put("stream_only", if(filters.stream_only, do: "true", else: nil))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp decode_segment(value) when is_binary(value), do: URI.decode_www_form(value)
  defp decode_segment(_), do: ""

  defp trace_detail_filters(filters) do
    %{
      hide_internal: filters.hide_internal,
      entity_type: if(filters.entity_type in [nil, "all"], do: nil, else: filters.entity_type),
      status: if(filters.status in [nil, "all"], do: nil, else: filters.status),
      stream_only: filters.stream_only,
      query: filters.query
    }
  end

  defp event_name(event) when is_map(event) do
    cond do
      is_binary(event[:event_name]) -> event[:event_name]
      is_list(event[:event_prefix]) -> Enum.join(event[:event_prefix], ".")
      true -> "event"
    end
  end

  defp event_name(_), do: "event"

  defp event_badge_variant(:exception), do: :error
  defp event_badge_variant(:stop), do: :success
  defp event_badge_variant(:start), do: :info
  defp event_badge_variant("exception"), do: :error
  defp event_badge_variant("stop"), do: :success
  defp event_badge_variant("start"), do: :info
  defp event_badge_variant(_), do: :default

  defp span_badge_variant("error"), do: :error
  defp span_badge_variant("ok"), do: :success
  defp span_badge_variant("running"), do: :info
  defp span_badge_variant(:error), do: :error
  defp span_badge_variant(:ok), do: :success
  defp span_badge_variant(:running), do: :info
  defp span_badge_variant(_), do: :default

  defp trace_status(trace) when is_map(trace) do
    trace[:status] || "running"
  end

  defp format_datetime(ts) when is_integer(ts) and ts > 0 do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(_), do: "—"

  defp format_timestamp(ts) when is_integer(ts) and ts > 0 do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S.%f")
    |> String.slice(0, 12)
  end

  defp format_timestamp(_), do: "—"

  defp format_duration(ms) when is_integer(ms) and ms >= 0, do: "#{ms}ms"
  defp format_duration(_), do: "—"

  defp format_chunk(chunk_index, chunk_count)
       when is_integer(chunk_index) and chunk_index >= 0 and is_integer(chunk_count) and
              chunk_count > 0 do
    "#{chunk_index + 1}/#{chunk_count}"
  end

  defp format_chunk(_, _), do: "—"

  defp normalize_entity_type(nil), do: "all"

  defp normalize_entity_type(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))
    if normalized in @entity_types, do: normalized, else: "all"
  end

  defp normalize_entity_type(_), do: "all"

  defp normalize_checkbox(nil, default), do: default
  defp normalize_checkbox(true, _default), do: true
  defp normalize_checkbox("true", _default), do: true
  defp normalize_checkbox("1", _default), do: true
  defp normalize_checkbox("on", _default), do: true
  defp normalize_checkbox(false, _default), do: false
  defp normalize_checkbox("false", _default), do: false
  defp normalize_checkbox("0", _default), do: false
  defp normalize_checkbox(_, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    normalized = String.trim(value)
    if normalized == "", do: nil, else: normalized
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil
end
