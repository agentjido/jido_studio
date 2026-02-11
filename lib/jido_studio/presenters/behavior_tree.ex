defmodule JidoStudio.Presenters.BehaviorTree do
  @moduledoc false
  @behaviour JidoStudio.AgentPresenter

  alias JidoStudio.Presenters.Default

  @impl true
  def supports?(_agent_module, strategy_module),
    do: strategy_module == Jido.Agent.Strategy.BehaviorTree

  @impl true
  def static(agent_info) do
    view_model = Default.static(agent_info)

    tabs =
      if Enum.any?(view_model.tabs, &(&1.id == :behavior_tree)) do
        view_model.tabs
      else
        view_model.tabs ++ [%{id: :behavior_tree, label: "Behavior Tree"}]
      end

    sections =
      Map.put(
        view_model.sections_by_tab,
        :behavior_tree,
        [
          section("Mode", :badge, "BehaviorTree", variant: :info),
          section(
            "Notes",
            :text,
            "Strategy-specific tree state appears here when snapshot details are available."
          )
        ]
      )

    %{view_model | tabs: tabs, sections_by_tab: sections}
  end

  @impl true
  def runtime(agent_info, nil, _opts), do: static(agent_info)

  def runtime(agent_info, status, opts) do
    view_model = Default.runtime(agent_info, status, opts)
    details = status.snapshot.details || %{}

    bt_sections = [
      section("Tick Count", :text, to_string(details[:tick_count] || 0)),
      section("Tree Depth", :text, to_string(details[:tree_depth] || 0)),
      section("Last Error", :text, format_optional(details[:error], "none"))
    ]

    sections = Map.put(view_model.sections_by_tab, :behavior_tree, bt_sections)

    tabs =
      if Enum.any?(view_model.tabs, &(&1.id == :behavior_tree)),
        do: view_model.tabs,
        else: view_model.tabs ++ [%{id: :behavior_tree, label: "Behavior Tree"}]

    %{view_model | tabs: tabs, sections_by_tab: sections}
  end

  @impl true
  def instance_summary(agent_info, instance, nil, opts) do
    Default.instance_summary(agent_info, instance, nil, opts)
  end

  def instance_summary(agent_info, instance, status, opts) do
    base = Default.instance_summary(agent_info, instance, status, opts)
    details = status.snapshot.details || %{}
    bt_meta = [{"Ticks", to_string(details[:tick_count] || 0)}]
    Map.update(base, :meta, bt_meta, fn existing -> existing ++ bt_meta end)
  end

  @impl true
  def start_form_schema(agent_info), do: Default.start_form_schema(agent_info)

  defp section(title, kind, data, opts \\ []) do
    %{title: title, kind: kind, data: data, variant: Keyword.get(opts, :variant, :default)}
  end

  defp format_optional(nil, fallback), do: fallback
  defp format_optional(value, _fallback), do: to_string(value)
end
