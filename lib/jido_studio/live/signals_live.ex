defmodule JidoStudio.SignalsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Observability.Filters
  alias JidoStudio.Observability.Signals

  @refresh_ms 2_000
  @default_limit 250

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Signals")
      |> assign(:filters, default_filters())
      |> assign(:signals, [])
      |> assign(:selected_signal, nil)
      |> assign(:summary, %{total: 0, errors: 0, by_type: [], by_agent: []})
      |> assign(:signal_types, [])
      |> assign(:available_agents, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Filters.parse(params, default_filters())
    selected_id = normalize_signal_id(params["signal"])

    signals = Signals.list_signals(filters: filters, limit: @default_limit)

    selected_signal =
      Enum.find(signals, fn signal ->
        signal[:seq] == selected_id
      end)

    selected_signal =
      if is_nil(selected_signal) and is_integer(selected_id) do
        Signals.get_signal(selected_id, filters: filters, limit: 400)
      else
        selected_signal
      end

    summary = Signals.summary(filters: filters)

    signal_types =
      signals
      |> Enum.map(&normalize_optional_string(&1[:signal_type]))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    available_agents =
      signals
      |> Enum.map(&normalize_optional_string(&1[:agent_id]))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:signals, signals)
     |> assign(:selected_signal, selected_signal)
     |> assign(:summary, summary)
     |> assign(:signal_types, signal_types)
     |> assign(:available_agents, available_agents)}
  end

  @impl true
  def handle_event("filters_change", %{"filters" => params}, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Filters.parse(%{"filters" => params}, default_filters()))

    {:noreply,
     push_patch(socket,
       to: list_path(socket.assigns.prefix, filters, socket.assigns.selected_signal)
     )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    filters = socket.assigns.filters

    signals = Signals.list_signals(filters: filters, limit: @default_limit)

    selected_signal =
      case socket.assigns.selected_signal do
        %{seq: seq} -> Enum.find(signals, &(&1[:seq] == seq)) || socket.assigns.selected_signal
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(:signals, signals)
     |> assign(:summary, Signals.summary(filters: filters))
     |> assign(:selected_signal, selected_signal)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Signals" subtitle="Live signal stream for cross-agent debugging">
        <:actions>
          <.badge variant={if(@summary.errors > 0, do: :warning, else: :default)}>
            {@summary.total} signals
          </.badge>
          <.badge :if={@summary.errors > 0} variant={:error}>{@summary.errors} errors</.badge>
        </:actions>
      </.page_header>

      <.card>
        <form phx-change="filters_change" class="grid grid-cols-1 md:grid-cols-4 lg:grid-cols-8 gap-2">
          <label class="text-xs text-js-text-muted">
            Signal Type
            <select
              name="filters[signal_type]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="">All</option>
              <option
                :for={signal_type <- @signal_types}
                value={signal_type}
                selected={signal_type == @filters.signal_type}
              >
                {signal_type}
              </option>
            </select>
          </label>

          <label class="text-xs text-js-text-muted">
            Agent
            <select
              name="filters[agent_id]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="">All</option>
              <option
                :for={agent <- @available_agents}
                value={agent}
                selected={agent == @filters.agent_id}
              >
                {agent}
              </option>
            </select>
          </label>

          <label class="text-xs text-js-text-muted">
            Project ID
            <input
              type="text"
              name="filters[project_id]"
              value={@filters.project_id || ""}
              placeholder="project scope"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>

          <label class="text-xs text-js-text-muted">
            User ID
            <input
              type="text"
              name="filters[user_id]"
              value={@filters.user_id || ""}
              placeholder="user scope"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
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
              <option value="7d" selected={@filters.range == "7d"}>7d</option>
              <option value="custom" selected={@filters.range == "custom"}>Custom</option>
              <option value="all" selected={@filters.range == "all"}>All</option>
            </select>
          </label>

          <label class="text-xs text-js-text-muted">
            Query
            <input
              type="text"
              name="filters[query]"
              value={@filters.query || ""}
              placeholder="trace, request, metadata"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>

          <label class="text-xs text-js-text-muted flex items-end gap-2">
            <input type="hidden" name="filters[error_only]" value="false" />
            <input
              type="checkbox"
              name="filters[error_only]"
              value="true"
              checked={@filters.error_only == true}
              class="rounded border-js-border bg-js-bg-elevated"
            /> Error only
          </label>
        </form>
      </.card>

      <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] gap-4">
        <.card class="p-0 overflow-hidden">
          <div :if={@signals == []} class="p-6">
            <.empty_state
              title="No signals"
              description="No signal events matched the current filters."
            />
          </div>

          <div :if={@signals != []} class="overflow-x-auto">
            <table class="w-full">
              <thead>
                <tr class="border-b border-js-border">
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Time
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Signal
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Agent
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Status
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Trace
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-js-border">
                <tr :for={signal <- @signals} class="hover:bg-js-bg-elevated/40">
                  <td class="px-3 py-2 text-xs text-js-text-subtle font-mono whitespace-nowrap">
                    <.link
                      patch={detail_path(@prefix, signal[:seq], @filters)}
                      class="text-js-info hover:text-js-text"
                    >
                      {format_timestamp(signal[:ts] || signal[:timestamp_ms])}
                    </.link>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text font-mono">
                    {signal[:signal_type] || signal[:event_name] || "signal"}
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-muted font-mono">
                    {signal[:agent_id] || "-"}
                  </td>
                  <td class="px-3 py-2 text-xs">
                    <.badge variant={status_variant(signal[:status])}>
                      {signal[:status] || "running"}
                    </.badge>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                    {signal[:trace_id] || "-"}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.card>

        <.card>
          <%= if @selected_signal do %>
            <div class="space-y-3 text-xs">
              <div class="text-sm font-semibold text-js-text">Signal Detail</div>
              <div class="text-js-text-muted font-mono break-all">
                {@selected_signal.signal_type || @selected_signal.event_name || "signal"}
              </div>
              <div class="flex flex-wrap gap-2">
                <.badge variant={status_variant(@selected_signal.status)}>
                  {@selected_signal.status || "running"}
                </.badge>
                <.badge variant={:default}>
                  trace:{@selected_signal.trace_id || "-"}
                </.badge>
                <.badge variant={:default}>
                  incident:{@selected_signal.incident_id || "-"}
                </.badge>
              </div>

              <div class="space-y-1 text-js-text-subtle">
                <div>
                  Agent:
                  <span class="font-mono text-js-text">{@selected_signal.agent_id || "-"}</span>
                </div>
                <div>
                  Project:
                  <span class="font-mono text-js-text">{@selected_signal.project_id || "-"}</span>
                </div>
                <div>
                  User: <span class="font-mono text-js-text">{@selected_signal.user_id || "-"}</span>
                </div>
                <div>
                  Request:
                  <span class="font-mono text-js-text">{@selected_signal.request_id || "-"}</span>
                </div>
                <div>
                  Action: <span class="font-mono text-js-text">{@selected_signal.action || "-"}</span>
                </div>
                <div>
                  Workflow:
                  <span class="font-mono text-js-text">{@selected_signal.workflow_id || "-"}</span>
                </div>
              </div>

              <div class="pt-2 border-t border-js-border">
                <div class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-2">
                  Jump To Related
                </div>
                <div class="flex flex-wrap gap-2">
                  <.link
                    :if={@selected_signal.trace_id}
                    navigate={
                      scoped_path(
                        @prefix <> "/traces/" <> URI.encode_www_form(@selected_signal.trace_id)
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Trace Timeline
                  </.link>
                  <.link
                    :if={@selected_signal.incident_id}
                    navigate={
                      scoped_path(
                        @prefix <>
                          "/traces?" <>
                          URI.encode_query(%{"incident_id" => @selected_signal.incident_id})
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Incident Hub
                  </.link>
                  <.link
                    :if={@selected_signal.agent_id}
                    navigate={
                      scoped_path(
                        @prefix <>
                          "/agents?" <>
                          URI.encode_query(%{"scope[agent_id]" => @selected_signal.agent_id})
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Agent Scope
                  </.link>
                  <.link
                    :if={@selected_signal.action}
                    navigate={
                      scoped_path(
                        @prefix <>
                          "/actions?" <> URI.encode_query(%{"action" => @selected_signal.action})
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Action Diagnostics
                  </.link>
                </div>
              </div>

              <div class="pt-2 border-t border-js-border">
                <div class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-1">
                  Metadata
                </div>
                <pre class="text-xs text-js-text-muted bg-js-bg-elevated border border-js-border rounded-md p-2 whitespace-pre-wrap break-words"><%= inspect(@selected_signal.metadata || %{}, pretty: true, limit: 60, printable_limit: 12_000) %></pre>
              </div>
            </div>
          <% else %>
            <.empty_state
              title="Select a signal"
              description="Choose a signal row to inspect metadata and jump to related traces/incidents."
            />
          <% end %>
        </.card>
      </div>
    </div>
    """
  end

  defp default_filters do
    Filters.default_filters(%{range: "1h", status: "all", error_only: false})
  end

  defp list_path(prefix, filters, selected_signal) do
    params = Filters.to_query_params(filters, default_filters())

    params =
      if is_map(selected_signal) and is_integer(selected_signal[:seq]) do
        Map.put(params, "signal", Integer.to_string(selected_signal[:seq]))
      else
        params
      end

    if map_size(params) == 0 do
      scoped_path(prefix <> "/signals")
    else
      scoped_path(prefix <> "/signals?" <> URI.encode_query(params))
    end
  end

  defp detail_path(prefix, signal_id, filters) do
    params =
      Filters.to_query_params(filters, default_filters())
      |> Map.put("signal", to_string(signal_id))

    scoped_path(prefix <> "/signals?" <> URI.encode_query(params))
  end

  defp scoped_path(path) do
    Scope.with_scope_query(path, Scope.current_node_param())
  end

  defp normalize_signal_id(nil), do: nil

  defp normalize_signal_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_signal_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_signal_id(_), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_), do: nil

  defp status_variant("error"), do: :error
  defp status_variant("ok"), do: :success
  defp status_variant("running"), do: :info
  defp status_variant(:error), do: :error
  defp status_variant(:ok), do: :success
  defp status_variant(:running), do: :info
  defp status_variant(_), do: :default

  defp format_timestamp(ts) when is_integer(ts) and ts > 0 do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S.%f")
    |> String.slice(0, 12)
  end

  defp format_timestamp(_), do: "-"
end
