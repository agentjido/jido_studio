defmodule JidoStudio.WorkflowsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Observability.Filters
  alias JidoStudio.Observability.Workflows

  @refresh_ms 2_500
  @default_limit 150

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Workflows")
      |> assign(:filters, default_filters())
      |> assign(:runs, [])
      |> assign(:selected_run, nil)
      |> assign(:timeline, [])
      |> assign(:available_workflows, [])
      |> assign(:available_agents, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Filters.parse(params, default_filters())
    runs = Workflows.list_runs(filters: filters, limit: @default_limit)

    selected_run_id =
      case socket.assigns.live_action do
        :show -> normalize_optional_string(params["id"])
        _ -> normalize_optional_string(params["run_id"])
      end

    selected_run =
      case selected_run_id do
        nil -> nil
        id -> Enum.find(runs, &(&1[:id] == id)) || load_run(id)
      end

    timeline = if selected_run, do: Workflows.run_timeline(selected_run.id, limit: 300), else: []

    available_workflows =
      runs
      |> Enum.map(&normalize_optional_string(&1[:workflow_id]))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    available_agents =
      runs
      |> Enum.map(&normalize_optional_string(&1[:agent_id]))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action, selected_run))
     |> assign(:filters, filters)
     |> assign(:runs, runs)
     |> assign(:selected_run, selected_run)
     |> assign(:timeline, timeline)
     |> assign(:available_workflows, available_workflows)
     |> assign(:available_agents, available_agents)}
  end

  @impl true
  def handle_event("filters_change", %{"filters" => params}, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Filters.parse(%{"filters" => params}, default_filters()))

    selected_run_id = socket.assigns.selected_run && socket.assigns.selected_run.id

    {:noreply,
     push_patch(socket,
       to:
         list_or_detail_path(
           socket.assigns.prefix,
           socket.assigns.live_action,
           selected_run_id,
           filters
         )
     )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    runs = Workflows.list_runs(filters: socket.assigns.filters, limit: @default_limit)

    selected_run =
      case socket.assigns.selected_run do
        %{id: id} -> Enum.find(runs, &(&1[:id] == id)) || load_run(id)
        _ -> nil
      end

    timeline = if selected_run, do: Workflows.run_timeline(selected_run.id, limit: 300), else: []

    {:noreply,
     socket
     |> assign(:runs, runs)
     |> assign(:selected_run, selected_run)
     |> assign(:timeline, timeline)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Workflows" subtitle="Workflow execution analysis and run triage">
        <:actions>
          <.badge>showing {length(@runs)} runs</.badge>
          <.badge :if={Enum.any?(@runs, &(&1.stalled? == true))} variant={:warning}>
            stalled {Enum.count(@runs, &(&1.stalled? == true))}
          </.badge>
        </:actions>
      </.page_header>

      <.card>
        <form phx-change="filters_change" class="grid grid-cols-1 md:grid-cols-4 lg:grid-cols-8 gap-2">
          <label class="text-xs text-js-text-muted">
            Workflow
            <select
              name="filters[workflow_id]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="">All</option>
              <option
                :for={workflow_id <- @available_workflows}
                value={workflow_id}
                selected={workflow_id == @filters.workflow_id}
              >
                {workflow_id}
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
              <option value="all" selected={@filters.range == "all"}>All</option>
            </select>
          </label>

          <label class="text-xs text-js-text-muted">
            Project ID
            <input
              type="text"
              name="filters[project_id]"
              value={@filters.project_id || ""}
              placeholder="project"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>

          <label class="text-xs text-js-text-muted">
            User ID
            <input
              type="text"
              name="filters[user_id]"
              value={@filters.user_id || ""}
              placeholder="user"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>

          <label class="text-xs text-js-text-muted">
            Query
            <input
              type="text"
              name="filters[query]"
              value={@filters.query || ""}
              placeholder="trace, incident, step"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>

          <div class="flex items-end gap-4">
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
            <label class="text-xs text-js-text-muted flex items-end gap-2">
              <input type="hidden" name="filters[stalled_only]" value="false" />
              <input
                type="checkbox"
                name="filters[stalled_only]"
                value="true"
                checked={@filters.stalled_only == true}
                class="rounded border-js-border bg-js-bg-elevated"
              /> Stalled only
            </label>
          </div>
        </form>
      </.card>

      <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] gap-4">
        <.card class="p-0 overflow-hidden">
          <div :if={@runs == []} class="p-6">
            <.empty_state
              title="No workflow runs"
              description="No workflow runs matched the current filters."
            />
          </div>

          <div :if={@runs != []} class="overflow-x-auto">
            <table class="w-full">
              <thead>
                <tr class="border-b border-js-border">
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Run ID
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Workflow
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Agent
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Status
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Duration
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Last Step
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-js-border">
                <tr
                  :for={run <- @runs}
                  class={["hover:bg-js-bg-elevated/40", if(run.stalled?, do: "bg-js-warning/5")]}
                >
                  <td class="px-3 py-2 text-xs text-js-info font-mono">
                    <.link
                      navigate={run_detail_path(@prefix, run.id, @filters)}
                      class="hover:text-js-text"
                    >
                      {run.run_id || run.id}
                    </.link>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                    {run.workflow_id || "-"}
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                    {run.agent_id || "-"}
                  </td>
                  <td class="px-3 py-2 text-xs">
                    <.badge variant={status_variant(run.status)}>{run.status || "running"}</.badge>
                    <.badge :if={run.stalled?} variant={:warning}>stalled</.badge>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                    {format_duration(run.duration_ms)}
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                    {run.last_step || "-"}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.card>

        <.card>
          <%= if @selected_run do %>
            <div class="space-y-3 text-xs">
              <div class="text-sm font-semibold text-js-text">Workflow Run Detail</div>
              <div class="text-js-text-muted font-mono break-all">
                {@selected_run.workflow_id} / {@selected_run.run_id}
              </div>

              <div class="flex flex-wrap gap-2">
                <.badge variant={status_variant(@selected_run.status)}>
                  {@selected_run.status || "running"}
                </.badge>
                <.badge :if={@selected_run.stalled?} variant={:warning}>stalled</.badge>
                <.badge variant={:default}>dur:{format_duration(@selected_run.duration_ms)}</.badge>
              </div>

              <div class="space-y-1 text-js-text-subtle">
                <div>
                  Trace: <span class="font-mono text-js-text">{@selected_run.trace_id || "-"}</span>
                </div>
                <div>
                  Incident:
                  <span class="font-mono text-js-text">{@selected_run.incident_id || "-"}</span>
                </div>
                <div>
                  Agent: <span class="font-mono text-js-text">{@selected_run.agent_id || "-"}</span>
                </div>
                <div>
                  Request:
                  <span class="font-mono text-js-text">{@selected_run.request_id || "-"}</span>
                </div>
              </div>

              <div class="pt-2 border-t border-js-border">
                <div class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-2">
                  Jump To Related
                </div>
                <div class="flex flex-wrap gap-2">
                  <.link
                    :if={@selected_run.trace_id}
                    navigate={
                      scoped_path(
                        @prefix <> "/traces/" <> URI.encode_www_form(@selected_run.trace_id)
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Trace
                  </.link>
                  <.link
                    :if={@selected_run.incident_id}
                    navigate={
                      scoped_path(
                        @prefix <>
                          "/traces?" <>
                          URI.encode_query(%{"incident_id" => @selected_run.incident_id})
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Incident
                  </.link>
                  <.link
                    :if={@selected_run.agent_id}
                    navigate={
                      scoped_path(
                        @prefix <>
                          "/agents?" <>
                          URI.encode_query(%{"scope[agent_id]" => @selected_run.agent_id})
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Agent Scope
                  </.link>
                  <.link
                    :if={@selected_run.workflow_id}
                    navigate={
                      scoped_path(
                        @prefix <>
                          "/signals?" <>
                          URI.encode_query(%{"workflow_id" => @selected_run.workflow_id})
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Signals
                  </.link>
                </div>
              </div>

              <div class="pt-2 border-t border-js-border">
                <div class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-2">
                  Run Timeline
                </div>
                <%= if @timeline == [] do %>
                  <p class="text-js-text-subtle">No timeline events recorded for this run.</p>
                <% else %>
                  <div class="space-y-1.5 max-h-64 overflow-y-auto js-scroll">
                    <div
                      :for={event <- @timeline}
                      class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2 py-1.5"
                    >
                      <div class="flex items-center justify-between gap-2">
                        <span class="text-[11px] font-mono text-js-text-subtle">
                          {format_timestamp(event.ts || event.timestamp_ms)}
                        </span>
                        <.badge variant={status_variant(event.status)}>
                          {event.status || event.type || "running"}
                        </.badge>
                      </div>
                      <div class="mt-1 text-[11px] text-js-text font-mono truncate">
                        {event.action || event.signal_type || event.event_name || "step"}
                      </div>
                      <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                        trace:{event.trace_id || "-"} / incident:{event.incident_id || "-"}
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% else %>
            <.empty_state
              title="Select a workflow run"
              description="Open a run to inspect timeline steps and correlated traces/signals/actions."
            />
          <% end %>
        </.card>
      </div>
    </div>
    """
  end

  defp default_filters do
    Filters.default_filters(%{
      range: "24h",
      status: "all",
      error_only: false,
      stalled_only: false
    })
  end

  defp load_run(run_id) do
    case Workflows.get_run(run_id) do
      {:ok, run} -> run
      _ -> nil
    end
  end

  defp page_title(:show, %{workflow_id: workflow_id}) when is_binary(workflow_id),
    do: "Workflow: #{workflow_id}"

  defp page_title(:show, _), do: "Workflow"
  defp page_title(_, _), do: "Workflows"

  defp list_or_detail_path(prefix, :show, selected_id, filters) when is_binary(selected_id) do
    run_detail_path(prefix, selected_id, filters)
  end

  defp list_or_detail_path(prefix, _live_action, selected_id, filters) do
    params = Filters.to_query_params(filters, default_filters())

    params =
      if is_binary(selected_id) do
        Map.put(params, "run_id", selected_id)
      else
        params
      end

    if map_size(params) == 0 do
      scoped_path(prefix <> "/workflows")
    else
      scoped_path(prefix <> "/workflows?" <> URI.encode_query(params))
    end
  end

  defp run_detail_path(prefix, run_id, filters) do
    params = Filters.to_query_params(filters, default_filters())

    base = prefix <> "/workflows/" <> URI.encode_www_form(run_id)

    if map_size(params) == 0 do
      scoped_path(base)
    else
      scoped_path(base <> "?" <> URI.encode_query(params))
    end
  end

  defp scoped_path(path) do
    Scope.with_scope_query(path, Scope.current_node_param())
  end

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

  defp format_duration(value) when is_integer(value) and value >= 0, do: "#{value}ms"
  defp format_duration(_), do: "-"

  defp format_timestamp(ts) when is_integer(ts) and ts > 0 do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S.%f")
    |> String.slice(0, 12)
  end

  defp format_timestamp(_), do: "-"
end
