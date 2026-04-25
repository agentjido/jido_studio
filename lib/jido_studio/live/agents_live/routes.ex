defmodule JidoStudio.Live.AgentsLive.Routes do
  @moduledoc false

  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Live.AgentsLive.Contracts
  alias JidoStudio.PathSegments

  def workbench_section_path(prefix, agent, instance_id, section, view_mode \\ nil) do
    section =
      section
      |> Contracts.parse_instance_section()
      |> Contracts.section_query_value()

    path = "#{prefix}/agents/#{agent.slug}/#{PathSegments.encode(instance_id)}/#{section}"

    with_view =
      case Contracts.parse_instance_view_mode_param(view_mode) do
        :advanced -> append_query(path, %{"view" => "advanced"})
        :basic -> append_query(path, %{"view" => "basic"})
        _ -> path
      end

    Scope.with_scope_query(with_view, Scope.current_node_param())
  end

  def workbench_path(prefix, agent, instance_id, panel, tab, section \\ nil, view_mode \\ nil) do
    panel = Contracts.parse_workbench_tab(panel)

    section =
      Contracts.parse_instance_section(section || Contracts.section_for_workbench_tab(panel))

    default_panel = Contracts.default_workbench_tab_for_section(section)
    base = workbench_section_path(prefix, agent, instance_id, section, view_mode)
    panel_value = Contracts.panel_query_value(panel)
    tab_value = Contracts.tab_query_value(tab)

    params_map =
      if(panel != default_panel, do: [{"panel", panel_value}], else: []) ++
        if(panel == :instance and is_binary(tab_value), do: [{"tab", tab_value}], else: [])

    query =
      params_map
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> URI.encode_query()

    if query == "" do
      base
    else
      separator = if String.contains?(base, "?"), do: "&", else: "?"
      "#{base}#{separator}#{query}"
    end
  end

  defp append_query(path, params) when is_binary(path) and is_map(params) do
    uri = URI.parse(path)

    existing =
      case uri.query do
        nil -> %{}
        query -> URI.decode_query(query)
      end

    query =
      existing
      |> Map.merge(params)
      |> URI.encode_query()

    uri
    |> Map.put(:query, query)
    |> URI.to_string()
  end
end
