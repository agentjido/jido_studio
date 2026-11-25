defmodule StudioPlayground.AgentStartGate do
  @moduledoc false
  use Jido.Plugin

  @impl true
  def child_spec(_init), do: Supervisor.child_spec({Agent, fn -> nil end}, id: __MODULE__)

  @impl true
  def await_ready(_pid, _opts) do
    send(StudioPlaygroundWeb.StudioAgentsTest, {:agent_starting, self()})

    receive do
      :finish_start -> :ok
    after
      10_000 -> {:error, :timeout}
    end
  end
end
