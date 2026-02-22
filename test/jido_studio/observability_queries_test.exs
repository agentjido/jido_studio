defmodule JidoStudio.ObservabilityQueriesTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Ingestor
  alias JidoStudio.Observability.Actions
  alias JidoStudio.Observability.Incidents
  alias JidoStudio.Observability.Signals
  alias JidoStudio.Observability.Workflows

  setup do
    old_persistence = Application.get_env(:jido_studio, :persistence)
    old_index_enabled = Application.get_env(:jido_studio, :incident_index_enabled)

    Application.put_env(:jido_studio, :persistence,
      adapter: JidoStudio.Persistence.ETS,
      opts: [event_retention: 2_000]
    )

    Application.put_env(:jido_studio, :incident_index_enabled, true)

    clear_table(:jido_studio_persistence_docs)
    clear_table(:jido_studio_persistence_events)
    clear_table(:jido_studio_persistence_event_seq)

    ensure_started(JidoStudio.Persistence.ETS, fn -> JidoStudio.Persistence.ETS.start_link([]) end)

    ensure_started(JidoStudio.Ingestor, fn -> JidoStudio.Ingestor.start_link([]) end)

    on_exit(fn ->
      Application.put_env(:jido_studio, :persistence, old_persistence)
      Application.put_env(:jido_studio, :incident_index_enabled, old_index_enabled)
    end)

    :ok
  end

  test "signals/actions/workflows queries return diagnostics from ingested events" do
    t0 = System.system_time(:millisecond)
    native_45ms = System.convert_time_unit(45, :millisecond, :native)

    Ingestor.ingest_event(%{
      type: :start,
      status: "running",
      event_name: "jido.signals.dispatch.start",
      signal_type: "agent_alert",
      trace_id: "trace-signal-1",
      agent_id: "agent-1",
      request_id: "req-1",
      timestamp_ms: t0,
      scope: %{project_id: "project-1", user_id: "user-1"},
      metadata: %{signal_type: "agent_alert"}
    })

    Ingestor.ingest_event(%{
      type: :start,
      event_name: "jido.ai.tool.execute.start",
      entity_type: "tool",
      entity_id: "weather.lookup",
      action: "weather.lookup",
      trace_id: "trace-action-1",
      call_id: "call-1",
      request_id: "req-1",
      workflow_id: "wf-1",
      agent_id: "agent-1",
      agent_module: "Demo.Agent",
      timestamp_ms: t0 + 5,
      scope: %{project_id: "project-1", user_id: "user-1"},
      metadata: %{tool_name: "weather.lookup"}
    })

    Ingestor.ingest_event(%{
      type: :stop,
      status: "ok",
      event_name: "jido.ai.tool.execute.stop",
      entity_type: "tool",
      entity_id: "weather.lookup",
      action: "weather.lookup",
      trace_id: "trace-action-1",
      call_id: "call-1",
      request_id: "req-1",
      workflow_id: "wf-1",
      agent_id: "agent-1",
      agent_module: "Demo.Agent",
      timestamp_ms: t0 + 60,
      measurements: %{duration: native_45ms},
      scope: %{project_id: "project-1", user_id: "user-1"},
      metadata: %{tool_name: "weather.lookup"}
    })

    Ingestor.ingest_event(%{
      type: :start,
      event_name: "jido.workflow.start",
      workflow_id: "wf-1",
      request_id: "req-1",
      trace_id: "trace-workflow-1",
      agent_id: "agent-1",
      timestamp_ms: t0 + 2,
      scope: %{project_id: "project-1", user_id: "user-1"}
    })

    Ingestor.ingest_event(%{
      type: :stop,
      status: "ok",
      event_name: "jido.workflow.stop",
      workflow_id: "wf-1",
      request_id: "req-1",
      trace_id: "trace-workflow-1",
      agent_id: "agent-1",
      timestamp_ms: t0 + 70,
      scope: %{project_id: "project-1", user_id: "user-1"}
    })

    Process.sleep(80)

    signals = Signals.list_signals(filters: %{range: "all"}, limit: 50)
    assert Enum.any?(signals, &(&1.signal_type == "agent_alert"))

    actions = Actions.list_actions(filters: %{range: "all", action: "weather.lookup"}, limit: 20)
    assert actions != []

    action = hd(actions)
    assert action.execution_count >= 1
    assert action.agent_module == "Demo.Agent"

    executions = Actions.latest_executions(action.id, limit: 20)
    assert executions != []
    assert Enum.any?(executions, &(&1.trace_id == "trace-action-1"))

    runs = Workflows.list_runs(filters: %{range: "all", workflow_id: "wf-1"}, limit: 20)
    assert runs != []

    run = hd(runs)
    assert run.workflow_id == "wf-1"

    timeline = Workflows.run_timeline(run.id, limit: 20)
    assert length(timeline) >= 2

    incidents = Incidents.list_incidents(%{range: "all", request_id: "req-1"}, 10)
    assert incidents != []
    assert Enum.any?(incidents, &(&1.incident_id == "req:req-1"))
  end

  defp clear_table(table) do
    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end
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
end
