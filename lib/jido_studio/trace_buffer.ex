defmodule JidoStudio.TraceBuffer do
  @moduledoc false
  use GenServer

  @default_size 500
  @table :jido_studio_traces

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def events(limit \\ 50) do
    case :ets.info(@table) do
      :undefined -> []
      _ -> :ets.tab2list(@table) |> Enum.sort_by(&elem(&1, 0), :desc) |> Enum.take(limit) |> Enum.map(&elem(&1, 1))
    end
  end

  @impl true
  def init(opts) do
    size = Keyword.get(opts, :size, Application.get_env(:jido_studio, :trace_buffer_size, @default_size))
    :ets.new(@table, [:ordered_set, :public, :named_table])

    attach_telemetry()

    {:ok, %{size: size, counter: 0}}
  end

  @impl true
  def handle_info({:telemetry_event, event, measurements, metadata}, state) do
    counter = state.counter + 1
    :ets.insert(@table, {counter, %{event: event, measurements: measurements, metadata: metadata, timestamp: System.system_time(:millisecond)}})

    if counter > state.size do
      case :ets.first(@table) do
        :"$end_of_table" -> :ok
        key -> :ets.delete(@table, key)
      end
    end

    {:noreply, %{state | counter: counter}}
  end

  defp attach_telemetry do
    events = [
      [:jido, :agent, :start],
      [:jido, :agent, :stop],
      [:jido, :agent, :exception],
      [:jido, :action, :start],
      [:jido, :action, :stop],
      [:jido, :action, :exception],
      [:jido, :workflow, :start],
      [:jido, :workflow, :stop],
      [:jido, :signal, :dispatch]
    ]

    pid = self()

    :telemetry.attach_many(
      "jido-studio-trace-buffer",
      events,
      fn event, measurements, metadata, _config ->
        send(pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )
  end
end
