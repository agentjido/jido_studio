defmodule JidoStudio.StarterOperationsTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Agents.StarterOperations
  alias JidoStudio.BeginnerAgent

  test "beginner operations use deterministic order and payload presets" do
    interaction_model = %{
      signals: [
        %{
          key: "s1",
          signal_type: "beginner.tip",
          priority: 0,
          route_available?: true,
          advanced?: false
        },
        %{
          key: "s2",
          signal_type: "beginner.reset",
          priority: 0,
          route_available?: true,
          advanced?: false
        },
        %{
          key: "s3",
          signal_type: "beginner.add",
          priority: 0,
          route_available?: true,
          advanced?: false
        },
        %{
          key: "s4",
          signal_type: "beginner.ping",
          priority: 0,
          route_available?: true,
          advanced?: false
        }
      ],
      actions: []
    }

    operations = StarterOperations.list(%{module: BeginnerAgent}, interaction_model)

    assert Enum.map(operations, & &1.signal_type) == [
             "beginner.ping",
             "beginner.add",
             "beginner.tip",
             "beginner.reset"
           ]

    ping = Enum.find(operations, &(&1.signal_type == "beginner.ping"))
    assert ping.payload == %{"message" => "hello", "count" => 1}
  end

  test "generic operations ignore advanced signals and keep stable order" do
    interaction_model = %{
      signals: [
        %{
          key: "b",
          signal_type: "zeta.run",
          priority: 0,
          route_available?: false,
          advanced?: false
        },
        %{
          key: "a",
          signal_type: "alpha.run",
          priority: 0,
          route_available?: false,
          advanced?: false
        },
        %{
          key: "internal",
          signal_type: "jido.internal",
          priority: 0,
          route_available?: true,
          advanced?: true
        }
      ],
      actions: []
    }

    operations =
      StarterOperations.list(%{module: Jido.AI.Examples.CalculatorAgent}, interaction_model)

    assert Enum.map(operations, & &1.signal_type) == ["alpha.run", "zeta.run"]
  end
end
