defmodule JidoStudio.PresenterResolver do
  @moduledoc """
  Resolves the presenter module for an agent detail page.
  """

  alias JidoStudio.Presenters

  @spec resolve(module() | nil) :: module()
  def resolve(agent_module) when is_atom(agent_module) do
    strategy_module = strategy_module(agent_module)

    cond do
      presenter = agent_override(agent_module) ->
        normalize_presenter(presenter)

      presenter = registry_override(agent_module, strategy_module) ->
        normalize_presenter(presenter)

      strategy_module == Jido.AI.Strategies.ReAct ->
        Presenters.ReAct

      strategy_module == Jido.Agent.Strategy.BehaviorTree ->
        Presenters.BehaviorTree

      true ->
        Presenters.Default
    end
  rescue
    _ -> Presenters.Default
  end

  def resolve(_), do: Presenters.Default

  defp agent_override(agent_module) do
    if function_exported?(agent_module, :studio_presenter, 0) do
      agent_module.studio_presenter()
    end
  rescue
    _ -> nil
  end

  defp registry_override(agent_module, strategy_module) do
    registry = Application.get_env(:jido_studio, :presenter_registry, %{})

    Map.get(registry, agent_module) ||
      if(strategy_module, do: Map.get(registry, strategy_module), else: nil)
  end

  defp strategy_module(agent_module) do
    if function_exported?(agent_module, :strategy, 0) do
      agent_module.strategy()
    end
  rescue
    _ -> nil
  end

  defp normalize_presenter(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :runtime, 3) do
      module
    else
      Presenters.Default
    end
  end

  defp normalize_presenter(_), do: Presenters.Default
end
