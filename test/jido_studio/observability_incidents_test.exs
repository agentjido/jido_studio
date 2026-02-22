defmodule JidoStudio.ObservabilityIncidentsTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Observability.Incidents
  alias JidoStudio.Persistence

  setup do
    old_persistence = Application.get_env(:jido_studio, :persistence)
    old_index_enabled = Application.get_env(:jido_studio, :incident_index_enabled)

    Application.put_env(:jido_studio, :persistence,
      adapter: JidoStudio.Persistence.ETS,
      opts: [event_retention: 500]
    )

    Application.put_env(:jido_studio, :incident_index_enabled, true)

    clear_table(:jido_studio_persistence_docs)
    clear_table(:jido_studio_persistence_events)
    clear_table(:jido_studio_persistence_event_seq)

    ensure_started(JidoStudio.Persistence.ETS, fn -> JidoStudio.Persistence.ETS.start_link([]) end)

    on_exit(fn ->
      Application.put_env(:jido_studio, :persistence, old_persistence)
      Application.put_env(:jido_studio, :incident_index_enabled, old_index_enabled)
    end)

    :ok
  end

  test "ingest_event builds incident docs and timeline query" do
    t0 = System.system_time(:millisecond)

    start_event = %{
      type: :start,
      status: "running",
      trace_id: "trace-incident-1",
      agent_id: "agent-1",
      action: "tool.lookup",
      request_id: "req-incident-1",
      event_name: "jido.workflow.start",
      timestamp_ms: t0,
      scope: %{project_id: "project-1", user_id: "user-1"}
    }

    error_event = %{
      type: :exception,
      status: "error",
      trace_id: "trace-incident-1",
      agent_id: "agent-1",
      action: "tool.lookup",
      request_id: "req-incident-1",
      event_name: "jido.workflow.exception",
      timestamp_ms: t0 + 12,
      scope: %{project_id: "project-1", user_id: "user-1"}
    }

    assert :ok = Incidents.ingest_event(start_event)
    assert :ok = Incidents.ingest_event(error_event)

    [incident] = Incidents.list_incidents(%{range: "all", agent_id: "agent-1"}, 10)
    assert incident.incident_id == "req:req-incident-1"
    assert incident.event_count == 2
    assert incident.error_count == 1
    assert incident.status == "error"
    assert "trace-incident-1" in (incident.trace_ids || [])

    timeline = Incidents.incident_timeline(incident.incident_id, %{range: "all", limit: 10})
    assert length(timeline) == 2
    assert Enum.any?(timeline, &(&1.status == "error"))

    entities = Incidents.incident_entities(incident.incident_id)
    assert Enum.any?(entities, &(&1.kind == "action" and &1.id == "tool.lookup"))

    assert :ok =
             Persistence.put_doc("traces", "trace-incident-1", %{
               trace_id: "trace-incident-1",
               status: "error",
               last_event_at: t0 + 12
             })

    related = Incidents.related_traces(incident.incident_id)
    assert Enum.any?(related, &(&1.trace_id == "trace-incident-1"))
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
