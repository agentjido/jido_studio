defmodule JidoStudio.DiagnosticsTimelineTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Diagnostics.Timeline
  alias JidoStudio.Persistence

  test "build/3 shapes lane-aware timeline model with selected span" do
    trace = %{
      trace_id: "trace-build-1",
      started_at: 1_000,
      duration_ms: 600,
      span_count: 3
    }

    spans = [
      %{
        span_id: "span-root",
        event_name: "agent.run",
        entity_type: "agent",
        entity_id: "calculator-demo",
        offset_ms: 0,
        duration_ms: 600,
        critical_path: true,
        status: "ok"
      },
      %{
        span_id: "span-tool",
        parent_span_id: "span-root",
        event_name: "tool.add",
        entity_type: "tool",
        entity_id: "Add",
        offset_ms: 120,
        duration_ms: 180,
        critical_path: true,
        status: "ok",
        call_id: "call-1",
        task_id: "task-1"
      },
      %{
        span_id: "span-middleware",
        parent_span_id: "span-root",
        event_name: "middleware.audit",
        entity_type: "middleware",
        entity_id: "Audit",
        offset_ms: 80,
        duration_ms: 40,
        critical_path: false,
        status: "ok"
      }
    ]

    model = Timeline.build(trace, spans, selected_span_id: "span-tool", critical: true)

    assert model.trace_id == "trace-build-1"
    assert model.timed_span_count == 3
    assert length(model.lanes) == 3
    assert model.selected_span.span_id == "span-tool"
    assert "span-root" in model.critical_path_ids
    assert "span-tool" in model.critical_path_ids
    assert Enum.all?(model.spans, &is_number(&1.left_pct))
    assert Enum.all?(model.spans, &is_number(&1.width_pct))
  end

  test "build/3 reports truncated and missing timing states" do
    trace = %{
      trace_id: "trace-build-2",
      started_at: 1_000,
      duration_ms: 400,
      span_count: 8
    }

    spans = [
      %{
        span_id: "span-ok",
        event_name: "agent.step",
        entity_type: "agent",
        entity_id: "calculator-demo",
        offset_ms: 0,
        duration_ms: 120,
        status: "ok"
      },
      %{
        span_id: "span-no-time",
        event_name: "tool.unknown",
        entity_type: "tool",
        entity_id: "Unknown",
        duration_ms: nil,
        status: "ok"
      }
    ]

    model = Timeline.build(trace, spans, span_cap: 2, critical: true)

    assert model.truncated?
    assert model.timing_unavailable_count == 1
    assert Enum.any?(model.warnings, &String.contains?(&1, "Span cap reached"))
    assert Enum.any?(model.warnings, &String.contains?(&1, "missing timing data"))
  end

  test "build/3 clears critical-path highlighting when disabled" do
    trace = %{trace_id: "trace-build-3", started_at: 1_000, duration_ms: 300}

    spans = [
      %{
        span_id: "span-1",
        event_name: "agent.run",
        entity_type: "agent",
        entity_id: "calculator-demo",
        offset_ms: 0,
        duration_ms: 300,
        critical_path: true,
        status: "ok"
      }
    ]

    model = Timeline.build(trace, spans, critical: false)

    assert model.critical? == false
    assert model.critical_path_ids == []
    assert Enum.all?(model.spans, &(&1.critical_path? == false))
  end

  test "pick_recent_traces/2 returns summaries for the selected node scope" do
    trace_id = "timeline-pick-#{System.unique_integer([:positive])}"
    started_at = System.system_time(:millisecond) - 1_000

    assert :ok =
             Persistence.put_doc("traces", trace_id, %{
               trace_id: trace_id,
               started_at: started_at,
               duration_ms: 125,
               status: "ok",
               agent_id: "calculator-demo"
             })

    on_exit(fn ->
      _ = Persistence.delete_doc("traces", trace_id)
    end)

    results = Timeline.pick_recent_traces({:node, Node.self()}, limit: 10, range: "1h")

    assert Enum.any?(results, &(&1.trace_id == trace_id))
  end
end
