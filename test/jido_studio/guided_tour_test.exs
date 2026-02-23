defmodule JidoStudio.GuidedTourTest do
  use ExUnit.Case, async: true

  alias JidoStudio.GuidedTour

  test "flows expose stable keys, steps, and selector metadata" do
    flows = GuidedTour.flows()

    assert is_list(flows)
    assert length(flows) >= 3

    flow_keys = Enum.map(flows, & &1.key)
    assert Enum.uniq(flow_keys) == flow_keys

    Enum.each(flows, fn flow ->
      assert is_binary(flow.key)
      assert is_binary(flow.label)
      assert is_binary(flow.description)
      assert is_integer(flow.duration_minutes)
      assert flow.duration_minutes > 0
      assert is_list(flow.steps)
      assert flow.steps != []

      Enum.each(flow.steps, fn step ->
        assert is_binary(step.key)
        assert is_binary(step.title)
        assert is_binary(step.body)
        assert is_binary(step.path)
        assert String.starts_with?(step.path, "/")
        assert is_binary(step.selector)
        assert is_binary(step.fallback)
      end)
    end)
  end

  test "flow/1 returns named flow and nil for missing" do
    assert %{key: "first_5_minutes"} = GuidedTour.flow("first_5_minutes")
    assert GuidedTour.flow("missing-flow") == nil
    assert GuidedTour.flow(nil) == nil
  end

  test "flows_json/0 returns decodable flow catalog" do
    {:ok, decoded} =
      GuidedTour.flows_json()
      |> Jason.decode()

    assert is_list(decoded)
    assert Enum.any?(decoded, &(&1["key"] == "first_5_minutes"))
  end

  test "setup flow includes inventory and starter selector steps" do
    flow = GuidedTour.flow("setup_and_first_interaction")
    assert flow != nil

    inventory_step = Enum.find(flow.steps, &(&1.key == "agents_inventory_explainer"))
    starter_step = Enum.find(flow.steps, &(&1.key == "agents_starter_agent"))

    assert inventory_step.path == "/agents"
    assert inventory_step.selector == ~s([data-tour-id="agents-inventory-explainer"])

    assert starter_step.path == "/agents"
    assert starter_step.selector == ~s([data-tour-id="agents-starter-agent"])
  end
end
