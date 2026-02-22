defmodule JidoStudio.ObservabilityCorrelationTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Observability.Correlation

  test "normalize/1 populates canonical correlation keys from metadata and scope" do
    record = %{
      metadata: %{
        trace_id: "trace-1",
        jido_span_id: "span-1",
        jido_parent_span_id: "parent-1",
        agent_id: "agent-1",
        agent_module: "Demo.Agent",
        action: "tool.lookup",
        workflow_id: "wf-1",
        signal_type: "agent.signal",
        request_id: "req-1",
        project_id: "project-meta",
        user_id: "user-meta"
      },
      scope: %{project_id: "project-scope", user_id: "user-scope"}
    }

    normalized = Correlation.normalize(record)

    assert normalized.trace_id == "trace-1"
    assert normalized.span_id == "span-1"
    assert normalized.parent_span_id == "parent-1"
    assert normalized.agent_id == "agent-1"
    assert normalized.agent_module == "Demo.Agent"
    assert normalized.action == "tool.lookup"
    assert normalized.workflow_id == "wf-1"
    assert normalized.signal_type == "agent.signal"
    assert normalized.request_id == "req-1"
    assert normalized.project_id == "project-scope"
    assert normalized.user_id == "user-scope"
    assert is_integer(normalized.ts)
    assert normalized.incident_id == "req:req-1"
  end

  test "incident_id/1 falls back to trace when request id is missing" do
    record = %{trace_id: "trace-42"}

    assert Correlation.incident_id(record) == "trace:trace-42"
  end
end
