defmodule JidoStudio.ActionsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Observability.Actions
  alias JidoStudio.Observability.Filters

  @refresh_ms 2_500
  @default_limit 150

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Actions")
      |> assign(:filters, default_filters())
      |> assign(:actions, [])
      |> assign(:selected_action, nil)
      |> assign(:executions, [])
      |> assign(:failure_samples, [])
      |> assign(:available_modules, [])
      |> assign(:available_agents, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)
    actions = Actions.list_actions(filters: filters, limit: @default_limit)

    selected_action_id =
      case socket.assigns.live_action do
        :show -> normalize_optional_string(params["id"])
        _ -> normalize_optional_string(params["action_id"])
      end

    selected_action =
      case selected_action_id do
        nil -> nil
        id -> Enum.find(actions, &(&1[:id] == id)) || load_action(id)
      end

    executions =
      if selected_action, do: Actions.latest_executions(selected_action.id, limit: 30), else: []

    failure_samples =
      if selected_action, do: Actions.failure_samples(selected_action.id, limit: 12), else: []

    modules =
      actions
      |> Enum.map(&normalize_optional_string(&1[:agent_module]))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    agents =
      actions
      |> Enum.map(&normalize_optional_string(&1[:agent_id]))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action, selected_action))
     |> assign(:filters, filters)
     |> assign(:actions, actions)
     |> assign(:selected_action, selected_action)
     |> assign(:executions, executions)
     |> assign(:failure_samples, failure_samples)
     |> assign(:available_modules, modules)
     |> assign(:available_agents, agents)}
  end

  @impl true
  def handle_event("filters_change", %{"filters" => params}, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(parse_filters(%{"filters" => params}))

    selected_id = socket.assigns.selected_action && socket.assigns.selected_action.id

    {:noreply,
     push_patch(socket,
       to:
         list_or_detail_path(
           socket.assigns.prefix,
           socket.assigns.live_action,
           selected_id,
           filters
         )
     )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    actions = Actions.list_actions(filters: socket.assigns.filters, limit: @default_limit)

    selected_action =
      case socket.assigns.selected_action do
        %{id: id} -> Enum.find(actions, &(&1[:id] == id)) || load_action(id)
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(:actions, actions)
     |> assign(:selected_action, selected_action)
     |> assign(
       :executions,
       if(selected_action, do: Actions.latest_executions(selected_action.id, limit: 30), else: [])
     )
     |> assign(
       :failure_samples,
       if(selected_action, do: Actions.failure_samples(selected_action.id, limit: 12), else: [])
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Actions" subtitle="Action diagnostics across agents and traces">
        <:actions>
          <.badge>showing {length(@actions)} actions</.badge>
          <.badge :if={@selected_action} variant={:info}>selected {@selected_action.action}</.badge>
        </:actions>
      </.page_header>

      <.card>
        <form phx-change="filters_change" class="grid grid-cols-1 md:grid-cols-4 lg:grid-cols-8 gap-2">
          <label class="text-xs text-js-text-muted">
            Action
            <input
              type="text"
              name="filters[action]"
              value={@filters.action || ""}
              placeholder="tool.call"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>

          <label class="text-xs text-js-text-muted">
            Module
            <select
              name="filters[agent_module]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="">All</option>
              <option
                :for={module <- @available_modules}
                value={module}
                selected={module == @filters.agent_module}
              >
                {module}
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
              placeholder="trace, incident, request"
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
          <div :if={@actions == []} class="p-6">
            <.empty_state
              title="No actions"
              description="No action diagnostics matched the current filters."
            />
          </div>

          <div :if={@actions != []} class="overflow-x-auto">
            <table class="w-full">
              <thead>
                <tr class="border-b border-js-border">
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Action
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Module
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Calls
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Error Rate
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    p50/p95
                  </th>
                  <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                    Last Status
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-js-border">
                <tr :for={action <- @actions} class="hover:bg-js-bg-elevated/40">
                  <td class="px-3 py-2 text-xs text-js-info font-mono">
                    <.link
                      navigate={action_detail_path(@prefix, action.id, @filters)}
                      class="hover:text-js-text"
                    >
                      {action.action || action.id}
                    </.link>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                    {action.agent_module || "-"}
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-subtle">
                    {action.execution_count || 0}
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-subtle">
                    {format_rate(action.error_rate)}
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                    {format_duration(action.p50_duration_ms)} / {format_duration(
                      action.p95_duration_ms
                    )}
                  </td>
                  <td class="px-3 py-2 text-xs">
                    <.badge variant={status_variant(action.last_status)}>
                      {action.last_status || "running"}
                    </.badge>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.card>

        <.card>
          <%= if @selected_action do %>
            <div class="space-y-3 text-xs">
              <div class="text-sm font-semibold text-js-text">Action Detail</div>
              <div class="text-js-text-muted font-mono break-all">{@selected_action.action}</div>

              <div class="flex flex-wrap gap-2">
                <.badge variant={status_variant(@selected_action.last_status)}>
                  {@selected_action.last_status || "running"}
                </.badge>
                <.badge variant={:default}>calls:{@selected_action.execution_count || 0}</.badge>
                <.badge variant={
                  if((@selected_action.failure_count || 0) > 0, do: :warning, else: :success)
                }>
                  failures:{@selected_action.failure_count || 0}
                </.badge>
              </div>

              <div class="space-y-1 text-js-text-subtle">
                <div>
                  Agent:
                  <span class="font-mono text-js-text">{@selected_action.agent_id || "-"}</span>
                </div>
                <div>
                  Module:
                  <span class="font-mono text-js-text">{@selected_action.agent_module || "-"}</span>
                </div>
                <div>
                  Trace:
                  <span class="font-mono text-js-text">{@selected_action.trace_id || "-"}</span>
                </div>
                <div>
                  Incident:
                  <span class="font-mono text-js-text">{@selected_action.incident_id || "-"}</span>
                </div>
              </div>

              <div class="pt-2 border-t border-js-border">
                <div class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-2">
                  Jump To Related
                </div>
                <div class="flex flex-wrap gap-2">
                  <.link
                    :if={@selected_action.trace_id}
                    navigate={
                      scoped_path(
                        @prefix <> "/traces/" <> URI.encode_www_form(@selected_action.trace_id)
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Trace
                  </.link>
                  <.link
                    :if={@selected_action.incident_id}
                    navigate={
                      scoped_path(
                        @prefix <>
                          "/traces?" <>
                          URI.encode_query(%{"incident_id" => @selected_action.incident_id})
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Incident
                  </.link>
                  <.link
                    :if={@selected_action.agent_id}
                    navigate={
                      scoped_path(
                        @prefix <>
                          "/agents?" <>
                          URI.encode_query(%{"scope[agent_id]" => @selected_action.agent_id})
                      )
                    }
                    class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                  >
                    Agent Scope
                  </.link>
                </div>
              </div>

              <div class="pt-2 border-t border-js-border">
                <div class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-2">
                  Latest Executions
                </div>
                <%= if @executions == [] do %>
                  <p class="text-js-text-subtle">No execution samples available.</p>
                <% else %>
                  <div class="space-y-1.5 max-h-56 overflow-y-auto js-scroll">
                    <div
                      :for={execution <- @executions}
                      class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2 py-1.5"
                    >
                      <div class="flex items-center justify-between gap-2">
                        <span class="text-[11px] font-mono text-js-text-subtle">
                          {format_timestamp(execution.ts || execution.timestamp_ms)}
                        </span>
                        <.badge variant={status_variant(execution.status)}>
                          {execution.status || "running"}
                        </.badge>
                      </div>
                      <div class="mt-1 flex flex-wrap items-center gap-2 text-[11px] text-js-text-subtle font-mono">
                        <span>dur:{format_duration(execution.duration_ms)}</span>
                        <span>trace:{execution.trace_id || "-"}</span>
                        <.link
                          :if={execution.trace_id}
                          navigate={
                            scoped_path(
                              @prefix <> "/traces/" <> URI.encode_www_form(execution.trace_id)
                            )
                          }
                          class="text-js-info hover:text-js-text"
                        >
                          open
                        </.link>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>

              <div :if={@failure_samples != []} class="pt-2 border-t border-js-border">
                <div class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-2">
                  Failure Samples
                </div>
                <div class="space-y-1.5">
                  <div
                    :for={sample <- @failure_samples}
                    class="rounded-md border border-js-border bg-js-error/5 px-2 py-1.5"
                  >
                    <div class="flex items-center justify-between gap-2">
                      <span class="text-[11px] font-mono text-js-text-subtle">
                        {format_timestamp(sample.ts || sample.timestamp_ms)}
                      </span>
                      <.badge variant={:error}>{sample.status || "error"}</.badge>
                    </div>
                    <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                      trace:{sample.trace_id || "-"} / call:{sample.call_id || "-"}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <.empty_state
              title="Select an action"
              description="Open an action from the table to inspect recent executions and failures."
            />
          <% end %>
        </.card>
      </div>
    </div>
    """
  end

  defp default_filters do
    Filters.default_filters(%{range: "24h", status: "all", error_only: false, action: nil})
    |> Map.put(:agent_module, nil)
  end

  defp parse_filters(params) do
    source = Map.get(params, "filters", params)

    Filters.parse(params, default_filters())
    |> Map.put(:agent_module, normalize_optional_string(fetch(source, :agent_module)))
  end

  defp load_action(action_id) do
    case Actions.get_action(action_id) do
      {:ok, action} -> action
      _ -> nil
    end
  end

  defp page_title(:show, %{action: action}) when is_binary(action), do: "Action: #{action}"
  defp page_title(:show, _), do: "Action"
  defp page_title(_, _), do: "Actions"

  defp list_or_detail_path(prefix, :show, selected_id, filters) when is_binary(selected_id) do
    action_detail_path(prefix, selected_id, filters)
  end

  defp list_or_detail_path(prefix, _live_action, selected_id, filters) do
    params = Filters.to_query_params(filters, default_filters())

    params =
      if is_binary(selected_id) do
        Map.put(params, "action_id", selected_id)
      else
        params
      end

    if map_size(params) == 0 do
      scoped_path(prefix <> "/actions")
    else
      scoped_path(prefix <> "/actions?" <> URI.encode_query(params))
    end
  end

  defp action_detail_path(prefix, action_id, filters) do
    params = Filters.to_query_params(filters, default_filters())

    base = prefix <> "/actions/" <> URI.encode_www_form(action_id)

    if map_size(params) == 0 do
      scoped_path(base)
    else
      scoped_path(base <> "?" <> URI.encode_query(params))
    end
  end

  defp scoped_path(path) do
    Scope.with_scope_query(path, Scope.current_node_param())
  end

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp fetch(_, _), do: nil

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

  defp format_rate(value) when is_float(value),
    do: :erlang.float_to_binary(value * 100.0, decimals: 1) <> "%"

  defp format_rate(value) when is_integer(value), do: "#{value * 100}%"
  defp format_rate(_), do: "0.0%"

  defp format_timestamp(ts) when is_integer(ts) and ts > 0 do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S.%f")
    |> String.slice(0, 12)
  end

  defp format_timestamp(_), do: "-"
end
