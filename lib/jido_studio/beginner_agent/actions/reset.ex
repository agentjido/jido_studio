defmodule JidoStudio.BeginnerAgent.Actions.Reset do
  @moduledoc false

  use Jido.Action,
    name: "beginner_reset",
    description: "Reset beginner onboarding state fields to defaults.",
    schema: []

  @impl true
  def run(_params, _ctx) do
    {:ok,
     %{
       last_message: "Ready",
       last_addition_result: 0.0,
       last_tip_amount: 0.0,
       last_total_amount: 0.0,
       ping_count: 0
     }}
  end
end
