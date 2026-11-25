defmodule JidoStudio.BeginnerAgent.Actions.Add do
  @moduledoc false

  use Jido.Action,
    name: "beginner_add",
    description: "Compute a deterministic addition result for onboarding practice.",
    schema: [
      a: [type: :float, required: true],
      b: [type: :float, required: true]
    ]

  @impl true
  def run(params, _ctx) do
    a = Map.get(params, :a, 0.0)
    b = Map.get(params, :b, 0.0)
    result = Float.round(a + b, 3)

    {:ok,
     %{
       last_addition_result: result,
       last_message: "#{a} + #{b} = #{result}"
     }}
  end
end
