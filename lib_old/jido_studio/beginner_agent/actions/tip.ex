defmodule JidoStudio.BeginnerAgent.Actions.Tip do
  @moduledoc false

  use Jido.Action,
    name: "beginner_tip",
    description: "Calculate a tip and total deterministically.",
    schema: [
      amount: [type: :float, required: true],
      rate_percent: [type: :float, default: 20.0]
    ]

  @impl true
  def run(params, _ctx) do
    amount = Map.get(params, :amount, 0.0)
    rate = Map.get(params, :rate_percent, 20.0)
    tip = Float.round(amount * rate / 100.0, 2)
    total = Float.round(amount + tip, 2)

    {:ok,
     %{
       last_tip_amount: tip,
       last_total_amount: total,
       last_message: "Tip #{tip} on #{amount} (#{rate}%) => total #{total}"
     }}
  end
end
