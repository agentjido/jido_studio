defmodule StudioPlayground.DemoAgents do
  @moduledoc false

  alias Jido.{Agent, Joi}

  def start! do
    start_agent!("inventory/east", "Inventory counter", "Tracks stock for the east warehouse.",
      stock: 24,
      reserved: 3
    )

    start_agent!("inventory/west", "Inventory counter", "Tracks stock for the west warehouse.",
      stock: 16,
      reserved: 1
    )

    start_agent!("order-review", "Order review", "Tracks the order review queue.",
      queued: 7,
      reviewed: 12,
      flagged: 2
    )
  end

  def start_demo do
    case Jido.start_agent(StudioPlayground.Jido, StudioPlayground.DemoCounter, id: "demo-counter") do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp start_agent!(id, name, description, initial_values) do
    agent = definition(name, description, initial_values)
    {:ok, _pid} = Jido.start_agent(StudioPlayground.Jido, agent, id: id)
    :ok
  end

  defp definition(name, description, initial_values) do
    Agent.define!(%{
      name: name,
      description: description,
      schema:
        Joi.object(Map.new(initial_values, fn {field, _value} -> {field, Joi.integer()} end)),
      initial_state: Map.new(initial_values)
    })
  end
end
