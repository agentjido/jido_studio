defmodule JidoStudio.DefinitionGraph do
  @moduledoc """
  Builds read-only canvas nodes and connections from a definition snapshot.

  Node and connection IDs are scoped to a graph. Columns describe the preview
  layout. The agent definition remains the source for topology and flow behavior.
  """

  @doc "Builds the selected route, nested flow, or topology graph."
  @spec build(map(), map(), String.t(), String.t() | nil) :: map()
  def build(definition, route, "topology", _flow), do: topology(definition, route)

  def build(definition, route, _mode, nested) do
    target = route["handler"]["target"]
    flows = definition["flows"]
    key = "route:" <> route["signal"]
    flow = flows[target]

    cond do
      is_nil(flow) ->
        action_graph(key, route)

      is_binary(nested) and nested != target and reaches?(flows, target, nested, MapSet.new()) ->
        Map.put(flow_graph(key <> ":" <> nested, flows[nested], nil, flows), :nested, nested)

      true ->
        flow_graph(key, flow, route, flows)
    end
  end

  defp reaches?(flows, current, nested, visited) do
    if flows[current] && !MapSet.member?(visited, current) do
      visited = MapSet.put(visited, current)

      Enum.any?(flows[current]["components"], fn component ->
        target = component["handler"]["target"]
        flows[target] && (target == nested || reaches?(flows, target, nested, visited))
      end)
    else
      false
    end
  end

  defp topology(definition, route) do
    %{"members" => members, "connections" => connections} = definition["topology"]
    root = %{"kind" => "agent", "name" => "root"}
    member_endpoints = Enum.map(members, &%{"kind" => "agent", "name" => &1["name"]})

    endpoints =
      [root | Enum.flat_map(connections, &[&1["from"], &1["to"]])]
      |> Enum.concat(member_endpoints)
      |> Enum.uniq()

    members = Map.new(members, &{&1["name"], &1})
    columns = Enum.map(endpoints, &[topology_node(&1, definition["name"], members)])

    edges =
      Enum.map(connections, fn connection ->
        from = endpoint_id(connection["from"])
        to = endpoint_id(connection["to"])

        edge(from, to, connection["signal"],
          detail: connection["delivery"],
          active: connection["signal"] == route["signal"]
        )
      end)

    graph("topology:" <> route["signal"], "Signal topology", columns, edges, :topology)
  end

  defp topology_node(%{"kind" => "agent", "name" => "root"} = endpoint, root, _members),
    do: node(endpoint_id(endpoint), "Root agent", label(root))

  defp topology_node(%{"kind" => "agent", "name" => name} = endpoint, _root, members) do
    member = members[name]
    caption = if member, do: "×#{member["count"]} declared"
    fields = Enum.map((member && member["routes"]) || [], &field("Receives", &1["signal"]))

    node(endpoint_id(endpoint), "Member agent", label(name),
      caption: caption,
      detail: member && member["definition"],
      fields: fields
    )
  end

  defp topology_node(%{"kind" => kind, "name" => name} = endpoint, _root, _members),
    do: node(endpoint_id(endpoint), label(kind), label(name), detail: name)

  defp endpoint_id(%{"kind" => kind, "name" => name}), do: kind <> ":" <> name

  defp flow_graph(key, flow, route, flows) do
    components = flow["components"]
    input = input_node(route)
    output = node("output", "Output", "Flow output", fields: flow["output"])
    outcomes = if route, do: outcome_nodes(route), else: []
    nodes_by_component = Map.new(components, &{&1["name"], component_nodes(&1, flows)})

    columns =
      components
      |> Enum.group_by(& &1["level"])
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_level, group} ->
        Enum.flat_map(group, &Map.fetch!(nodes_by_component, &1["name"]))
      end)

    dependencies =
      Enum.flat_map(components, fn component ->
        sources =
          case component["needs"] do
            [] ->
              [input.id]

            needs ->
              for name <- needs, source <- Map.get(nodes_by_component, name, []), do: source.id
          end

        for source <- sources,
            destination <- Map.fetch!(nodes_by_component, component["name"]),
            do:
              edge(
                source,
                destination.id,
                if(source == input.id, do: "Flow entry", else: "Dependency")
              )
      end)

    output_edges =
      for %{
            "name" => name,
            "value" => binding,
            "reference" => %{"source" => "result", "component" => source, "path" => path}
          } <- flow["output"],
          producer <- output_producers(Map.get(nodes_by_component, source, []), path),
          do: edge(producer.id, output.id, name, detail: binding)

    edges = dependencies ++ output_edges ++ Enum.map(outcomes, &edge(output.id, &1.id, &1.kind))
    columns = [[input] | columns] ++ [[output]] ++ if(outcomes == [], do: [], else: [outcomes])

    graph(key, label(flow["name"]), columns, edges, :flow)
  end

  defp component_nodes(%{"kind" => "parallel", "options" => [_ | _]} = component, _flows) do
    Enum.map(component["options"], fn option ->
      node(option_id(component, option), "Parallel action", label(option["name"]),
        detail: option["handler"]["target"],
        fields: option["inputs"]
      )
    end)
  end

  defp component_nodes(component, flows) do
    target = component["handler"]["target"]
    kind = component["handler"]["kind"] || component["kind"]

    [
      node(step_id(component["name"]), label(kind), label(component["name"]),
        detail: target,
        fields: component["inputs"],
        options: component["options"],
        open_flow: if(Map.has_key?(flows, target), do: target)
      )
    ]
  end

  defp output_producers([%{kind: "Parallel action"} | _] = nodes, [index | _])
       when is_integer(index) and index >= 0 do
    Enum.slice(nodes, index, 1)
  end

  defp output_producers(nodes, _path), do: nodes
  defp step_id(name), do: "step:" <> name
  defp option_id(component, option), do: step_id(component["name"]) <> ":" <> option["name"]

  defp input_node(nil), do: node("input", "Input", "Flow input")

  defp input_node(route),
    do:
      node("signal", "Signal", signal_label(route["signal"]),
        detail: route["signal"],
        fields: route["defaults"]
      )

  defp action_graph(key, route) do
    input = input_node(route)
    handler = route["handler"]

    action =
      node("handler", label(handler["kind"]), module_label(handler["target"]),
        detail: handler["target"]
      )

    outcomes = outcome_nodes(route)

    edges = [
      edge(input.id, action.id, "Route handler")
      | Enum.map(outcomes, &edge(action.id, &1.id, &1.detail))
    ]

    columns = [[input], [action]] ++ if(outcomes == [], do: [], else: [outcomes])

    graph(key, signal_label(route["signal"]), columns, edges, :flow)
  end

  defp outcome_nodes(route) do
    state =
      if route["state"], do: node("state", "State", "Commit agent state", detail: route["state"])

    reply =
      if data = route["reply"] do
        node("reply", "Reply", signal_label(data["signal"]),
          detail: data["signal"],
          fields: [field("From", data["from"])]
        )
      end

    Enum.reject([state, reply], &is_nil/1)
  end

  defp graph(key, title, columns, edges, kind) do
    nodes = List.flatten(columns)
    node_ids = MapSet.new(nodes, & &1.id)

    edges =
      Enum.filter(edges, &(MapSet.member?(node_ids, &1.from) and MapSet.member?(node_ids, &1.to)))

    %{key: key, title: title, kind: kind, columns: columns, nodes: nodes, edges: edges}
  end

  defp node(id, kind, title, opts \\ []) do
    %{
      id: id,
      kind: kind,
      title: title,
      caption: opts[:caption],
      detail: opts[:detail],
      fields: opts[:fields] || [],
      options: opts[:options] || [],
      open_flow: opts[:open_flow]
    }
  end

  defp edge(from, to, label, opts \\ []) do
    %{
      id: Enum.join([from, to, label], "|"),
      from: from,
      to: to,
      label: label,
      detail: opts[:detail],
      active: opts[:active] || false
    }
  end

  defp field(name, value), do: %{"name" => name, "value" => value}
  defp label(value), do: Phoenix.Naming.humanize(value)

  defp signal_label(signal),
    do: signal |> String.split(".") |> Enum.take(-2) |> Enum.join("_") |> label()

  defp module_label(target),
    do: target |> String.split(".") |> List.last() |> Phoenix.Naming.underscore() |> label()
end
