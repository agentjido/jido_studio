defmodule StudioPlayground.DemoCounter do
  @moduledoc false

  alias Jido.Joi
  alias StudioPlayground.DemoCounter.{Increment, IncrementAction}

  use Jido.Agent, name: "Demo counter", description: "Counts increments sent from Studio."

  state do
    schema(Joi.object(%{count: Joi.integer()}))
    initial_state(%{count: 0})
  end

  routes do
    signal_source("/studio-playground/demo-counter")

    route Increment.type(), IncrementAction do
      reply("demo.counter.updated", from: output())
    end
  end
end
