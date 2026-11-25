defmodule StudioPlayground.DemoCounter.Increment do
  @moduledoc false
  alias Jido.Joi

  use Jido.Signal,
    type: "demo.counter.increment",
    default_source: "/studio-playground",
    schema: Joi.object(%{amount: Joi.integer() |> Joi.min(1) |> Joi.max(10) |> Joi.default(1)})
end
