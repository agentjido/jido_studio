defmodule JidoStudio.BeginnerAgentTest do
  use ExUnit.Case, async: true

  alias JidoStudio.BeginnerAgent
  alias JidoStudio.BeginnerAgent.Actions

  test "signal routes expose beginner onboarding actions" do
    routes = BeginnerAgent.signal_routes(%{})

    assert {"beginner.ping", Actions.Ping} in routes
    assert {"beginner.add", Actions.Add} in routes
    assert {"beginner.tip", Actions.Tip} in routes
    assert {"beginner.reset", Actions.Reset} in routes
  end

  test "add action returns deterministic output" do
    assert {:ok, result} = Actions.Add.run(%{a: 25.0, b: 4.0}, %{})
    assert result.last_addition_result == 29.0
    assert result.last_message == "25.0 + 4.0 = 29.0"
  end

  test "tip action returns deterministic output" do
    assert {:ok, result} = Actions.Tip.run(%{amount: 42.5, rate_percent: 20.0}, %{})
    assert result.last_tip_amount == 8.5
    assert result.last_total_amount == 51.0
    assert result.last_message == "Tip 8.5 on 42.5 (20.0%) => total 51.0"
  end

  test "ping and reset actions are deterministic" do
    assert {:ok, ping_result} = Actions.Ping.run(%{message: "hello", count: 3}, %{})
    assert ping_result.ping_count == 3
    assert ping_result.last_message == "Ping acknowledged: hello"

    assert {:ok, reset_result} = Actions.Reset.run(%{}, %{})
    assert reset_result.last_message == "Ready"
    assert reset_result.last_addition_result == 0.0
    assert reset_result.last_tip_amount == 0.0
    assert reset_result.last_total_amount == 0.0
    assert reset_result.ping_count == 0
  end
end
