defmodule JidoStudio.HomeLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.AgentRegistry
  alias JidoStudio.Cluster.RPC
  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Observability.Incidents
  alias JidoStudio.Tracing

  @refresh_ms 4_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Home")
      |> assign(:summary, %{})
      |> assign(:attention_items, [])
      |> assign(:top_agents, [])
      |> assign(:recent_activity, [])
      |> assign(:recent_failures, [])
      |> assign(:home_warning, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, refresh_home(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, refresh_home(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Home" subtitle="Your agent fleet at a glance">
        <:actions>
          <.badge variant={:info}>scope:{@cluster_node_param || "all"}</.badge>
        </:actions>
      </.page_header>

      <.card class="py-3">
        <p class="text-xs text-js-text-muted">
          What this page is for: quickly answer "is everything healthy?" and jump into Agents, Activity, or Diagnostics when attention is needed.
        </p>
        <p :if={@home_warning} class="mt-2 text-xs text-js-warning">{@home_warning}</p>
      </.card>

      <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <.stat_card label="Agents Online" value={to_string(@summary.online_agents || 0)} />
        <.stat_card label="Agents Available" value={to_string(@summary.available_agents || 0)} />
        <.stat_card label="Active Incidents" value={to_string(@summary.active_incidents || 0)} />
        <.stat_card label="Cluster Nodes" value={to_string(@summary.node_count || 1)} />
      </div>

      <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-4">
        <.card>
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold text-js-text">Attention Needed</h2>
            <.badge :if={@attention_items != []} variant={:warning}>
              {length(@attention_items)}
            </.badge>
          </div>

          <div :if={@attention_items == []} class="mt-4">
            <.empty_state
              title="No active alerts"
              description="No incident spikes or recent error-heavy traces were detected."
            />
          </div>

          <div :if={@attention_items != []} class="mt-3 space-y-2">
            <div
              :for={item <- @attention_items}
              class="rounded-md border border-js-border bg-js-bg-elevated px-3 py-2"
            >
              <div class="text-xs text-js-text font-medium">{item.title}</div>
              <p class="mt-1 text-xs text-js-text-muted">{item.description}</p>
            </div>
          </div>

          <div class="mt-4 flex flex-wrap gap-2">
            <.link
              navigate={page_path(@prefix, "/agents", @cluster_node_param)}
              class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Open Agents
            </.link>
            <.link
              navigate={page_path(@prefix, "/activity", @cluster_node_param)}
              class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Open Activity
            </.link>
            <.link
              navigate={page_path(@prefix, "/diagnostics", @cluster_node_param)}
              class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Open Diagnostics
            </.link>
          </div>
        </.card>

        <.card>
          <h2 class="text-sm font-semibold text-js-text">Top Agents</h2>
          <div :if={@top_agents == []} class="mt-4">
            <.empty_state
              title="No active agents"
              description="Start an agent instance to see fleet rankings and activity."
            />
          </div>
          <div :if={@top_agents != []} class="mt-3 space-y-2">
            <div
              :for={agent <- @top_agents}
              class="flex items-center justify-between rounded-md border border-js-border bg-js-bg-elevated px-3 py-2"
            >
              <div>
                <div class="text-xs text-js-text">{agent.name}</div>
                <div class="text-[11px] text-js-text-subtle font-mono">{inspect(agent.module)}</div>
              </div>
              <.badge variant={:default}>{length(agent.running_instances || [])} running</.badge>
            </div>
          </div>
        </.card>
      </div>

      <.card>
        <h2 class="text-sm font-semibold text-js-text">Recent Activity</h2>

        <div :if={@recent_activity == []} class="mt-4">
          <.empty_state
            title="No recent trace activity"
            description="Trace data appears here once agents execute actions or workflows."
          />
        </div>

        <div :if={@recent_activity != []} class="mt-3 divide-y divide-js-border">
          <div :for={item <- @recent_activity} class="py-2 flex items-center justify-between gap-3">
            <div class="min-w-0">
              <div class="text-xs text-js-text truncate">{item.title}</div>
              <div class="text-[11px] text-js-text-subtle font-mono truncate">{item.subtitle}</div>
            </div>
            <div class="text-[11px] text-js-text-subtle font-mono whitespace-nowrap">{item.when}</div>
          </div>
        </div>
      </.card>
    </div>
    """
  end

  defp refresh_home(socket) do
    scope = socket.assigns.cluster_scope
    jido_instance = socket.assigns[:jido_instance]

    agents = AgentRegistry.list_agents(jido_instance: jido_instance, scope: scope)
    incidents = cluster_incidents(scope)
    traces = cluster_traces(scope)

    summary = %{
      online_agents: Enum.count(agents, &((&1.running_instances || []) != [])),
      available_agents: Enum.count(agents, &((&1.running_instances || []) == [])),
      running_instances: Enum.reduce(agents, 0, &(&2 + length(&1.running_instances || []))),
      active_incidents: Enum.count(incidents, &incident_active?/1),
      node_count: node_count(scope)
    }

    top_agents =
      agents
      |> Enum.sort_by(&length(&1.running_instances || []), :desc)
      |> Enum.take(5)

    attention_items =
      []
      |> maybe_add_attention(summary.active_incidents > 0, %{
        title: "#{summary.active_incidents} active incidents",
        description: "Open Activity or Diagnostics to inspect current failures and timelines."
      })
      |> maybe_add_attention(Enum.any?(traces, &(&1[:status] == "error")), %{
        title: "Recent error traces detected",
        description: "A trace ended with errors in the current scope within the recent window."
      })

    recent_failures =
      incidents
      |> Enum.filter(&incident_active?/1)
      |> Enum.take(5)

    recent_activity =
      traces
      |> Enum.take(8)
      |> Enum.map(fn trace ->
        %{
          title: trace[:trace_id] || trace[:id] || "trace",
          subtitle:
            [trace[:agent_id], trace[:status]] |> Enum.reject(&is_nil/1) |> Enum.join(" / "),
          when: format_timestamp(trace[:last_event_at] || trace[:started_at])
        }
      end)

    warning = if scope != :all and node_count(scope) == 1, do: nil, else: nil

    socket
    |> assign(:summary, summary)
    |> assign(:top_agents, top_agents)
    |> assign(:attention_items, attention_items)
    |> assign(:recent_activity, recent_activity)
    |> assign(:recent_failures, recent_failures)
    |> assign(:home_warning, warning)
  end

  defp cluster_incidents(scope) do
    scope
    |> collect(Incidents, :list_incidents, [%{range: "24h"}, 40])
    |> Enum.uniq_by(&(&1[:incident_id] || &1[:id]))
    |> Enum.sort_by(&(&1[:last_event_at] || 0), :desc)
  end

  defp cluster_traces(scope) do
    scope
    |> collect(Tracing, :list_traces, [[filters: %{range: "24h"}, limit: 30]])
    |> Enum.uniq_by(&(&1[:trace_id] || &1[:id]))
    |> Enum.sort_by(&(&1[:last_event_at] || &1[:started_at] || 0), :desc)
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

  defp node_count(:all), do: length(Scope.available_nodes())
  defp node_count(_), do: 1

  defp incident_active?(incident) when is_map(incident) do
    status = to_string(incident[:status] || "")
    error_count = incident[:error_count] || 0

    status == "error" or error_count > 0
  end

  defp incident_active?(_), do: false

  defp maybe_add_attention(items, true, item), do: [item | items]
  defp maybe_add_attention(items, false, _item), do: items

  defp format_timestamp(ts) when is_integer(ts) and ts > 0 do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp format_timestamp(_), do: "-"

  defp page_path(prefix, suffix, node_param) do
    Scope.with_scope_query(prefix <> suffix, node_param)
  end
end
