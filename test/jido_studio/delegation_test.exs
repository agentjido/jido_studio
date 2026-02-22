defmodule JidoStudio.DelegationTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Delegation
  alias JidoStudio.Ingestor

  setup do
    old_persistence = Application.get_env(:jido_studio, :persistence)

    Application.put_env(:jido_studio, :persistence,
      adapter: JidoStudio.Persistence.ETS,
      opts: [event_retention: 200]
    )

    clear_table(:jido_studio_persistence_docs)
    clear_table(:jido_studio_persistence_events)
    clear_table(:jido_studio_persistence_event_seq)

    ensure_started(JidoStudio.Persistence.ETS, fn -> JidoStudio.Persistence.ETS.start_link([]) end)

    ensure_started(JidoStudio.Ingestor, fn -> JidoStudio.Ingestor.start_link([]) end)

    on_exit(fn ->
      Application.put_env(:jido_studio, :persistence, old_persistence)
    end)

    :ok
  end

  test "builds subagent and task records from ingested events" do
    t0 = System.system_time(:millisecond)

    Ingestor.ingest_event(%{
      trace_id: "trace-delegation-1",
      span_id: "root",
      parent_span_id: nil,
      agent_id: "child-agent-1",
      parent_agent_id: "parent-agent-1",
      task_id: "task-1",
      task_status: "running",
      type: :start,
      event_name: "jido.agent.cmd.start",
      timestamp_ms: t0,
      metadata: %{scope: %{project_id: "p1"}}
    })

    Ingestor.ingest_event(%{
      trace_id: "trace-delegation-1",
      span_id: "root",
      parent_span_id: nil,
      agent_id: "child-agent-1",
      parent_agent_id: "parent-agent-1",
      task_id: "task-1",
      task_status: "ok",
      type: :stop,
      event_name: "jido.agent.cmd.stop",
      timestamp_ms: t0 + 20,
      metadata: %{scope: %{project_id: "p1"}}
    })

    Process.sleep(30)

    subagents = Delegation.list_subagents("parent-agent-1")
    assert length(subagents) == 1
    assert hd(subagents).agent_id == "child-agent-1"

    tasks = Delegation.list_tasks("child-agent-1")
    assert length(tasks) == 1
    assert hd(tasks).task_status == "ok"

    graph = Delegation.delegation_graph("trace-delegation-1")
    assert Enum.any?(graph.nodes, &(&1.id == "parent-agent-1"))
    assert Enum.any?(graph.nodes, &(&1.id == "child-agent-1"))
    assert Enum.any?(graph.edges, &(&1.from == "parent-agent-1" and &1.to == "child-agent-1"))
  end

  test "returns subagent detail and subagent-scoped events" do
    t0 = System.system_time(:millisecond)

    Ingestor.ingest_event(%{
      trace_id: "trace-delegation-2",
      span_id: "span-1",
      parent_span_id: nil,
      agent_id: "child-agent-2",
      parent_agent_id: "parent-agent-2",
      type: :start,
      event_name: "jido.agent.cmd.start",
      timestamp_ms: t0,
      metadata: %{subagent_id: "child-agent-2"}
    })

    Ingestor.ingest_event(%{
      trace_id: "trace-delegation-2",
      span_id: "span-2",
      parent_span_id: "span-1",
      agent_id: "another-agent",
      parent_agent_id: "parent-agent-2",
      type: :stop,
      event_name: "jido.agent.cmd.stop",
      timestamp_ms: t0 + 15,
      metadata: %{subagent_id: "child-agent-2"}
    })

    Process.sleep(30)

    assert %{} = Delegation.get_subagent("parent-agent-2", "child-agent-2")

    events = Delegation.list_subagent_events("trace-delegation-2", "child-agent-2")
    assert length(events) == 2
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
