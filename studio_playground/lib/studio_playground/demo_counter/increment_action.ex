defmodule StudioPlayground.DemoCounter.IncrementAction do
  @moduledoc false
  alias Jido.Joi

  use Jido.Action,
    name: "increment_demo_counter",
    schema: Joi.object(%{amount: Joi.integer() |> Joi.min(1) |> Joi.max(10)}),
    output_schema: Joi.object(%{count: Joi.integer()})

  @impl true
  def run(%{amount: amount}, %{agent_state: %{count: count}}) do
    {:ok, %{count: count + amount}}
  end
end
