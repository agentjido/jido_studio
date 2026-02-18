defmodule JidoStudio.TraceBufferTest do
  use ExUnit.Case, async: false

  alias JidoStudio.TraceBuffer

  setup do
    ensure_started(JidoStudio.TraceBuffer, fn -> JidoStudio.TraceBuffer.start_link([]) end)

    table = :jido_studio_traces

    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end

    :ok
  end

  defp ensure_started(name, starter) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case starter.() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end
    end
  end

  test "events/0 returns list" do
    assert is_list(TraceBuffer.events())
  end

  test "filter_events/2 supports binary filter keys safely" do
    events = [
      %{source: :telemetry, agent_id: "a1", trace_id: "t1", call_id: "call-1"},
      %{source: :agent_debug, agent_id: "a2", trace_id: "t2", call_id: "call-2"}
    ]

    assert [%{agent_id: "a1"}] = TraceBuffer.filter_events(events, %{"agent_id" => "a1"})

    assert [%{source: :agent_debug}] =
             TraceBuffer.filter_events(events, %{"source" => "agent_debug"})

    assert [%{call_id: "call-1"}] = TraceBuffer.filter_events(events, %{"call_id" => "call-1"})

    assert length(TraceBuffer.filter_events(events, %{"unknown_filter" => "ignored"})) == 2
  end

  test "normalize_agent_debug_event/2 adds source and instance fields" do
    event = %{
      type: :directive_started,
      at: System.monotonic_time(:millisecond),
      data: %{foo: "bar"}
    }

    normalized = TraceBuffer.normalize_agent_debug_event(event, agent_id: "agent-1")

    assert normalized.source == :agent_debug
    assert normalized.agent_id == "agent-1"
    assert normalized.instance_id == "agent-1"
    assert normalized.metadata[:foo] == "bar"
  end

  test "events_for_instance/2 returns only matching instance events" do
    send(
      TraceBuffer,
      {:telemetry_event, [:jido, :ai, :react, :start], %{system_time: System.system_time()},
       %{agent_id: "inst-1", trace_id: "trace-1"}}
    )

    send(
      TraceBuffer,
      {:telemetry_event, [:jido, :ai, :react, :complete], %{duration: 1000},
       %{agent_id: "inst-2", trace_id: "trace-2"}}
    )

    Process.sleep(20)

    events = TraceBuffer.events_for_instance("inst-1", 20)

    assert events != []
    assert Enum.all?(events, &(&1.instance_id == "inst-1"))
  end
end
