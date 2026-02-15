defmodule JidoStudio.TracesLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Tracing

  @default_range "1h"
  @default_limit 400

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
            spans = Tracing.list_trace_spans(trace_id, limit: 5_000)
            events = Tracing.list_trace_events(trace_id, order: :asc, limit: 1_500)

            {:noreply,
             socket
             |> assign(:trace, trace)
             |> assign(:spans, spans)
             |> assign(:events, events)}

          _ ->
            {:noreply,
             socket
             |> put_flash(:error, "Trace not found")
             |> assign(:trace, nil)
             |> assign(:spans, [])
             |> assign(:events, [])}
        end

      _ ->
        {:noreply,
         socket
         |> assign(:trace, nil)
         |> assign(:spans, [])
         |> assign(:events, [])}
    end
  end

  @impl true
  def handle_event("filters_change", %{"filters" => params}, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(normalize_filter_params(params))
      |> Map.update(:range, @default_range, fn value -> value || @default_range end)

    {:noreply,
     push_patch(socket,
       to: list_path(socket.assigns.prefix, filters)
     )}
  end

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

        trace =
          case Tracing.get_trace(trace_id) do
            {:ok, t} -> t
            _ -> socket.assigns.trace
          end

        socket
        |> assign(:trace, trace)
        |> assign(:spans, Tracing.list_trace_spans(trace_id, limit: 5_000))
        |> assign(:events, Tracing.list_trace_events(trace_id, order: :asc, limit: 1_500))
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
            </div>
          </.card>

          <.card class="lg:col-span-3 p-0 overflow-hidden">
            <div class="px-3 py-2 border-b border-js-border">
              <h3 class="text-sm font-medium text-js-text">Timeline</h3>
              <p class="text-xs text-js-text-muted mt-1">Span hierarchy ordered by start time.</p>
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
                      Span ID
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-js-border">
                  <tr :for={span <- @spans} class="hover:bg-js-bg-elevated/40">
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
                    <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">{span.span_id}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.card>
        </div>

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
        <form phx-change="filters_change" class="grid grid-cols-1 md:grid-cols-5 gap-2">
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
    %{agent: nil, status: "all", range: @default_range, from: nil, to: nil}
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
      to: normalize_optional_string(source["to"])
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
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp decode_segment(value) when is_binary(value), do: URI.decode_www_form(value)
  defp decode_segment(_), do: ""

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

  defp normalize_optional_string(value) when is_binary(value) do
    normalized = String.trim(value)
    if normalized == "", do: nil, else: normalized
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil
end
