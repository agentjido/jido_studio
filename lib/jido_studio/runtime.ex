defmodule JidoStudio.Runtime do
  @moduledoc false
  use Supervisor

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children =
      JidoStudio.Persistence.child_specs(opts) ++
        [
          {JidoStudio.Ingestor, opts},
          {JidoStudio.TraceBuffer, opts},
          {JidoStudio.Threads.Manager, opts}
        ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
