defmodule JidoStudio.DefinitionSnapshot do
  @moduledoc """
  Projects compiled Jido agent and flow maps into data for a definition preview.
  """

  @doc """
  Builds a JSON-compatible renderer input from a root agent and its visual map.

  Pass a trusted definition with initial state that can be shown to the reader.
  Optional flow graphs contain dependency names and levels from the compiler.
  The snapshot omits executable values and plugin options.
  """
  @spec from_visual_map(%{root: module(), agents: map(), flows: map()}, map()) :: map()
  def from_visual_map(%{root: root, agents: agents, flows: flows}, graphs \\ %{}) do
    agent = Map.fetch!(agents, root)

    %{
      "name" => agent.name,
      "id" => agent.id,
      "description" => agent.description,
      "source" => agent.signal_source,
      "initial_state" => fields(agent.initial_state),
      "routes" => Enum.map(agent.routes, &route/1),
      "topology" => topology(agent, agents),
      "flows" =>
        Map.new(flows, fn {module, definition} ->
          {inspect(module), flow(definition, Map.get(graphs, module, %{}))}
        end)
    }
  end

  defp topology(agent, agents) do
    %{
      "members" =>
        Enum.map(agent.topology.agents, fn member ->
          definition = Map.fetch!(agents, member.definition)

          %{
            "name" => to_string(member.name),
            "definition" => inspect(member.definition),
            "count" => member.count,
            "routes" => Enum.map(definition.routes, &route/1)
          }
        end),
      "connections" =>
        Enum.map(agent.topology.connections, fn connection ->
          %{
            "signal" => connection.path,
            "from" => endpoint(connection.from),
            "to" => endpoint(connection.to),
            "delivery" => to_string(connection.delivery)
          }
        end)
    }
  end

  defp endpoint(%{kind: kind, name: name}) do
    %{"kind" => to_string(kind), "name" => to_string(name)}
  end

  defp route(route) do
    %{
      "signal" => route.path,
      "handler" => handler(route.handler),
      "defaults" => fields(route.defaults),
      "state" => if(route.state != :unchanged, do: reference(route.state)),
      "reply" =>
        route.reply && %{"signal" => route.reply.type, "from" => reference(route.reply.from)}
    }
  end

  defp flow(flow, graph) do
    levels = Map.get(graph, :levels, %{})
    dependencies = Map.get(graph, :dependencies, %{})

    %{
      "name" => flow.name,
      "components" =>
        Enum.map(Enum.sort(flow.components), fn {name, component} ->
          %{
            "name" => name,
            "kind" => to_string(component.kind),
            "level" => Map.get(levels, name, 0),
            "needs" => Map.get(dependencies, name, component.needs),
            "handler" => Map.get(component, :call) && handler(component.call),
            "inputs" => fields(get_in(component, [:call, :params]) || %{}),
            "options" => options(component)
          }
        end),
      "output" => fields(flow.output || %{})
    }
  end

  defp options(%{kind: :parallel, actions: actions}) do
    Enum.map(actions, fn action ->
      %{
        "name" => action.name,
        "handler" => handler(action.call),
        "inputs" => fields(action.call.params)
      }
    end)
  end

  defp options(%{kind: :wait, options: options}) do
    Enum.map(options, fn option ->
      %{
        "name" => option.name,
        "event" => option.event,
        "after_ms" => option.after_ms,
        "inputs" => fields(option.match)
      }
    end)
  end

  defp options(%{kind: :choice, options: options, fallback: fallback}) do
    choices = Enum.map(options, &choice(&1.name, &1.call, display(&1.condition)))
    if fallback, do: choices ++ [choice("otherwise", fallback, nil)], else: choices
  end

  defp options(_component), do: []

  defp choice(name, call, condition) do
    %{
      "name" => name,
      "condition" => condition,
      "handler" => handler(call),
      "inputs" => fields(call.params)
    }
  end

  defp handler(%{kind: kind, target: target}) do
    %{"kind" => to_string(kind), "target" => target_label(target)}
  end

  defp target_label({module, _function, _arity}), do: inspect(module) <> " (inline)"

  defp target_label(module) do
    case inspect(module) do
      "Jido.Action.Generated.Inline." <> _hash -> "Inline action"
      label -> label
    end
  end

  defp fields(values) when is_map(values) and not is_struct(values) do
    values
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> field(to_string(key), value) end)
  end

  defp fields(nil), do: []
  defp fields(value), do: [field("value", value)]

  defp field(
         name,
         %{__struct__: Jido.Flow.Ref, component: component, source: source, path: path} = ref
       ) do
    %{
      "name" => name,
      "value" => reference(ref),
      "reference" => %{"component" => component, "source" => to_string(source), "path" => path}
    }
  end

  defp field(name, value), do: %{"name" => name, "value" => display(value)}

  defp display(%{source: _source, path: _path, __struct__: Jido.Flow.Ref} = ref),
    do: reference(ref)

  defp display(%{operator: operator, operands: [left, right], __struct__: Jido.Expr.Operation}),
    do: "#{display(left)} #{operator} #{display(right)}"

  defp display(value) when is_map(value) and not is_struct(value) and map_size(value) > 0 do
    entries = Enum.map_join(fields(value), ", ", &"#{&1["name"]}: #{&1["value"]}")
    "{" <> entries <> "}"
  end

  defp display(value), do: inspect(value, limit: 12, printable_limit: 200)

  defp reference(%{source: source, path: path} = ref) do
    prefix = Enum.reject([Map.get(ref, :component), source], &is_nil/1)
    Enum.map_join(prefix ++ path, ".", &to_string/1)
  end
end
