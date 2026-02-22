defmodule JidoStudio.AgentsIntrospectionTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Agents.Introspection

  setup do
    old_config = Application.get_env(:jido_studio, :agent_interactions, [])
    Application.put_env(:jido_studio, :agent_interactions, enabled: true, default_tab: :auto)

    on_exit(fn ->
      Application.put_env(:jido_studio, :agent_interactions, old_config)
    end)

    :ok
  end

  defmodule StrategyLike do
    def signal_routes(_ctx) do
      [{"strategy.input", {:strategy_cmd, :safe_action}}]
    end

    def action_spec(:safe_action) do
      %{name: "safe.action", doc: "Safe action", schema: [query: [type: :string, required: true]]}
    end

    def action_spec(_), do: nil
  end

  defmodule AgentLike do
    def strategy, do: StrategyLike
    def strategy_opts, do: []
    def signal_routes(_ctx), do: [{"agent.control", Jido.Actions.Control.Noop}]

    def plugin_routes do
      [
        {"plugin.demo", Jido.Actions.Control.Noop, -10},
        {"plugin.__schedule__.tick", Jido.Actions.Control.Noop, -20}
      ]
    end

    def actions, do: [Jido.Actions.Control.Noop]
  end

  test "builds hybrid static introspection model" do
    model = Introspection.build(AgentLike, nil)

    assert model.runner_supported? == true
    assert model.chat_supported? == false
    assert model.primary_default_tab == :interact

    assert Enum.any?(model.signals, &(&1.signal_type == "strategy.input"))
    assert Enum.any?(model.signals, &(&1.signal_type == "agent.control"))
    assert Enum.any?(model.signals, &(&1.signal_type == "plugin.demo"))
    assert Enum.any?(model.signals, &(&1.signal_type == "plugin.__schedule__.tick" and &1.advanced?))

    assert Enum.any?(model.actions, &(&1.kind == :strategy_cmd))
  end

  test "defaults to chat for chat-capable modules under auto mode" do
    model = Introspection.build(Jido.AI.Examples.WeatherAgent, nil)

    assert model.chat_supported? == true
    assert model.primary_default_tab == :chat
  end
end
