defmodule JidoStudio.Onboarding.StarterAgent do
  @moduledoc false

  alias JidoStudio.AgentInteractions
  alias JidoStudio.Beginner

  @type agent_info :: map()

  @spec product_agents([agent_info()]) :: [agent_info()]
  def product_agents(agents) when is_list(agents) do
    internal_tags = AgentInteractions.internal_agent_tags()

    Enum.reject(agents, fn
      %{} = agent ->
        tags = normalize_tags(Map.get(agent, :tags, []))
        Enum.any?(tags, &(&1 in internal_tags))

      _ ->
        true
    end)
  end

  def product_agents(_), do: []

  @spec pick([agent_info()]) :: {agent_info() | nil, String.t()}
  def pick(agents) when is_list(agents) do
    cond do
      starter = Enum.find(agents, &beginner_agent?/1) ->
        {starter, "Built-in Studio beginner agent (deterministic, no API keys required)."}

      starter = Enum.find(agents, &calculator_agent?/1) ->
        {starter, "Calculator-like flow provides a low-risk first interaction path."}

      true ->
        case Enum.sort_by(agents, &agent_sort_key/1) do
          [%{} = starter | _] ->
            {starter, "First available product agent in the selected scope."}

          _ ->
            {nil, "No product agents are available in the selected runtime and node scope."}
        end
    end
  end

  def pick(_),
    do: {nil, "No product agents are available in the selected runtime and node scope."}

  defp beginner_agent?(%{} = agent) do
    module = Map.get(agent, :module)
    is_atom(module) and module == Beginner.module()
  end

  defp beginner_agent?(_), do: false

  defp calculator_agent?(%{} = agent) do
    [
      Map.get(agent, :name),
      Map.get(agent, :slug),
      Map.get(agent, :description),
      module_name(Map.get(agent, :module))
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.any?(fn value ->
      value
      |> String.downcase()
      |> String.contains?("calculator")
    end)
  end

  defp calculator_agent?(_), do: false

  defp agent_sort_key(%{} = agent) do
    name =
      agent
      |> Map.get(:name, "")
      |> to_string()
      |> String.downcase()

    slug =
      agent
      |> Map.get(:slug, "")
      |> to_string()
      |> String.downcase()

    module =
      agent
      |> Map.get(:module)
      |> module_name()
      |> to_string()
      |> String.downcase()

    {name, slug, module}
  end

  defp agent_sort_key(_), do: {"", "", ""}

  defp module_name(module) when is_atom(module), do: Atom.to_string(module)
  defp module_name(_), do: nil

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(fn
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.downcase/1)
  end

  defp normalize_tags(_), do: []
end
