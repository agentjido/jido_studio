defmodule JidoStudio.Live.AgentsLive.Render.AdvancedInstanceView do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components
  import JidoStudio.Live.AgentsLive.Panes
  import JidoStudio.Live.AgentsLive.Support

  alias JidoStudio.Live.AgentsLive.ShowState

  def show(assigns) do
    ~H"""
    <div
      class="p-3 lg:p-4 space-y-2 lg:flex-1 lg:min-h-0 lg:overflow-hidden lg:flex lg:flex-col"
      id="agent-workbench"
    >
      <div class="js-agent-topbar flex items-center justify-between gap-3 shrink-0">
        <div class="flex items-center gap-2 text-sm text-js-text-muted">
          <.link navigate={scoped_path(@prefix <> "/agents")} class="hover:text-js-text">
            Agents
          </.link>
          <span>/</span>
          <.link navigate={@module_path} class="hover:text-js-text">
            {humanize_agent_name(@agent.name)}
          </.link>
          <span :if={@active_instance_id}>
            / <span class="text-js-text-subtle">{short_instance_id(@active_instance_id)}</span>
          </span>
          <.badge :if={@workspace_source == :persisted} variant={:warning}>
            Persisted Workspace
          </.badge>
          <.badge :if={not @instance_online?} variant={:default}>
            Instance Offline
          </.badge>
        </div>
        <div class="flex items-center gap-2">
          <div class="inline-flex items-center rounded-md border border-js-border bg-js-bg-elevated/20 p-0.5">
            <.link
              patch={@basic_view_path}
              class="rounded px-2 py-1 text-xs text-js-text-muted hover:text-js-text"
            >
              Basic View
            </.link>
            <.link
              patch={@advanced_view_path}
              class="rounded bg-js-bg-elevated px-2 py-1 text-xs text-js-text"
            >
              Advanced View
            </.link>
          </div>

          <button
            :if={@thread_persistence?}
            type="button"
            phx-click="clear_workspace"
            data-confirm="Clear persisted workspace for this instance? Saved threads and context snapshots will be removed."
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-sm text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            Clear Workspace
          </button>
          <.link
            navigate={@traces_path}
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-sm text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            <Lucideicons.activity class="w-4 h-4" /> Traces
          </.link>
        </div>
      </div>

      <div class={[@workbench_grid_class, "lg:flex-1 lg:min-h-0"]}>
        <.chat_threads_rail
          class={"min-h-[12rem] lg:min-h-0 lg:h-full #{@threads_rail_class || ""}"}
          threads={@chat_state.threads}
          active_thread_id={@chat_state.active_thread_id}
          messages_by_thread={@chat_state.messages_by_thread}
          chat_pending?={@chat_pending?}
        />

        <div class="min-h-[22rem] lg:min-h-0 lg:h-full flex flex-col gap-1.5">
          <div class="px-0.5">
            <div class="js-instance-menu">
              <div class="js-instance-menu-header">
                <div class="js-instance-menu-title-block">
                  <p class="js-instance-menu-kicker">Instance Menu</p>
                  <p class="js-instance-menu-description">
                    {section_description(@instance_section)}
                  </p>
                </div>
                <span class="js-instance-menu-current">
                  {String.capitalize(section_query_value(@instance_section))}
                </span>
              </div>

              <div class="js-instance-menu-sections">
                <.link
                  :for={section <- workbench_sections()}
                  patch={
                    workbench_section_path(
                      @prefix,
                      @agent,
                      @active_instance_id,
                      section.id,
                      :advanced
                    )
                  }
                  class={workbench_section_button_class(@instance_section == section.id)}
                >
                  <span class="js-instance-menu-item-icon">
                    <%= case section.id do %>
                      <% :play -> %>
                        <Lucideicons.message_circle class="w-3.5 h-3.5" />
                      <% :observe -> %>
                        <Lucideicons.activity class="w-3.5 h-3.5" />
                      <% :configure -> %>
                        <Lucideicons.wrench class="w-3.5 h-3.5" />
                    <% end %>
                  </span>
                  <span class="js-instance-menu-item-label">{section.label}</span>
                </.link>
              </div>

              <div class="js-instance-menu-tabs">
                <span
                  :for={tab <- @section_tabs}
                  :if={tab.id == :chat and @chat_tab_disabled?}
                  class={[
                    workbench_tab_button_class(false),
                    "is-disabled"
                  ]}
                  title="Chat unavailable for this instance"
                >
                  {tab.label}
                </span>

                <.link
                  :for={tab <- @section_tabs}
                  :if={not (tab.id == :chat and @chat_tab_disabled?)}
                  patch={
                    workbench_path(
                      @prefix,
                      @agent,
                      @active_instance_id,
                      tab.id,
                      @detail_tab,
                      @instance_section,
                      :advanced
                    )
                  }
                  class={workbench_tab_button_class(@workbench_tab == tab.id)}
                >
                  {tab.label}
                </.link>
              </div>
            </div>
          </div>

          {workbench_panel(assigns)}
        </div>

        <.summary_pane
          class="min-h-[16rem] lg:min-h-0 lg:h-full"
          agent={@agent}
          module_path={@module_path}
          instance_links={@instance_links}
          active_instance_id={@active_instance_id}
          instance_debug_enabled?={@instance_debug_enabled?}
          instance_debug_level={@instance_debug_level}
          instance_debug_error={@instance_debug_error}
          traces_path={@traces_path}
          summary_meta={@summary_meta}
          instance_observability_events={@instance_observability_events}
          triage_links={@triage_links}
        />
      </div>
    </div>
    """
  end

  defdelegate workbench_panel(assigns), to: JidoStudio.Live.AgentsLive.Render.WorkbenchPanels

  defp scoped_path(path), do: ShowState.scoped_path(path)
end
