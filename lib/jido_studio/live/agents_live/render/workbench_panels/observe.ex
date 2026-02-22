defmodule JidoStudio.Live.AgentsLive.Render.WorkbenchPanels.Observe do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components
  import JidoStudio.Live.AgentsLive.Panes
  import JidoStudio.Live.AgentsLive.Support

  def panel(assigns) do
    ~H"""
    <%= case @workbench_tab do %>
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
      <% _ -> %>
        <.empty_state
          title="No observability panel"
          description="Choose Events, TODOs, Thread Context, or Thread Events."
        />
    <% end %>
    """
  end
end
