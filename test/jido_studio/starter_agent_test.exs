defmodule JidoStudio.StarterAgentTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Beginner
  alias JidoStudio.Onboarding.StarterAgent

  test "pick prefers bundled beginner agent when available" do
    beginner = %{
      module: Beginner.module(),
      name: "jido_studio_beginner",
      slug: "beginner",
      description: "starter",
      tags: ["studio", "beginner"],
      running_instances: []
    }

    calculator = %{
      module: Jido.AI.Examples.CalculatorAgent,
      name: "calculator_agent",
      slug: "calculator",
      description: "calculator",
      tags: ["demo"],
      running_instances: []
    }

    assert {picked, reason} = StarterAgent.pick([calculator, beginner])
    assert picked.module == Beginner.module()
    assert reason =~ "Built-in Studio beginner agent"
  end

  test "pick falls back to calculator-like agent when beginner is unavailable" do
    calculator = %{
      module: Jido.AI.Examples.CalculatorAgent,
      name: "calculator_agent",
      slug: "calculator",
      description: "calculator",
      tags: ["demo"],
      running_instances: []
    }

    weather = %{
      module: Jido.AI.Examples.WeatherAgent,
      name: "weather_agent",
      slug: "weather",
      description: "weather",
      tags: ["demo"],
      running_instances: []
    }

    assert {picked, reason} = StarterAgent.pick([weather, calculator])
    assert picked.module == Jido.AI.Examples.CalculatorAgent
    assert reason =~ "Calculator-like flow"
  end

  test "pick falls back to stable first product agent when no beginner or calculator exists" do
    bravo = %{
      module: :"Elixir.TestSupport.Starter.Bravo",
      name: "bravo_agent",
      slug: "bravo",
      description: "bravo",
      tags: [],
      running_instances: []
    }

    alpha = %{
      module: :"Elixir.TestSupport.Starter.Alpha",
      name: "alpha_agent",
      slug: "alpha",
      description: "alpha",
      tags: [],
      running_instances: []
    }

    assert {picked, reason} = StarterAgent.pick([bravo, alpha])
    assert picked.slug == "alpha"
    assert reason =~ "First available product agent"
  end
end
