defmodule JidoStudio.AgentRegistryTest do
  use ExUnit.Case, async: false

  alias JidoStudio.AgentRegistry

  defmodule TestJido do
    use Jido, otp_app: :jido_studio
  end

  test "discovers jido_ai WeatherAgent via fallback module scanning" do
    discovered = AgentRegistry.list_discovered_agents()
    weather = Enum.find(discovered, &(&1.module == Jido.AI.Examples.WeatherAgent))

    assert weather != nil
    assert weather.name == "weather_agent"
    assert weather.status == :available
  end

  test "maps running instances to the WeatherAgent module" do
    start_supervised!(TestJido)
    instance_id = "weather-test-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.WeatherAgent, id: instance_id)

    weather =
      AgentRegistry.list_agents(jido_instance: TestJido)
      |> Enum.find(&(&1.module == Jido.AI.Examples.WeatherAgent))

    assert weather != nil
    assert weather.status == :running
    assert Enum.any?(weather.running_instances, &(&1.id == instance_id))
  end
end
