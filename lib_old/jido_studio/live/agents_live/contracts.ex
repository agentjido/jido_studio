defmodule JidoStudio.Live.AgentsLive.Contracts do
  @moduledoc false

  @workbench_sections [
    %{
      id: :play,
      label: "Play",
      default_tab: :chat,
      tabs: [
        %{id: :chat, label: "Chat"},
        %{id: :interact, label: "Interact"},
        %{id: :messages, label: "Messages"}
      ]
    },
    %{
      id: :observe,
      label: "Observe",
      default_tab: :events,
      tabs: [
        %{id: :events, label: "Events"},
        %{id: :todos, label: "TODOs"},
        %{id: :thread_context, label: "Thread Context"},
        %{id: :thread_events, label: "Thread Events"}
      ]
    },
    %{
      id: :configure,
      label: "Configure",
      default_tab: :instance,
      tabs: [
        %{id: :instance, label: "Instance"},
        %{id: :sub_agents, label: "Sub-Agents"},
        %{id: :tasks, label: "Tasks"},
        %{id: :tool_insights, label: "Tool Insights"},
        %{id: :middleware, label: "Middleware"}
      ]
    }
  ]

  @workbench_tab_order [
    :chat,
    :interact,
    :messages,
    :events,
    :todos,
    :thread_context,
    :thread_events,
    :instance,
    :sub_agents,
    :tasks,
    :tool_insights,
    :middleware
  ]

  @workbench_tabs_by_section Enum.reduce(@workbench_sections, %{}, fn section, acc ->
                               Enum.reduce(section.tabs, acc, fn tab, inner ->
                                 Map.put(inner, tab.id, section.id)
                               end)
                             end)

  @instance_view_modes [:basic, :advanced]

  def workbench_sections, do: @workbench_sections

  def parse_instance_view_mode(mode)

  def parse_instance_view_mode(mode) when mode in @instance_view_modes, do: mode
  def parse_instance_view_mode("basic"), do: :basic
  def parse_instance_view_mode("advanced"), do: :advanced
  def parse_instance_view_mode(_), do: :basic

  def parse_instance_view_mode_param(mode)

  def parse_instance_view_mode_param(mode) when mode in @instance_view_modes, do: mode
  def parse_instance_view_mode_param("basic"), do: :basic
  def parse_instance_view_mode_param("advanced"), do: :advanced
  def parse_instance_view_mode_param(_), do: nil

  def view_mode_query_value(:basic), do: "basic"
  def view_mode_query_value(:advanced), do: "advanced"
  def view_mode_query_value(_), do: "basic"

  def parse_instance_section(section)

  def parse_instance_section(section) when section in [:play, :observe, :configure], do: section
  def parse_instance_section("play"), do: :play
  def parse_instance_section("observe"), do: :observe
  def parse_instance_section("configure"), do: :configure
  def parse_instance_section(_), do: :play

  def section_query_value(:play), do: "play"
  def section_query_value(:observe), do: "observe"
  def section_query_value(:configure), do: "configure"
  def section_query_value(_), do: "play"

  def default_workbench_tab_for_section(section) do
    section =
      section
      |> parse_instance_section()

    section =
      Enum.find(@workbench_sections, &(&1.id == section)) ||
        Enum.find(@workbench_sections, &(&1.id == :play))

    section.default_tab
  end

  def workbench_tabs_for_section(section) do
    section =
      section
      |> parse_instance_section()

    section =
      Enum.find(@workbench_sections, &(&1.id == section)) ||
        Enum.find(@workbench_sections, &(&1.id == :play))

    section.tabs
  end

  def section_description(:play), do: "Try interactions and send messages."
  def section_description(:observe), do: "Track events, TODOs, and runtime flow."
  def section_description(:configure), do: "Inspect instance details and tools."
  def section_description(_), do: "Inspect and operate this instance."

  def workbench_tab_in_section?(tab, section) do
    tab = parse_workbench_tab(tab)

    section
    |> workbench_tabs_for_section()
    |> Enum.any?(&(&1.id == tab))
  end

  def section_for_workbench_tab(tab) do
    tab = parse_workbench_tab(tab)
    Map.get(@workbench_tabs_by_section, tab, :play)
  end

  def parse_workbench_tab(panel, legacy_view \\ nil)

  def parse_workbench_tab(panel, _legacy_view)
      when panel in @workbench_tab_order,
      do: panel

  def parse_workbench_tab("chat", _legacy_view), do: :chat
  def parse_workbench_tab("interact", _legacy_view), do: :interact
  def parse_workbench_tab("messages", _legacy_view), do: :messages
  def parse_workbench_tab("events", _legacy_view), do: :events
  def parse_workbench_tab("todos", _legacy_view), do: :todos
  def parse_workbench_tab("thread_context", _legacy_view), do: :thread_context
  def parse_workbench_tab("context", _legacy_view), do: :thread_context
  def parse_workbench_tab("thread_events", _legacy_view), do: :thread_events
  def parse_workbench_tab("thread_events_legacy", _legacy_view), do: :thread_events
  def parse_workbench_tab("instance", _legacy_view), do: :instance
  def parse_workbench_tab("sub_agents", _legacy_view), do: :sub_agents
  def parse_workbench_tab("tasks", _legacy_view), do: :tasks
  def parse_workbench_tab("tool_insights", _legacy_view), do: :tool_insights
  def parse_workbench_tab("middleware", _legacy_view), do: :middleware
  def parse_workbench_tab(_, "inspect"), do: :instance
  def parse_workbench_tab(_, :inspect), do: :instance
  def parse_workbench_tab(_, _), do: :chat

  def panel_query_value(:chat), do: "chat"
  def panel_query_value(:interact), do: "interact"
  def panel_query_value(:messages), do: "messages"
  def panel_query_value(:events), do: "events"
  def panel_query_value(:todos), do: "todos"
  def panel_query_value(:thread_context), do: "thread_context"
  def panel_query_value(:thread_events), do: "thread_events"
  def panel_query_value(:instance), do: "instance"
  def panel_query_value(:sub_agents), do: "sub_agents"
  def panel_query_value(:tasks), do: "tasks"
  def panel_query_value(:tool_insights), do: "tool_insights"
  def panel_query_value(:middleware), do: "middleware"
  def panel_query_value(_), do: "chat"

  def tab_query_value(tab) when is_atom(tab), do: Atom.to_string(tab)
  def tab_query_value(tab) when is_binary(tab) and tab != "", do: tab
  def tab_query_value(_), do: nil
end
