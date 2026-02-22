defmodule JidoStudio.ActivityLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Cluster.RPC
  alias JidoStudio.Cluster.Scope
  alias JidoStudio.ScopeQuery
  alias JidoStudio.Observability.Actions
  alias JidoStudio.Observability.Signals
  alias JidoStudio.Observability.Workflows
  alias JidoStudio.Tracing

  @refresh_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Activity")
      |> assign(:summary, %{})
      |> assign(:timeline, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, refresh_activity(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, refresh_activity(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Activity" subtitle="Recent runtime activity and operational trends">
        <:actions>
          <.badge variant={:default}>runtime:{@runtime_key || "default"}</.badge>
          <.badge variant={:info}>node:{@cluster_node_param || "all"}</.badge>
        </:actions>
      </.page_header>

      <.card class="py-3">
        <p class="text-xs text-js-text-muted">
          What this page is for: monitor the live stream of signals, actions, workflow runs, and traces before drilling into detailed diagnostics.
        </p>
      </.card>

      <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <.stat_card label="Signals" value={to_string(@summary.signal_count || 0)} />
        <.stat_card label="Actions" value={to_string(@summary.action_count || 0)} />
        <.stat_card label="Workflows" value={to_string(@summary.workflow_count || 0)} />
        <.stat_card label="Errors" value={to_string(@summary.error_count || 0)} />
      </div>

      <.card>
        <div class="flex items-center justify-between">
          <h2 class="text-sm font-semibold text-js-text">Operational Timeline</h2>
          <div class="flex gap-2">
            <.link
              navigate={page_path(@prefix, "/signals", @runtime_key, @cluster_node_param)}
              class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Signals
            </.link>
            <.link
              navigate={page_path(@prefix, "/actions", @runtime_key, @cluster_node_param)}
              class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Actions
            </.link>
            <.link
              navigate={page_path(@prefix, "/workflows", @runtime_key, @cluster_node_param)}
              class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Workflows
            </.link>
            <.link
              navigate={page_path(@prefix, "/traces", @runtime_key, @cluster_node_param)}
              class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Traces
            </.link>
          </div>
        </div>

        <div :if={@timeline == []} class="mt-4">
          <.empty_state
            title="No recent activity"
            description="Activity appears here as agents emit signals, actions, workflow runs, and traces."
          />
        </div>

        <div :if={@timeline != []} class="mt-3 divide-y divide-js-border">
          <div :for={item <- @timeline} class="py-2 flex items-center justify-between gap-3">
            <div class="min-w-0">
              <div class="text-xs text-js-text truncate">{item.title}</div>
              <div class="text-[11px] text-js-text-subtle font-mono truncate">{item.subtitle}</div>
            </div>
            <div class="flex items-center gap-2">
              <.badge variant={item.variant}>{item.kind}</.badge>
              <span class="text-[11px] text-js-text-subtle font-mono whitespace-nowrap">
                {item.when}
              </span>
            </div>
          </div>
        </div>
      </.card>
    </div>
    """
  end

  defp refresh_activity(socket) do
    scope = socket.assigns.cluster_scope

    signals = collect(scope, Signals, :list_signals, [[limit: 60, filters: %{range: "1h"}]])
    actions = collect(scope, Actions, :list_actions, [[limit: 40, filters: %{range: "1h"}]])
    workflows = collect(scope, Workflows, :list_runs, [[limit: 40, filters: %{range: "1h"}]])
    traces = collect(scope, Tracing, :list_traces, [[filters: %{range: "1h"}, limit: 40]])

    timeline =
      signals_to_events(signals) ++
        actions_to_events(actions) ++
        workflows_to_events(workflows) ++
        traces_to_events(traces)

    timeline =
      timeline
      |> Enum.sort_by(&(&1.ts || 0), :desc)
      |> Enum.take(80)

    summary = %{
      signal_count: length(signals),
      action_count: length(actions),
      workflow_count: length(workflows),
      error_count: Enum.count(timeline, &(&1.variant == :error))
    }

    socket
    |> assign(:summary, summary)
    |> assign(:timeline, timeline)
  end

  defp collect(:all, module, fun, args) do
    case RPC.call(:all, module, fun, args) do
      {:ok, results} when is_list(results) ->
        results
        |> Enum.flat_map(fn
          %{ok?: true, value: items} when is_list(items) -> items
          _ -> []
        end)

      _ ->
        []
    end
  end

  defp collect(scope, module, fun, args) do
    node = Scope.selected_node(scope) || Node.self()

    case RPC.call({:node, node}, module, fun, args) do
      {:ok, items} when is_list(items) -> items
      _ -> []
    end
  end

  defp signals_to_events(signals) do
    signals
    |> Enum.take(20)
    |> Enum.map(fn signal ->
      status = normalize_status(signal[:status])

      %{
        ts: signal[:ts] || signal[:timestamp_ms] || 0,
        kind: "signal",
        title: signal[:signal_type] || signal[:event_name] || "Signal",
        subtitle: [signal[:agent_id], signal[:trace_id]] |> compact_join(" / "),
        when: format_timestamp(signal[:ts] || signal[:timestamp_ms]),
        variant: status_variant(status)
      }
    end)
  end

  defp actions_to_events(actions) do
    actions
    |> Enum.take(20)
    |> Enum.map(fn action ->
      status = normalize_status(action[:last_status])

      %{
        ts: action[:last_event_at] || action[:updated_at] || 0,
        kind: "action",
        title: action[:action] || action[:id] || "Action",
        subtitle: [action[:agent_id], action[:trace_id]] |> compact_join(" / "),
        when: format_timestamp(action[:last_event_at] || action[:updated_at]),
        variant: status_variant(status)
      }
    end)
  end

  defp workflows_to_events(runs) do
    runs
    |> Enum.take(20)
    |> Enum.map(fn run ->
      status = normalize_status(run[:status])

      %{
        ts: run[:last_event_at] || run[:updated_at] || 0,
        kind: "workflow",
        title: run[:workflow_id] || run[:run_id] || "Workflow",
        subtitle: [run[:agent_id], run[:trace_id]] |> compact_join(" / "),
        when: format_timestamp(run[:last_event_at] || run[:updated_at]),
        variant: status_variant(status)
      }
    end)
  end

  defp traces_to_events(traces) do
    traces
    |> Enum.take(20)
    |> Enum.map(fn trace ->
      status = normalize_status(trace[:status])

      %{
        ts: trace[:last_event_at] || trace[:started_at] || 0,
        kind: "trace",
        title: trace[:trace_id] || trace[:id] || "Trace",
        subtitle: [trace[:agent_id], trace[:incident_id]] |> compact_join(" / "),
        when: format_timestamp(trace[:last_event_at] || trace[:started_at]),
        variant: status_variant(status)
      }
    end)
  end

  defp compact_join(items, separator) do
    items
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.map(&to_string/1)
    |> Enum.join(separator)
  end

  defp normalize_status(status) when status in ["ok", :ok], do: "ok"
  defp normalize_status(status) when status in ["error", :error], do: "error"
  defp normalize_status(_), do: "running"

  defp status_variant("error"), do: :error
  defp status_variant("ok"), do: :success
  defp status_variant(_), do: :default

  defp format_timestamp(ts) when is_integer(ts) and ts > 0 do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp format_timestamp(_), do: "-"

  defp page_path(prefix, suffix, runtime_key, node_param) do
    ScopeQuery.with_scope_query(prefix <> suffix, runtime_key, node_param)
  end
end
