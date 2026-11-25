defmodule JidoStudio.TurnHistory do
  @moduledoc false
  use GenServer

  @settled [:jido, :agent_server, :turn, :settled]
  @capacity 512
  @page_limit 50
  @fields [:signal_id, :signal_type, :status, :stage, :committed?, :trace_id, :span_id]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def list(worker, timeout), do: GenServer.call(__MODULE__, {:list, worker}, timeout)

  @impl true
  def init(nil) do
    Process.flag(:trap_exit, true)
    :telemetry.detach(__MODULE__)
    :ok = :telemetry.attach(__MODULE__, @settled, &__MODULE__.record/4, self())
    {:ok, {0, :queue.new()}}
  end

  @impl true
  def terminate(_reason, _state), do: :telemetry.detach(__MODULE__)

  def record(@settled, _measurements, %{turn_id: id} = metadata, receiver) when is_binary(id) do
    turn =
      metadata
      |> Map.take(@fields)
      |> Map.merge(%{id: id, settled_at: DateTime.utc_now()})

    # Telemetry invokes this handler in the emitting AgentServer worker.
    # The worker PID distinguishes agents with identical IDs in different scopes.
    GenServer.cast(receiver, {:settled, self(), turn})
  end

  def record(_event, _measurements, _metadata, _receiver), do: :ok

  @impl true
  def handle_cast({:settled, worker, turn}, {size, turns}) do
    turns = if size == @capacity, do: :queue.drop_r(turns), else: turns
    {:noreply, {min(size + 1, @capacity), :queue.in_r({worker, turn}, turns)}}
  end

  @impl true
  def handle_call({:list, worker}, _from, {_size, turns} = state) do
    matches =
      for {^worker, turn} <- :queue.to_list(turns), do: turn

    {:reply, Enum.take(matches, @page_limit), state}
  end
end
