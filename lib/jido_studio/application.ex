defmodule JidoStudio.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([JidoStudio.TurnHistory], strategy: :one_for_one)
  end
end
