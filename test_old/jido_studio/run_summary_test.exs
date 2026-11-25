defmodule JidoStudio.RunSummaryTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Agents.RunSummary

  test "build_success captures changed keys from before/after state snapshots" do
    result = %{
      mode: :sync,
      state_before: %{"count" => 1, "message" => "hello"},
      state_after: %{"count" => 2, "message" => "hello"},
      trace_id: "trace-123"
    }

    dispatch_ref = %{signal_type: "beginner.ping"}

    summary = RunSummary.build_success(result, dispatch_ref)

    assert summary.status == :success
    assert summary.trace_id == "trace-123"
    assert summary.changed_keys == ["count"]
    assert [%{key: "count"}] = summary.state_delta
  end

  test "latest_trace_id reads trace_id from event metadata" do
    events = [
      %{metadata: %{trace_id: "trace-abc"}},
      %{trace_id: "trace-def"}
    ]

    assert RunSummary.latest_trace_id(events) == "trace-abc"
  end
end
