defmodule JidoStudio.TurnTrace do
  @moduledoc false

  alias Jido.AgentServer
  alias Jido.Signal.Context

  @compile {:no_warn_undefined, [AgentServer, Context]}

  @settled [:jido, :agent_server, :turn, :settled]
  @events [
    [:jido, :agent_server, :turn, :start],
    [:jido, :action, :start],
    [:jido, :action, :stop],
    [:jido, :action, :exception],
    [:jido, :agent_server, :commit],
    [:jido, :agent_server, :turn, :stop],
    @settled
  ]

  def run(pid, signal, reply_fields) do
    caller = self()
    ref = make_ref()

    # The capture must detach even if LiveView closes while the call is pending.
    {_pid, monitor} =
      spawn_monitor(fn -> send(caller, {ref, capture(pid, signal, reply_fields)}) end)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, _pid, _reason} ->
        {:error, :turn_unavailable}
    end
  end

  defp capture(pid, signal, reply_fields) do
    with {:ok, signal, trace} <- Context.ensure_trace(signal) do
      ref = make_ref()
      config = {self(), ref, trace.trace_id}
      :ok = :telemetry.attach_many(ref, @events, &__MODULE__.record/4, config)

      try do
        case AgentServer.call(pid, signal, 5_000) do
          {:ok, turn} ->
            deadline = System.monotonic_time(:millisecond) + 250
            events = collect(ref, turn.turn_id, deadline, [])

            {:ok,
             %{
               id: turn.turn_id,
               status: turn.status,
               revision: turn.agent_revision,
               signal_id: signal.id,
               signal_type: signal.type,
               trace_id: trace.trace_id,
               reply: reply(turn.reply, reply_fields),
               events: events
             }}

          {:error, _reason} ->
            {:error, :turn_rejected}
        end
      catch
        :exit, {:timeout, _details} -> {:error, :turn_timeout}
        :exit, _reason -> {:error, :turn_unavailable}
      after
        :telemetry.detach(ref)
      end
    end
  end

  def record(
        name,
        measurements,
        %{trace_id: trace_id, turn_id: turn_id} = metadata,
        {receiver, ref, trace_id}
      ) do
    event = %{
      name: name,
      span_id: Map.get(metadata, :span_id),
      action: Map.get(metadata, :action_name),
      duration: Map.get(measurements, :duration)
    }

    send(receiver, {ref, turn_id, event})
    :ok
  end

  def record(_name, _measurements, _metadata, _config), do: :ok

  defp collect(ref, turn_id, deadline, events) do
    receive do
      {^ref, ^turn_id, %{name: @settled} = event} ->
        Enum.reverse([event | events])

      {^ref, ^turn_id, event} when length(events) < 63 ->
        collect(ref, turn_id, deadline, [event | events])
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> Enum.reverse(events)
    end
  end

  defp reply(%{type: type, data: data}, fields) when is_map(data) do
    values =
      data
      |> Map.take(fields)
      |> Map.filter(fn {_key, value} -> is_number(value) or is_boolean(value) end)

    %{type: type, data: values}
  end

  defp reply(_reply, _fields), do: nil
end
