defmodule JidoStudio.AgentRegistryTest do
  use ExUnit.Case, async: false

  alias JidoStudio.AgentRegistry
  alias JidoStudio.BeginnerAgent

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

  test "includes bundled beginner agent by default" do
    discovered = AgentRegistry.list_discovered_agents()
    beginner = Enum.find(discovered, &(&1.module == BeginnerAgent))

    assert beginner != nil
    assert beginner.name == "jido_studio_beginner"
  end

  test "hides beginner agent from discovery when disabled and not running" do
    restore = stash_app_env(:jido_studio, :beginner_agent, enabled: false)
    on_exit(restore)

    discovered = AgentRegistry.list_discovered_agents()
    refute Enum.any?(discovered, &(&1.module == BeginnerAgent))

    all_agents = AgentRegistry.list_agents(jido_instance: nil)
    refute Enum.any?(all_agents, &(&1.module == BeginnerAgent))
  end

  test "shows beginner agent when disabled but already running" do
    restore = stash_app_env(:jido_studio, :beginner_agent, enabled: false)
    on_exit(restore)

    start_supervised!(TestJido)
    instance_id = "beginner-running-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, BeginnerAgent, id: instance_id)

    beginner =
      AgentRegistry.list_agents(jido_instance: TestJido)
      |> Enum.find(&(&1.module == BeginnerAgent))

    assert beginner != nil
    assert beginner.status == :running
    assert Enum.any?(beginner.running_instances, &(&1.id == instance_id))
  end

  test "source_app is populated for discovered entries" do
    discovered = AgentRegistry.list_discovered_agents()
    weather = Enum.find(discovered, &(&1.module == Jido.AI.Examples.WeatherAgent))

    assert weather != nil
    assert is_binary(weather.source_app)
    assert weather.source_app != ""
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

  defp stash_app_env(app, key, value) when is_atom(app) and is_atom(key) do
    previous = Application.get_env(app, key, :__unset__)
    Application.put_env(app, key, value)

    fn ->
      case previous do
        :__unset__ -> Application.delete_env(app, key)
        prior -> Application.put_env(app, key, prior)
      end
    end
  end
end
