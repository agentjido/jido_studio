defmodule StudioPlayground.StartingAgent do
  @moduledoc false
  use Jido.Agent, name: "Starting counter", plugins: [StudioPlayground.AgentStartGate]
end
