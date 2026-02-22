defmodule JidoStudio.Live.AgentsLive.Render.WorkbenchPanels.Configure do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components
  import JidoStudio.Live.AgentsLive.Panes
  import JidoStudio.Live.AgentsLive.Support

  alias JidoStudio.Live.AgentsLive.ObservabilityState

  def panel(assigns) do
    ~H"""
    <%= case @workbench_tab do %>
      <% :instance -> %>
        <.settings_pane
          class="min-h-[20rem] lg:min-h-0 lg:h-full"
          agent={@agent}
          detail_tab={@detail_tab}
          detail_tabs={@detail_tabs}
          sections_by_tab={@sections_by_tab}
          system_prompt={@system_prompt}
          module_path={@module_path}
          instance_links={@instance_links}
          active_instance_id={@active_instance_id}
          active_instance_pid={@active_instance_pid}
          traces_path={@traces_path}
          instance_debug_enabled?={@instance_debug_enabled?}
          instance_debug_level={@instance_debug_level}
          instance_debug_error={@instance_debug_error}
          instance_observability_events={@instance_observability_events}
        />
      <% :sub_agents -> %>
        <.card class="min-h-0 h-full overflow-hidden p-0">
          <div class="px-3 py-2 border-b border-js-border">
            <h3 class="text-sm font-medium text-js-text">Sub-Agents</h3>
            <p class="text-xs text-js-text-muted mt-1">
              Delegated child agent activity inferred from runtime traces.
            </p>
          </div>
          <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
            <%= if @subagents == [] do %>
              <.empty_state
                title="No sub-agent records"
                description="No delegation metadata was found for this instance."
              />
            <% else %>
              <div
                :for={sub <- @subagents}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
              >
                <div class="flex items-center justify-between gap-2">
                  <div class="min-w-0">
                    <span class="text-xs text-js-text font-mono break-all">{sub.agent_id}</span>
                    <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                      parent: {sub.parent_agent_id}
                    </div>
                  </div>
                  <div class="flex items-center gap-2">
                    <.badge variant={if(sub.status in ["error", :error], do: :error, else: :info)}>
                      {sub.status || "running"}
                    </.badge>
                    <button
                      type="button"
                      phx-click="toggle_subagent_row"
                      phx-value-id={sub.agent_id}
                      class="text-xs text-js-info hover:text-js-text transition-colors"
                    >
                      <%= if @expanded_subagent_id == sub.agent_id do %>
                        Collapse
                      <% else %>
                        Expand
                      <% end %>
                    </button>
                  </div>
                </div>

                <div
                  :if={@expanded_subagent_id == sub.agent_id}
                  class="mt-3 border-t border-js-border pt-2.5 space-y-2"
                >
                  <div class="inline-flex gap-1 rounded-md border border-js-border bg-js-bg px-1 py-1">
                    <button
                      :for={tab <- ["config", "messages", "middleware", "tools", "events"]}
                      type="button"
                      phx-click="select_subagent_detail_tab"
                      phx-value-tab={tab}
                      class={[
                        "rounded px-2 py-1 text-[11px] transition-colors",
                        if(@subagent_detail_tab == tab,
                          do: "bg-js-muted text-js-text",
                          else: "text-js-text-muted hover:text-js-text"
                        )
                      ]}
                    >
                      {String.capitalize(tab)}
                    </button>
                  </div>

                  <%= case @subagent_detail_tab do %>
                    <% "messages" -> %>
                      <pre class="text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"><%= inspect(sub[:messages] || [], pretty: true, limit: 120, printable_limit: 20_000) %></pre>
                    <% "middleware" -> %>
                      <pre class="text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"><%= inspect(sub[:middleware] || [], pretty: true, limit: 120, printable_limit: 20_000) %></pre>
                    <% "tools" -> %>
                      <pre class="text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"><%= inspect(sub[:tools] || [], pretty: true, limit: 120, printable_limit: 20_000) %></pre>
                    <% "events" -> %>
                      <%= if Map.get(@subagent_events, sub.agent_id, []) == [] do %>
                        <p class="text-xs text-js-text-subtle">
                          No trace events available for this sub-agent.
                        </p>
                      <% else %>
                        <div class="space-y-1">
                          <div
                            :for={event <- Map.get(@subagent_events, sub.agent_id, [])}
                            class="rounded border border-js-border bg-js-bg/70 px-2 py-1.5"
                          >
                            <div class="flex items-center justify-between gap-2">
                              <time
                                class="text-[11px] font-mono text-js-text-subtle"
                                data-js-ts={event[:timestamp_ms]}
                                data-js-relative="true"
                              >
                                {format_event_timestamp(event[:timestamp_ms])}
                              </time>
                              <.badge variant={:default}>{event[:type] || "event"}</.badge>
                            </div>
                            <div class="mt-1 text-[11px] font-mono text-js-text break-all">
                              {event[:event_name] || format_event_name(event)}
                            </div>
                          </div>
                        </div>
                      <% end %>
                    <% _ -> %>
                      <div class="space-y-1 text-[11px] text-js-text-muted">
                        <div>
                          <span class="text-js-text-subtle">name:</span> {sub[:name] || "n/a"}
                        </div>
                        <div>
                          <span class="text-js-text-subtle">model:</span> {sub[:model] || "n/a"}
                        </div>
                        <div>
                          <span class="text-js-text-subtle">duration:</span> {sub[:duration_ms] ||
                            0}ms
                        </div>
                        <div>
                          <span class="text-js-text-subtle">updated:</span>
                          <time data-js-ts={sub[:updated_at]} data-js-relative="true">
                            {format_event_timestamp(sub[:updated_at])}
                          </time>
                        </div>
                        <div>
                          <span class="text-js-text-subtle">result:</span> {sub[:result] ||
                            "n/a"}
                        </div>
                        <div :if={sub[:error]}>
                          <span class="text-js-text-subtle">error:</span> {inspect(sub[:error],
                            limit: 40
                          )}
                        </div>
                        <div :if={is_map(sub[:token_usage])}>
                          <span class="text-js-text-subtle">token_usage:</span> {inspect(
                            sub[:token_usage],
                            limit: 20
                          )}
                        </div>
                      </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </.card>
      <% :tasks -> %>
        <.card class="min-h-0 h-full overflow-hidden p-0">
          <div class="px-3 py-2 border-b border-js-border">
            <h3 class="text-sm font-medium text-js-text">Tasks</h3>
            <p class="text-xs text-js-text-muted mt-1">
              Task lifecycle inferred from scheduler/signal/directive events.
            </p>
          </div>
          <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
            <%= if @tasks == [] do %>
              <.empty_state
                title="No task records"
                description="No task IDs were observed for this instance."
              />
            <% else %>
              <div
                :for={task <- @tasks}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-xs text-js-text font-mono">{task.task_id}</span>
                  <.badge variant={task_badge_variant(task.task_status || task.status)}>
                    {task.task_status || task.status || "running"}
                  </.badge>
                </div>
                <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                  trace: {task.trace_id || "n/a"} / span: {task.span_id || "n/a"}
                </div>
              </div>
            <% end %>
          </div>
        </.card>
      <% :tool_insights -> %>
        <.card class="min-h-0 h-full overflow-hidden p-0">
          <div class="px-3 py-2 border-b border-js-border">
            <h3 class="text-sm font-medium text-js-text">Tool Insights</h3>
            <p class="text-xs text-js-text-muted mt-1">
              Call counts, failures, and p95 durations for observed tool runs.
            </p>
          </div>
          <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
            <%= if @tool_insights == [] do %>
              <.empty_state
                title="No tool runs"
                description="Tool usage appears here after runtime tool invocations."
              />
            <% else %>
              <div
                :for={run <- @tool_insights}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-xs text-js-text font-mono">
                    {run.tool_name || run.call_id}
                  </span>
                  <.badge variant={if(run.failure_count > 0, do: :warning, else: :success)}>
                    p95 {run.p95_duration_ms || 0}ms
                  </.badge>
                </div>
                <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                  calls: {run.call_count || 0} / failures: {run.failure_count || 0}
                </div>
                <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                  last: {run.last_status || "n/a"} / duration: {run.last_duration_ms || 0}ms
                </div>
                <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                  action: {run.action || "n/a"} / workflow: {run.workflow_id || "n/a"}
                </div>
                <.link
                  :if={
                    tool_trace_path(
                      @traces_path,
                      @active_instance_id,
                      run.call_id,
                      run.trace_id
                    )
                  }
                  navigate={
                    tool_trace_path(
                      @traces_path,
                      @active_instance_id,
                      run.call_id,
                      run.trace_id
                    )
                  }
                  class="mt-1 inline-flex text-[11px] text-js-info hover:text-js-text"
                >
                  Open Trace
                </.link>
              </div>
            <% end %>
          </div>
        </.card>
      <% :middleware -> %>
        <.card class="min-h-0 h-full overflow-hidden p-0">
          <div class="px-3 py-2 border-b border-js-border">
            <h3 class="text-sm font-medium text-js-text">Middleware</h3>
            <p class="text-xs text-js-text-muted mt-1">
              Latest middleware chain snapshots and invocation timing.
            </p>
          </div>
          <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
            <%= if @middleware_snapshots == [] do %>
              <.empty_state
                title="No middleware snapshots"
                description="Middleware data appears when runtime metadata includes chain details."
              />
            <% else %>
              <div
                :for={snapshot <- @middleware_snapshots}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-xs text-js-text font-mono">
                    {snapshot.entity_id || "middleware"}
                  </span>
                  <.badge variant={:default}>{snapshot.last_duration_ms || 0}ms</.badge>
                </div>
                <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                  {Enum.join(snapshot.middleware_chain || [], " -> ")}
                </div>
                <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                  invoked:
                  <time
                    data-js-ts={snapshot.last_invoked_at || snapshot.updated_at}
                    data-js-relative="true"
                  >
                    {format_event_timestamp(snapshot.last_invoked_at || snapshot.updated_at)}
                  </time>
                </div>
                <pre
                  :if={is_map(snapshot.config_snapshot) and map_size(snapshot.config_snapshot) > 0}
                  class="mt-1 text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"
                ><%= inspect(snapshot.config_snapshot, pretty: true, limit: 60) %></pre>
              </div>
            <% end %>
          </div>
        </.card>
      <% _ -> %>
        <.empty_state
          title="No configure panel"
          description="Choose Instance, Sub-Agents, Tasks, Tool Insights, or Middleware."
        />
    <% end %>
    """
  end

  defp tool_trace_path(base_path, instance_id, call_id, trace_id) do
    ObservabilityState.tool_trace_path(base_path, instance_id, call_id, trace_id)
  end
end
