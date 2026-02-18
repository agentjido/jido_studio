defmodule JidoStudio.EvalsTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Evals
  alias JidoStudio.Ingestor

  setup do
    old_persistence = Application.get_env(:jido_studio, :persistence)
    old_evals = Application.get_env(:jido_studio, :evals)

    Application.put_env(:jido_studio, :persistence,
      adapter: JidoStudio.Persistence.ETS,
      opts: [event_retention: 200]
    )

    Application.put_env(:jido_studio, :evals,
      enabled: true,
      rule_sets: [:default]
    )

    clear_table(:jido_studio_persistence_docs)
    clear_table(:jido_studio_persistence_events)
    clear_table(:jido_studio_persistence_event_seq)

    ensure_started(JidoStudio.Persistence.ETS, fn -> JidoStudio.Persistence.ETS.start_link([]) end)

    ensure_started(JidoStudio.Ingestor, fn -> JidoStudio.Ingestor.start_link([]) end)

    on_exit(fn ->
      Application.put_env(:jido_studio, :persistence, old_persistence)
      Application.put_env(:jido_studio, :evals, old_evals)
    end)

    :ok
  end

  test "runs eval and persists history for a trace" do
    t0 = System.system_time(:millisecond)

    Ingestor.ingest_event(%{
      trace_id: "trace-eval-1",
      span_id: "root",
      type: :start,
      event_name: "jido.agent.cmd.start",
      agent_id: "eval-agent-1",
      timestamp_ms: t0,
      metadata: %{}
    })

    Ingestor.ingest_event(%{
      trace_id: "trace-eval-1",
      span_id: "root",
      type: :stop,
      event_name: "jido.agent.cmd.stop",
      agent_id: "eval-agent-1",
      timestamp_ms: t0 + 100,
      metadata: %{}
    })

    Process.sleep(30)

    assert {:ok, run} = Evals.run_trace("trace-eval-1")
    assert run.trace_id == "trace-eval-1"
    assert is_integer(run.score)
    assert run.status in [:pass, :fail]

    runs = Evals.list_runs("trace-eval-1", limit: 5)
    assert length(runs) == 1
    assert hd(runs).id == run.id
  end

  test "respects evals disabled config" do
    Application.put_env(:jido_studio, :evals, enabled: false, rule_sets: [:default])
    assert {:error, :disabled} = Evals.run_trace("trace-any")
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
