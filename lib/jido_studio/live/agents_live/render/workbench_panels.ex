defmodule JidoStudio.Live.AgentsLive.Render.WorkbenchPanels do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components
  import JidoStudio.Live.AgentsLive.Panes
  import JidoStudio.Live.AgentsLive.Support

  alias JidoStudio.Agents.RunnerForm
  alias JidoStudio.Live.AgentsLive.ObservabilityState

  def workbench_panel(assigns) do
    ~H"""
    <%= case @workbench_tab do %>
      <% :interact -> %>
        <.card class="min-h-0 h-full overflow-hidden p-0">
          <div class="px-3 py-2 border-b border-js-border">
            <h3 class="text-sm font-medium text-js-text">Interact</h3>
            <p class="text-xs text-js-text-muted mt-1">
              Signal and action introspection with guarded runtime dispatch.
            </p>
          </div>
          <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-3 flex-1 min-h-0">
            <%= if @interaction_model.warnings != [] do %>
              <div class="rounded-md border border-js-warning/40 bg-js-warning/10 p-2 space-y-1">
                <p class="text-xs text-js-warning font-medium">Introspection warnings</p>
                <p
                  :for={warning <- @interaction_model.warnings}
                  class="text-[11px] text-js-warning/90"
                >
                  {warning}
                </p>
              </div>
            <% end %>

            <div class="grid grid-cols-1 xl:grid-cols-2 gap-3">
              <div class="space-y-2">
                <div class="flex items-center justify-between gap-2">
                  <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">
                    Consumed Signals
                  </h4>
                  <button
                    type="button"
                    phx-click="toggle_advanced_signals"
                    class="text-xs text-js-info hover:text-js-text"
                  >
                    {if(@show_advanced_signals?, do: "Hide advanced", else: "Show advanced")}
                  </button>
                </div>
                <%= if @interaction_signals == [] do %>
                  <.empty_state
                    title="No signal routes"
                    description="No runtime or static signal routes were discovered."
                  />
                <% else %>
                  <div class="space-y-1.5">
                    <div
                      :for={signal <- @interaction_signals}
                      class={[
                        "rounded-md border px-2 py-2 bg-js-bg-elevated/30",
                        if(@selected_runner_target == {:signal, signal.key},
                          do: "border-js-info/60",
                          else: "border-js-border"
                        )
                      ]}
                    >
                      <div class="flex items-center justify-between gap-2">
                        <div class="text-xs font-mono text-js-text break-all">
                          {signal.signal_type}
                        </div>
                        <div class="flex items-center gap-1">
                          <.badge variant={if(signal.route_available?, do: :success, else: :warning)}>
                            {if(signal.route_available?, do: "runtime", else: "static")}
                          </.badge>
                          <.badge variant={if(signal.advanced?, do: :default, else: :info)}>
                            {if(signal.advanced?, do: "advanced", else: "entry")}
                          </.badge>
                        </div>
                      </div>
                      <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                        src: {signal.source} / priority: {signal.priority} / target: {signal.target_summary}
                      </div>
                      <div
                        :if={is_integer(signal.last_seen_at)}
                        class="mt-1 text-[11px] text-js-text-subtle"
                      >
                        last seen:
                        <time data-js-ts={signal.last_seen_at} data-js-relative="true">
                          {format_event_timestamp(signal.last_seen_at)}
                        </time>
                      </div>
                      <button
                        type="button"
                        phx-click="select_signal"
                        phx-value-key={signal.key}
                        class="mt-2 inline-flex rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text"
                      >
                        Use Signal
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>

              <div class="space-y-2">
                <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">
                  Action Schemas
                </h4>
                <%= if @interaction_actions == [] do %>
                  <.empty_state
                    title="No action schemas"
                    description="No route or plugin actions were discovered."
                  />
                <% else %>
                  <div class="space-y-1.5">
                    <div
                      :for={action <- @interaction_actions}
                      class={[
                        "rounded-md border px-2 py-2 bg-js-bg-elevated/30",
                        if(@selected_runner_target == {:action, action.key},
                          do: "border-js-info/60",
                          else: "border-js-border"
                        )
                      ]}
                    >
                      <div class="flex items-center justify-between gap-2">
                        <div class="text-xs text-js-text font-mono break-all">
                          {action.label}
                        </div>
                        <.badge variant={if(action.convertible_schema?, do: :success, else: :warning)}>
                          {if(action.convertible_schema?, do: "schema ok", else: "raw fallback")}
                        </.badge>
                      </div>
                      <p
                        :if={is_binary(action.doc)}
                        class="mt-1 text-[11px] text-js-text-subtle"
                      >
                        {action.doc}
                      </p>
                      <div class="mt-1 text-[11px] text-js-text-subtle">
                        required: {if(action.required_fields == [],
                          do: "none",
                          else: Enum.join(action.required_fields, ", ")
                        )}
                      </div>
                      <div
                        :if={action.schema_error}
                        class="mt-1 text-[11px] text-js-warning"
                      >
                        {action.schema_error}
                      </div>
                      <button
                        type="button"
                        phx-click="select_action"
                        phx-value-key={action.key}
                        class="mt-2 inline-flex rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text"
                      >
                        Use Action
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <div class="rounded-md border border-js-border bg-js-bg-elevated/20 p-3 space-y-2">
              <div class="flex items-center justify-between gap-2">
                <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">Runner</h4>
                <.badge variant={
                  if(@interaction_model.dispatch_available?, do: :success, else: :warning)
                }>
                  {if(@interaction_model.dispatch_available?,
                    do: "instance online",
                    else: "instance offline"
                  )}
                </.badge>
              </div>
              <div class="text-xs text-js-text-muted">
                Selected:
                <span class="font-mono text-js-text">
                  <%= case @selected_runner_target do %>
                    <% {:signal, key} -> %>
                      signal {key}
                    <% {:action, key} -> %>
                      action {key}
                    <% _ -> %>
                      none
                  <% end %>
                </span>
              </div>

              <form phx-change="update_runner_payload" class="space-y-2">
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  <label class="text-xs text-js-text-muted">
                    Dispatch Mode
                    <select
                      name="runner[dispatch_mode]"
                      class="mt-1 w-full rounded-md border border-js-border bg-js-bg px-2 py-1.5 text-xs text-js-text"
                    >
                      <option value="sync" selected={@runner_form.dispatch_mode == "sync"}>
                        sync
                      </option>
                      <option value="async" selected={@runner_form.dispatch_mode == "async"}>
                        async
                      </option>
                    </select>
                  </label>
                  <label class="text-xs text-js-text-muted">
                    Schema View
                    <select
                      name="runner[schema_mode]"
                      class="mt-1 w-full rounded-md border border-js-border bg-js-bg px-2 py-1.5 text-xs text-js-text"
                    >
                      <option value="fields" selected={@runner_form.schema_mode == "fields"}>
                        fields
                      </option>
                      <option value="raw" selected={@runner_form.schema_mode == "raw"}>
                        raw
                      </option>
                    </select>
                  </label>
                </div>
                <label class="text-xs text-js-text-muted block">
                  Payload JSON <textarea
                    name="runner[payload_json]"
                    rows="8"
                    class="mt-1 w-full rounded-md border border-js-border bg-js-bg p-2 text-xs text-js-text font-mono"
                  ><%= @runner_form.payload_json %></textarea>
                </label>
              </form>

              <div class="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  phx-click="arm_runner_execute"
                  class={
                    if(@runner_form.guard_armed?,
                      do:
                        "inline-flex rounded-md border border-js-success/40 bg-js-success/10 px-2.5 py-1 text-xs text-js-success",
                      else:
                        "inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text"
                    )
                  }
                >
                  {if(@runner_form.guard_armed?, do: "Armed", else: "Arm Execute")}
                </button>
                <button
                  type="button"
                  phx-click="run_selected_interaction"
                  disabled={!RunnerForm.can_execute?(@runner_form)}
                  class="inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Run
                </button>
                <button
                  type="button"
                  phx-click="clear_runner_history"
                  class="inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text"
                >
                  Clear History
                </button>
              </div>

              <pre
                :if={@runner_result}
                class="text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"
              ><%= inspect(@runner_result, pretty: true, limit: 120, printable_limit: 20_000) %></pre>

              <%= if @runner_history != [] do %>
                <div class="space-y-1.5">
                  <p class="text-[11px] uppercase tracking-wider text-js-text-subtle">
                    Recent Runs
                  </p>
                  <div
                    :for={entry <- @runner_history}
                    class="rounded border border-js-border bg-js-bg/60 px-2 py-1.5 text-[11px] text-js-text-subtle font-mono"
                  >
                    <span>{entry[:mode]} {entry[:signal_type]}</span>
                    <span class="mx-1">/</span>
                    <time data-js-ts={entry[:timestamp_ms]} data-js-relative="true">
                      {format_event_timestamp(entry[:timestamp_ms])}
                    </time>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </.card>
      <% :messages -> %>
        <.card class="min-h-0 h-full overflow-hidden p-0">
          <div class="px-3 py-2 border-b border-js-border">
            <h3 class="text-sm font-medium text-js-text">Messages</h3>
            <p class="text-xs text-js-text-muted mt-1">
              Normalized runtime thread messages including tool calls and thinking blocks.
            </p>
          </div>
          <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
            <%= if @runtime_messages == [] do %>
              <.empty_state
                title="No runtime messages"
                description="Send a message or run strategy steps to capture a thread snapshot."
              />
            <% else %>
              <div
                :for={message <- @runtime_messages}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-xs font-medium text-js-text">
                    {message[:role] || :unknown}
                  </span>
                  <.badge variant={
                    if(message[:status] in ["error", :error], do: :error, else: :default)
                  }>
                    {message[:status] || "ok"}
                  </.badge>
                </div>
                <div class="mt-1 text-xs text-js-text-muted whitespace-pre-wrap break-words">
                  <%= case message[:content] do %>
                    <% content when is_binary(content) -> %>
                      {content}
                    <% content when is_list(content) -> %>
                      <div :for={part <- content} class="mb-1">
                        <span
                          :if={part[:type] == :thinking}
                          class="inline-flex rounded bg-js-info/10 px-1.5 py-0.5 text-[11px] text-js-info mr-1"
                        >
                          thinking
                        </span>
                        <span>{part[:content] || inspect(part[:data], limit: 40)}</span>
                      </div>
                    <% other -> %>
                      {inspect(other, pretty: true, limit: 40)}
                  <% end %>
                </div>
                <div :if={message[:tool_calls] != []} class="mt-2 space-y-1">
                  <div class="text-[11px] uppercase tracking-wider text-js-text-subtle">
                    Tool Calls
                  </div>
                  <div
                    :for={call <- message[:tool_calls]}
                    class="text-xs text-js-text-subtle font-mono"
                  >
                    {call[:name]} ({call[:call_id]})
                  </div>
                </div>
                <div :if={message[:tool_results] != []} class="mt-2 space-y-1">
                  <div class="text-[11px] uppercase tracking-wider text-js-text-subtle">
                    Tool Results
                  </div>
                  <div
                    :for={result <- message[:tool_results]}
                    class="text-xs text-js-text-subtle font-mono"
                  >
                    {result[:name]} [{result[:status] || "ok"}]
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </.card>
      <% :events -> %>
        <.card class="min-h-0 h-full overflow-hidden p-0">
          <div class="px-3 py-2 border-b border-js-border flex items-center justify-between gap-2">
            <div>
              <h3 class="text-sm font-medium text-js-text">Events</h3>
              <p class="text-xs text-js-text-muted mt-1">
                Merged event stream with expandable raw telemetry payloads.
              </p>
            </div>
            <.link
              :if={@traces_path}
              navigate={@traces_path}
              class="text-xs text-js-info hover:text-js-text transition-colors"
            >
              Open Traces
            </.link>
          </div>
          <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
            <form phx-change="update_instance_event_query" class="mb-2">
              <input
                type="text"
                name="query"
                value={@instance_event_query}
                placeholder="Search merged events"
                class="w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text focus:outline-none focus:ring-2 focus:ring-js-ring"
              />
            </form>
            <%= if @instance_events == [] do %>
              <.empty_state
                title="No merged events"
                description="Run an interaction to populate event telemetry."
              />
            <% else %>
              <div
                :for={event <- @instance_events}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
              >
                <div class="flex items-center justify-between gap-2">
                  <time
                    class="text-[11px] font-mono text-js-text-subtle"
                    data-js-ts={event[:timestamp_ms]}
                    data-js-relative="true"
                  >
                    {format_event_timestamp(event[:timestamp_ms])}
                  </time>
                  <div class="flex items-center gap-1">
                    <.badge variant={if(event[:source] == :agent_debug, do: :warning, else: :info)}>
                      {event[:source] || :telemetry}
                    </.badge>
                    <.badge :if={(event[:chunk_count] || 1) > 1} variant={:default}>
                      {event[:chunk_count]} chunks
                    </.badge>
                  </div>
                </div>
                <div class="mt-1 text-xs text-js-text font-mono break-all">
                  {format_event_name(event)}
                </div>
                <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                  call: {event[:call_id] || "n/a"} / task: {event[:task_id] || "n/a"}
                </div>
                <button
                  type="button"
                  phx-click="toggle_event_row"
                  phx-value-id={event[:id]}
                  class="mt-2 text-xs text-js-info hover:text-js-text transition-colors"
                >
                  <%= if MapSet.member?(@expanded_event_ids, event[:id]) do %>
                    Hide Raw
                  <% else %>
                    Show Raw
                  <% end %>
                </button>
                <pre
                  :if={MapSet.member?(@expanded_event_ids, event[:id])}
                  class="mt-2 text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"
                ><%= inspect(event[:raw] || event, pretty: true, limit: 120, printable_limit: 20_000) %></pre>
              </div>
            <% end %>
          </div>
        </.card>
      <% :todos -> %>
        <.card class="min-h-0 h-full overflow-hidden p-0">
          <div class="px-3 py-2 border-b border-js-border">
            <h3 class="text-sm font-medium text-js-text">TODOs</h3>
            <p class="text-xs text-js-text-muted mt-1">
              Strategy TODO list with fallback to tracked tasks.
            </p>
          </div>
          <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
            <%= if @runtime_todos == [] do %>
              <.empty_state
                title="No TODOs"
                description="No strategy TODO state was found for this instance."
              />
            <% else %>
              <div
                :for={todo <- @runtime_todos}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-xs text-js-text">{todo[:content]}</span>
                  <.badge variant={todo_badge_variant(todo[:status])}>
                    {todo[:status] || :pending}
                  </.badge>
                </div>
                <div
                  :if={todo[:active_form]}
                  class="mt-1 text-[11px] text-js-text-subtle font-mono"
                >
                  active_form: {todo[:active_form]}
                </div>
              </div>
            <% end %>
          </div>
        </.card>
      <% :thread_context -> %>
        <.card class="min-h-0 h-full overflow-hidden p-0">
          <div class="px-3 py-2 border-b border-js-border">
            <h3 class="text-sm font-medium text-js-text">Thread Context</h3>
            <p class="text-xs text-js-text-muted mt-1">
              Context snapshot for the active thread and strategy state.
            </p>
          </div>
          <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-3.5 flex-1 min-h-0">
            <%= if @thread_context_sections == [] do %>
              <.empty_state
                title="No context available"
                description="Context appears after the strategy reports runtime state."
              />
            <% else %>
              <.detail_section
                :for={section <- @thread_context_sections}
                section={section}
              />
            <% end %>
          </div>
        </.card>
      <% :thread_events -> %>
        <.card class="min-h-0 h-full overflow-hidden p-0">
          <div class="px-3 py-2 border-b border-js-border flex items-center justify-between gap-2">
            <div>
              <h3 class="text-sm font-medium text-js-text">Thread Events</h3>
              <p class="text-xs text-js-text-muted mt-1">
                Event stream scoped to this thread when metadata includes thread IDs.
              </p>
            </div>
            <.link
              :if={@traces_path}
              navigate={@traces_path}
              class="text-xs text-js-info hover:text-js-text transition-colors"
            >
              Open Traces
            </.link>
          </div>
          <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
            <form phx-change="update_live_event_query" class="mb-2">
              <input
                type="text"
                name="query"
                value={@live_event_query}
                placeholder="Search events"
                class="w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text focus:outline-none focus:ring-2 focus:ring-js-ring"
              />
            </form>
            <p :if={@thread_scope_id} class="text-xs text-js-text-subtle">
              Thread ID: <span class="font-mono text-js-text">{@thread_scope_id}</span>
            </p>
            <%= if @thread_events == [] do %>
              <.empty_state
                title="No thread events"
                description="Send a message and tool call activity will appear here."
              />
            <% else %>
              <div
                :for={event <- @thread_events}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
              >
                <div class="flex items-center justify-between gap-2">
                  <time
                    class="text-[11px] font-mono text-js-text-subtle"
                    data-js-ts={event[:timestamp_ms]}
                    data-js-relative="true"
                  >
                    {format_event_timestamp(event[:timestamp_ms])}
                  </time>
                  <.badge variant={if(event[:source] == :agent_debug, do: :warning, else: :info)}>
                    {event[:source] || :telemetry}
                  </.badge>
                </div>
                <div class="mt-1 text-xs text-js-text font-mono truncate">
                  {format_event_name(event)}
                </div>
              </div>
            <% end %>
          </div>
        </.card>
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
        <div class="min-h-0 h-full flex flex-col gap-2">
          <div
            :if={not @chat_enabled? and @interaction_model.runner_supported?}
            class="rounded-md border border-js-info/40 bg-js-info/10 px-3 py-2 text-xs text-js-info flex items-center justify-between gap-2"
          >
            <span>
              {chat_unavailable_message(@chat_unavailable_reason)}
            </span>
            <button
              type="button"
              phx-click="select_workbench_tab"
              phx-value-panel="interact"
              class="inline-flex rounded-md border border-js-info/50 px-2 py-1 text-[11px] hover:text-js-text"
            >
              Open Interact
            </button>
          </div>
          <.chat_conversation_panel
            class="min-h-0 h-full"
            thread_name={@active_thread_name}
            draft_message={@draft_message}
            active_messages={@active_messages}
            chat_pending?={@chat_pending?}
            chat_enabled?={@chat_enabled?}
            placeholder={@chat_config.placeholder}
            empty_title={@chat_config.empty_title}
            empty_description={@chat_config.empty_description}
            model_label={@chat_config.model_label || @ui_model}
            provider_options={@chat_provider_options}
            provider_value={@chat_provider}
            model_options={@chat_model_options}
            model_value={@chat_model}
            traces_path={@traces_path}
          />
        </div>
    <% end %>
    """
  end

  defp tool_trace_path(base_path, instance_id, call_id, trace_id) do
    ObservabilityState.tool_trace_path(base_path, instance_id, call_id, trace_id)
  end
end
