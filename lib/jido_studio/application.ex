defmodule JidoStudio.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JidoStudio.TraceBuffer
    ]

    opts = [strategy: :one_for_one, name: JidoStudio.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
