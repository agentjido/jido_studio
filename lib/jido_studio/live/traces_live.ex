defmodule JidoStudio.TracesLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Observability

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2000, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Traces")
      |> assign(:events, [])
      |> assign(:trace_groups, [])
      |> assign(:filters_active?, false)
      |> assign(:source_filter, nil)
      |> assign(:agent_slug_filter, nil)
      |> assign(:agent_module_filter, nil)
      |> assign(:agent_id_filter, nil)
      |> assign(:instance_id_filter, nil)
      |> assign(:trace_id_filter, nil)
      |> assign(:span_id_filter, nil)
      |> assign(:parent_span_id_filter, nil)
      |> assign(:causation_id_filter, nil)
      |> assign(:call_id_filter, nil)
      |> assign(:signal_type_filter, nil)
      |> assign(:directive_type_filter, nil)
      |> assign(:trace_page_limit, Observability.trace_page_limit())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    events =
      load_events(socket.assigns.jido_instance,
        filters: filters,
        limit: socket.assigns.trace_page_limit
      )

    {:noreply,
     socket
     |> assign(:source_filter, filters[:source])
     |> assign(:agent_slug_filter, filters[:agent_slug])
     |> assign(:agent_module_filter, filters[:agent_module])
     |> assign(:agent_id_filter, filters[:agent_id])
     |> assign(:instance_id_filter, filters[:instance_id])
     |> assign(:trace_id_filter, filters[:trace_id])
     |> assign(:span_id_filter, filters[:span_id])
     |> assign(:parent_span_id_filter, filters[:parent_span_id])
     |> assign(:causation_id_filter, filters[:causation_id])
     |> assign(:call_id_filter, filters[:call_id])
     |> assign(:signal_type_filter, filters[:signal_type])
     |> assign(:directive_type_filter, filters[:directive_type])
     |> assign(:filters_active?, filters_active?(filters))
     |> assign(:events, events)
     |> assign(:trace_groups, trace_groups(events))}
  end

  @impl true
  def handle_info(:refresh, socket) do
    filters = current_filters(socket)

    events =
      load_events(socket.assigns.jido_instance,
        filters: filters,
        limit: socket.assigns.trace_page_limit
      )

    {:noreply,
     socket
     |> assign(:events, events)
     |> assign(:trace_groups, trace_groups(events))}
  end

  defp load_events(jido_instance, opts) do
    filters = Keyword.get(opts, :filters, %{})
    limit = Keyword.get(opts, :limit, Observability.trace_page_limit())

    Observability.query_events(jido_instance, filters: filters, limit: limit)
    |> Enum.filter(&matches_agent_filter?(&1, filters))
  rescue
    _ -> []
  end

  defp matches_agent_filter?(_event, %{agent_slug: nil, agent_module: nil}), do: true

  defp matches_agent_filter?(event, filters) do
    slug = filters[:agent_slug]
    module = filters[:agent_module]

    candidate_values = event_candidate_values(event)

    matches_slug? =
      case slug do
        nil -> true
        _ -> slug in candidate_values
      end

    matches_module? =
      case module do
        nil -> true
        _ -> module in candidate_values
      end

    matches_slug? and matches_module?
  end

  defp event_candidate_values(event) do
    metadata = event[:metadata] || %{}

    metadata
    |> Map.values()
    |> Enum.flat_map(&metadata_value_candidates/1)
    |> Enum.uniq()
  end

  defp metadata_value_candidates(%{__struct__: mod} = struct) when is_atom(mod) do
    [inspect(mod), module_slug(mod), inspect(struct)]
  end

  defp metadata_value_candidates(mod) when is_atom(mod), do: [inspect(mod), module_slug(mod)]
  defp metadata_value_candidates(value) when is_binary(value), do: [value]
  defp metadata_value_candidates(value) when is_integer(value), do: [Integer.to_string(value)]
  defp metadata_value_candidates(_), do: []

  defp module_slug(module) do
    module
    |> Atom.to_string()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 8)
  end

  defp trace_groups(events) do
    events
    |> Enum.filter(&(is_binary(&1[:trace_id]) and &1[:trace_id] != ""))
    |> Enum.group_by(& &1.trace_id)
    |> Enum.map(fn {trace_id, trace_events} ->
      sorted = Enum.sort_by(trace_events, &(&1[:timestamp_ms] || 0), :asc)
      first = List.first(sorted)
      last = List.last(sorted)

      %{
        trace_id: trace_id,
        events: length(sorted),
        start_at: first && first[:timestamp_ms],
        end_at: last && last[:timestamp_ms],
        duration_ms:
          max(((last && last[:timestamp_ms]) || 0) - ((first && first[:timestamp_ms]) || 0), 0),
        start_count: Enum.count(sorted, &(&1[:type] == :start)),
        stop_count: Enum.count(sorted, &(&1[:type] == :stop)),
        exception_count: Enum.count(sorted, &(&1[:type] == :exception))
      }
    end)
    |> Enum.sort_by(& &1.start_at, :desc)
  end

  defp format_event_name(event_prefix) when is_list(event_prefix),
    do: Enum.join(event_prefix, ".")

  defp format_event_name(value) when is_binary(value), do: value
  defp format_event_name(value), do: inspect(value)

  defp format_timestamp(ts) when is_integer(ts) do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S.%f")
    |> String.slice(0, 12)
  end

  defp format_timestamp(_), do: "—"

  defp event_badge_variant(:exception), do: :error
  defp event_badge_variant(:stop), do: :success
  defp event_badge_variant(:start), do: :info
  defp event_badge_variant(_), do: :default

  defp source_badge_variant(:telemetry), do: :info
  defp source_badge_variant(:agent_debug), do: :warning
  defp source_badge_variant(_), do: :default

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_filters(params) do
    %{
      source: parse_source(blank_to_nil(params["source"])),
      agent_slug: blank_to_nil(params["agent_slug"]),
      agent_module: blank_to_nil(params["agent_module"]),
      agent_id: blank_to_nil(params["agent_id"]),
      instance_id: blank_to_nil(params["instance_id"]),
      trace_id: blank_to_nil(params["trace_id"]),
      span_id: blank_to_nil(params["span_id"]),
      parent_span_id: blank_to_nil(params["parent_span_id"]),
      causation_id: blank_to_nil(params["causation_id"]),
      call_id: blank_to_nil(params["call_id"]),
      signal_type: blank_to_nil(params["signal_type"]),
      directive_type: blank_to_nil(params["directive_type"])
    }
  end

  defp parse_source(nil), do: nil
  defp parse_source("telemetry"), do: :telemetry
  defp parse_source("agent_debug"), do: :agent_debug
  defp parse_source(_), do: nil

  defp current_filters(socket) do
    %{
      source: socket.assigns.source_filter,
      agent_slug: socket.assigns.agent_slug_filter,
      agent_module: socket.assigns.agent_module_filter,
      agent_id: socket.assigns.agent_id_filter,
      instance_id: socket.assigns.instance_id_filter,
      trace_id: socket.assigns.trace_id_filter,
      span_id: socket.assigns.span_id_filter,
      parent_span_id: socket.assigns.parent_span_id_filter,
      causation_id: socket.assigns.causation_id_filter,
      call_id: socket.assigns.call_id_filter,
      signal_type: socket.assigns.signal_type_filter,
      directive_type: socket.assigns.directive_type_filter
    }
  end

  defp filters_active?(filters) when is_map(filters) do
    Enum.any?(filters, fn {_k, v} -> not is_nil(v) and v != "" end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Traces" subtitle="Telemetry + debug events with correlation context">
        <:actions>
          <.link
            :if={@filters_active?}
            navigate={@prefix <> "/traces"}
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            Clear Filter
          </.link>
          <.badge>showing {length(@events)} / {@trace_page_limit}</.badge>
        </:actions>
      </.page_header>

      <div
        :if={@filters_active?}
        class="bg-js-info/15 border border-js-border rounded-lg p-3 text-xs text-js-text-muted flex flex-wrap gap-2"
      >
        <span :if={@source_filter}>
          source=<code class="bg-js-bg-elevated px-1 rounded">{@source_filter}</code>
        </span>
        <span :if={@agent_slug_filter}>
          slug=<code class="bg-js-bg-elevated px-1 rounded">{@agent_slug_filter}</code>
        </span>
        <span :if={@agent_module_filter}>
          module=<code class="bg-js-bg-elevated px-1 rounded">{@agent_module_filter}</code>
        </span>
        <span :if={@agent_id_filter}>
          agent=<code class="bg-js-bg-elevated px-1 rounded">{@agent_id_filter}</code>
        </span>
        <span :if={@trace_id_filter}>
          trace=<code class="bg-js-bg-elevated px-1 rounded">{@trace_id_filter}</code>
        </span>
        <span :if={@span_id_filter}>
          span=<code class="bg-js-bg-elevated px-1 rounded">{@span_id_filter}</code>
        </span>
        <span :if={@causation_id_filter}>
          cause=<code class="bg-js-bg-elevated px-1 rounded">{@causation_id_filter}</code>
        </span>
        <span :if={@call_id_filter}>
          call=<code class="bg-js-bg-elevated px-1 rounded">{@call_id_filter}</code>
        </span>
      </div>

      <.card :if={@events == []}>
        <.empty_state
          title="No trace events yet"
          description="Trace/debug events will appear here as agents execute. If filtering is active, try clearing the filter."
        />
      </.card>

      <.card :if={@trace_groups != []}>
        <h3 class="text-sm font-medium text-js-text mb-3">Trace Timeline</h3>
        <div class="space-y-2">
          <div
            :for={group <- Enum.take(@trace_groups, 8)}
            class="rounded-md border border-js-border bg-js-bg-elevated/30 px-3 py-2 text-xs"
          >
            <div class="flex items-center justify-between gap-2">
              <code class="text-js-text">{group.trace_id}</code>
              <span class="text-js-text-subtle">{group.events} events</span>
            </div>
            <div class="mt-1 text-js-text-muted flex flex-wrap gap-x-3 gap-y-1">
              <span>duration: {group.duration_ms}ms</span>
              <span>start: {group.start_count}</span>
              <span>stop: {group.stop_count}</span>
              <span>exception: {group.exception_count}</span>
            </div>
          </div>
        </div>
      </.card>

      <.card :if={@events != []} class="p-0">
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead>
              <tr class="border-b border-js-border">
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                  Time
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                  Source
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                  Event
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                  Type
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                  Agent
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                  Trace
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                  Call
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                  Details
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-js-border">
              <tr :for={event <- @events} class="hover:bg-js-bg-elevated transition-colors">
                <td class="px-3 py-2 text-xs text-js-text-subtle font-mono whitespace-nowrap">
                  {format_timestamp(event[:timestamp_ms])}
                </td>
                <td class="px-3 py-2 text-xs">
                  <.badge variant={source_badge_variant(event[:source])}>{event[:source]}</.badge>
                </td>
                <td class="px-3 py-2 text-xs text-js-text-muted font-mono">
                  {format_event_name(event[:event_prefix] || event[:event_name])}
                </td>
                <td class="px-3 py-2 text-xs">
                  <.badge variant={event_badge_variant(event[:type])}>
                    {to_string(event[:type] || "event")}
                  </.badge>
                </td>
                <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                  {event[:agent_id] || "—"}
                </td>
                <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                  {event[:trace_id] || "—"}
                </td>
                <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                  {event[:call_id] || "—"}
                </td>
                <td class="px-3 py-2 text-xs text-js-text-subtle font-mono max-w-xs truncate">
                  {inspect(event[:metadata] || %{}, limit: 4)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.card>
    </div>
    """
  end
end
