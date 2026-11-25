defmodule JidoStudio.Live.AgentsLive.Render.WorkbenchPanels do
  @moduledoc false
  use Phoenix.Component

  alias JidoStudio.Live.AgentsLive.Render.WorkbenchPanels.Configure
  alias JidoStudio.Live.AgentsLive.Render.WorkbenchPanels.Observe
  alias JidoStudio.Live.AgentsLive.Render.WorkbenchPanels.Play

  def workbench_panel(%{workbench_tab: tab} = assigns)
      when tab in [:interact, :messages, :chat] do
    Play.panel(assigns)
  end

  def workbench_panel(%{workbench_tab: tab} = assigns)
      when tab in [:events, :todos, :thread_context, :thread_events] do
    Observe.panel(assigns)
  end

  def workbench_panel(%{workbench_tab: tab} = assigns)
      when tab in [:instance, :sub_agents, :tasks, :tool_insights, :middleware] do
    Configure.panel(assigns)
  end

  def workbench_panel(assigns), do: Play.panel(assigns)
end
