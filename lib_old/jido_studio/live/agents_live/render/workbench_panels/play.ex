defmodule JidoStudio.Live.AgentsLive.Render.WorkbenchPanels.Play do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components
  import JidoStudio.Live.AgentsLive.Support

  alias JidoStudio.Agents.RunnerForm

  def panel(assigns) do
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
end
