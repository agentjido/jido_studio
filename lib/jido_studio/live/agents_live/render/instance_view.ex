defmodule JidoStudio.Live.AgentsLive.Render.InstanceView do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components
  import JidoStudio.Live.AgentsLive.Panes
  import JidoStudio.Live.AgentsLive.Support

  alias JidoStudio.Live.AgentsLive.Render.AdvancedInstanceView
  alias JidoStudio.Live.AgentsLive.Render.BasicInstanceView
  alias JidoStudio.Live.AgentsLive.ShowState

  def show_without_active_instance(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between border-b border-js-border pb-4 gap-3">
        <div class="flex items-center gap-2 text-sm text-js-text-muted">
          <.link navigate={scoped_path(@prefix <> "/agents")} class="hover:text-js-text">
            Agents
          </.link>
          <span>/</span>
          <span class="text-js-text">{humanize_agent_name(@agent.name)}</span>
        </div>
        <div class="flex items-center gap-2">
          <.button
            size={:sm}
            phx-click="open_start_modal"
            title="Start agent instance"
          >
            Start Instance
          </.button>
          <.link
            navigate={@traces_path}
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-sm text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            <Lucideicons.activity class="w-4 h-4" /> Traces
          </.link>
        </div>
      </div>

      <.card>
        <div class="space-y-4">
          <div>
            <h2 class="text-xl font-semibold text-js-text">{humanize_agent_name(@agent.name)}</h2>
            <p class="text-sm text-js-text-muted mt-1">
              Select a running instance to open chat, settings, and threads.
            </p>
          </div>

          <%= if @instance_cards == [] do %>
            <.no_running_instances />
          <% else %>
            <div class="space-y-3">
              <div
                :for={instance <- @instance_cards}
                class="flex items-stretch gap-3"
              >
                <.link
                  navigate={instance.path}
                  class="group flex-1 rounded-lg border border-js-border bg-js-bg/30 px-4 py-3 hover:bg-js-bg-elevated transition-colors"
                >
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0 space-y-1.5">
                      <div class="flex items-center gap-2.5 flex-wrap">
                        <span class="text-sm text-js-text font-medium">{instance.summary.title}</span>
                        <.badge
                          :for={badge <- Map.get(instance.summary, :badges, [])}
                          variant={Map.get(badge, :variant, :default)}
                        >
                          {badge.label}
                        </.badge>
                      </div>
                      <div
                        :if={Map.get(instance.summary, :subtitle)}
                        class="text-xs text-js-text-subtle truncate leading-5"
                      >
                        {instance.summary.subtitle}
                      </div>
                      <ul class="mt-0.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-js-text-muted leading-5">
                        <li
                          :for={{label, value} <- Map.get(instance.summary, :meta, [])}
                          class="flex items-center gap-1 whitespace-nowrap"
                        >
                          <span class="text-js-text-subtle">{label}:</span>
                          <span>{value}</span>
                        </li>
                      </ul>
                    </div>
                    <span class="inline-flex items-center gap-1.5 rounded-md border border-js-border px-2.5 py-1.5 text-xs font-medium text-js-text-muted group-hover:text-js-text group-hover:border-js-primary/60">
                      Open <Lucideicons.chevron_right class="w-3 h-3" />
                    </span>
                  </div>
                </.link>
                <.link
                  navigate={instance.traces_path}
                  class="inline-flex min-w-[96px] shrink-0 items-center justify-center gap-1.5 rounded-lg border border-js-border px-3 py-2.5 text-xs font-medium text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
                >
                  <Lucideicons.activity class="w-3.5 h-3.5" />
                  <span>Traces</span>
                </.link>
              </div>
            </div>
          <% end %>
        </div>
      </.card>

      <.start_instance_modal
        show={@start_modal_open?}
        start_form={@start_form}
        start_form_schema={@start_form_schema}
        start_form_error={@start_form_error}
        starting_instance?={@starting_instance?}
      />
    </div>
    """
  end

  def show_with_active_instance(assigns) do
    case parse_instance_view_mode(assigns.instance_view_mode) do
      :advanced -> AdvancedInstanceView.show(assigns)
      _ -> BasicInstanceView.show(assigns)
    end
  end

  def no_running_instances(assigns) do
    ~H"""
    <.empty_state
      title="No running instances"
      description="Start an instance of this agent, then select it here."
    />
    """
  end

  defp scoped_path(path), do: ShowState.scoped_path(path)
end
