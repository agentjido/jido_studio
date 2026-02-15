defmodule JidoStudio.IngestorTracingTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Ingestor
  alias JidoStudio.Tracing

  setup do
    old_persistence = Application.get_env(:jido_studio, :persistence)

    Application.put_env(:jido_studio, :persistence,
      adapter: JidoStudio.Persistence.ETS,
      opts: [event_retention: 200]
    )

    clear_table(:jido_studio_persistence_docs)
    clear_table(:jido_studio_persistence_events)
    clear_table(:jido_studio_persistence_event_seq)

    on_exit(fn ->
      Application.put_env(:jido_studio, :persistence, old_persistence)
    end)

    :ok
  end

  test "ingestor materializes trace and span docs" do
    t0 = System.system_time(:millisecond)

    Ingestor.ingest_event(%{
      trace_id: "trace-abc",
      span_id: "span-root",
      parent_span_id: nil,
      agent_id: "weather-agent-1",
      type: :start,
      event_name: "jido.agent.cmd.start",
      timestamp_ms: t0,
      metadata: %{}
    })

    Ingestor.ingest_event(%{
      trace_id: "trace-abc",
      span_id: "span-child",
      parent_span_id: "span-root",
      agent_id: "weather-agent-1",
      type: :start,
      event_name: "jido.ai.tool.execute.start",
      timestamp_ms: t0 + 10,
      metadata: %{}
    })

    Ingestor.ingest_event(%{
      trace_id: "trace-abc",
      span_id: "span-child",
      parent_span_id: "span-root",
      agent_id: "weather-agent-1",
      type: :stop,
      event_name: "jido.ai.tool.execute.stop",
      timestamp_ms: t0 + 30,
      metadata: %{}
    })

    Ingestor.ingest_event(%{
      trace_id: "trace-abc",
      span_id: "span-root",
      parent_span_id: nil,
      agent_id: "weather-agent-1",
      type: :stop,
      event_name: "jido.agent.cmd.stop",
      timestamp_ms: t0 + 40,
      metadata: %{}
    })

    Process.sleep(40)

    assert {:ok, trace} = Tracing.get_trace("trace-abc")
    assert trace.status == "ok"
    assert trace.agent_id == "weather-agent-1"
    assert is_integer(trace.duration_ms)
    assert trace.duration_ms >= 40

    spans = Tracing.list_trace_spans("trace-abc")
    assert length(spans) == 2

    root = Enum.find(spans, &(&1.span_id == "span-root"))
    child = Enum.find(spans, &(&1.span_id == "span-child"))

    assert root.depth == 0
    assert child.depth == 1
    assert child.parent_span_id == "span-root"

    events = Tracing.list_trace_events("trace-abc", order: :asc, limit: 10)
    assert length(events) == 4
    assert Enum.map(events, & &1.seq) == [1, 2, 3, 4]
  end

  defp clear_table(table) do
    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end
  end
end
