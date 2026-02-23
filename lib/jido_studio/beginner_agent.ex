defmodule JidoStudio.BeginnerAgent do
  @moduledoc false

  alias JidoStudio.BeginnerAgent.Actions

  use Jido.Agent,
    name: "jido_studio_beginner",
    description:
      "Built-in Jido Studio beginner agent for deterministic onboarding without provider keys.",
    category: "onboarding",
    tags: ["studio", "beginner", "demo"],
    schema: [
      last_message: [type: :string, default: "Ready"],
      last_addition_result: [type: :float, default: 0.0],
      last_tip_amount: [type: :float, default: 0.0],
      last_total_amount: [type: :float, default: 0.0],
      ping_count: [type: :non_neg_integer, default: 0]
    ]

  @impl true
  def signal_routes(_ctx) do
    [
      {"beginner.ping", Actions.Ping},
      {"beginner.add", Actions.Add},
      {"beginner.tip", Actions.Tip},
      {"beginner.reset", Actions.Reset}
    ]
  end
end
