defmodule JidoStudio.Live.AgentsLive.Routes do
  @moduledoc false

  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Live.AgentsLive.Contracts

  def workbench_section_path(prefix, agent, instance_id, section) do
    section =
      section
      |> Contracts.parse_instance_section()
      |> Contracts.section_query_value()

    path = "#{prefix}/agents/#{agent.slug}/#{URI.encode_www_form(instance_id)}/#{section}"
    Scope.with_scope_query(path, Scope.current_node_param())
  end

  def workbench_path(prefix, agent, instance_id, panel, tab, section \\ nil) do
    panel = Contracts.parse_workbench_tab(panel)

    section =
      Contracts.parse_instance_section(section || Contracts.section_for_workbench_tab(panel))

    default_panel = Contracts.default_workbench_tab_for_section(section)
    base = workbench_section_path(prefix, agent, instance_id, section)
    panel_value = Contracts.panel_query_value(panel)
    tab_value = Contracts.tab_query_value(tab)

    params =
      if(panel != default_panel, do: [{"panel", panel_value}], else: []) ++
        if(panel == :instance and is_binary(tab_value), do: [{"tab", tab_value}], else: [])

    query =
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> URI.encode_query()

    if query == "" do
      base
    else
      separator = if String.contains?(base, "?"), do: "&", else: "?"
      "#{base}#{separator}#{query}"
    end
  end
end
