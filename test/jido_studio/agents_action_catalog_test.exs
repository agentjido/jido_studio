defmodule JidoStudio.AgentsActionCatalogTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Agents.ActionCatalog

  defmodule StrategyLike do
    def action_spec(:safe_action) do
      %{
        name: "safe.action",
        doc: "Safe schema action",
        schema: [message: [type: :string, required: true]]
      }
    end

    def action_spec(:zoi_any_action) do
      %{
        name: "zoi.any.action",
        doc: "Schema that may not convert cleanly to JSON schema",
        schema: Zoi.any()
      }
    end

    def action_spec(_), do: nil
  end

  defmodule AgentLike do
    def strategy, do: StrategyLike
    def strategy_opts, do: []
    def actions, do: [Jido.Actions.Control.Noop]
  end

  test "builds action rows from route targets and plugin actions" do
    signals = [
      %{
        key: "a",
        signal_type: "demo.safe",
        source: :strategy,
        target: {:strategy_cmd, :safe_action}
      },
      %{key: "b", signal_type: "demo.noop", source: :plugin, target: Jido.Actions.Control.Noop}
    ]

    model = ActionCatalog.build(AgentLike, signals)

    assert model.actions != []
    assert Enum.any?(model.actions, &(&1.kind == :strategy_cmd and &1.label == "safe.action"))

    assert Enum.any?(
             model.actions,
             &(&1.kind == :action_module and &1.module == Jido.Actions.Control.Noop)
           )
  end

  test "does not raise when schema conversion fails" do
    signals = [
      %{
        key: "a",
        signal_type: "demo.any",
        source: :strategy,
        target: {:strategy_cmd, :zoi_any_action}
      }
    ]

    model = ActionCatalog.build(AgentLike, signals)

    assert model.actions != []

    row =
      Enum.find(model.actions, &(&1.kind == :strategy_cmd and &1.action == :zoi_any_action))

    refute is_nil(row)
    assert row.kind == :strategy_cmd
    assert is_boolean(row.convertible_schema?)
    assert is_list(model.warnings)
  end
end
