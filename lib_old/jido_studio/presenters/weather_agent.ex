defmodule JidoStudio.Presenters.WeatherAgent do
  @moduledoc false
  @behaviour JidoStudio.AgentPresenter

  alias JidoStudio.Presenters.Default
  alias JidoStudio.Presenters.ReAct

  @weather_module Jido.AI.Examples.WeatherAgent

  @impl true
  def supports?(agent_module, _strategy_module), do: agent_module == @weather_module

  @impl true
  def static(agent_info) do
    view_model = ReAct.static(agent_info)

    tabs =
      if Enum.any?(view_model.tabs, &(&1.id == :weather)) do
        view_model.tabs
      else
        view_model.tabs ++ [%{id: :weather, label: "Weather"}]
      end

    sections =
      Map.put(
        view_model.sections_by_tab,
        :weather,
        [
          section(
            "Location Input Rule",
            :text,
            "Weather tools require lat,lng coordinates. Geocode first when user gives city or address."
          ),
          section(
            "Sample Prompts",
            :badges,
            [
              "What's the weather in Seattle this weekend?",
              "Should I bring an umbrella in Chicago today?",
              "I'm hiking in Denver tomorrow. What should I wear?"
            ]
          )
        ]
      )

    %{view_model | tabs: tabs, sections_by_tab: sections}
  end

  @impl true
  def runtime(agent_info, runtime_status, opts) do
    view_model = ReAct.runtime(agent_info, runtime_status, opts)
    weather_sections = Map.get(static(agent_info).sections_by_tab, :weather, [])

    sections = Map.put(view_model.sections_by_tab, :weather, weather_sections)

    tabs =
      if Enum.any?(view_model.tabs, &(&1.id == :weather)),
        do: view_model.tabs,
        else: view_model.tabs ++ [%{id: :weather, label: "Weather"}]

    %{view_model | tabs: tabs, sections_by_tab: sections}
  end

  @impl true
  def instance_summary(agent_info, instance, runtime_status, opts) do
    ReAct.instance_summary(agent_info, instance, runtime_status, opts)
  end

  @impl true
  def chat_config(agent_info, runtime_status, opts) do
    base = Default.chat_config(agent_info, runtime_status, opts)

    %{
      base
      | placeholder: "Ask about weather, forecasts, and activity plans...",
        empty_title: "Weather chat ready",
        empty_description:
          "You can ask follow-up questions like \"what about tomorrow?\" and keep context on this instance."
    }
  end

  @impl true
  def start_form_schema(_agent_info) do
    [
      %{
        name: "instance_id",
        label: "Instance ID (optional)",
        type: :text,
        default: "",
        placeholder: "weather-agent-dev"
      },
      %{
        name: "debug",
        label: "Enable debug event buffer",
        type: :checkbox,
        default: "false"
      },
      %{
        name: "initial_state_json",
        label: "Initial State (JSON map, optional)",
        type: :textarea_json,
        default: "",
        rows: 6,
        placeholder: "{\n  \"model\": \"anthropic:claude-haiku-4-5\"\n}"
      }
    ]
  end

  defp section(title, kind, data, opts \\ []) do
    %{title: title, kind: kind, data: data, variant: Keyword.get(opts, :variant, :default)}
  end
end
