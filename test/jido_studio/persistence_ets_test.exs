defmodule JidoStudio.PersistenceETSTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Persistence

  setup do
    old_persistence = Application.get_env(:jido_studio, :persistence)

    Application.put_env(:jido_studio, :persistence,
      adapter: JidoStudio.Persistence.ETS,
      opts: [event_retention: 50]
    )

    if pid = Process.whereis(JidoStudio.Persistence.ETS) do
      GenServer.stop(pid)
    end

    clear_table(:jido_studio_persistence_docs)
    clear_table(:jido_studio_persistence_events)
    clear_table(:jido_studio_persistence_event_seq)

    on_exit(fn ->
      Application.put_env(:jido_studio, :persistence, old_persistence)
    end)

    :ok
  end

  test "put/get/list/delete doc lifecycle" do
    assert :ok =
             Persistence.put_doc("traces", "trace-1", %{status: "running", agent_id: "agent-1"})

    assert :ok = Persistence.put_doc("traces", "trace-2", %{status: "ok", agent_id: "agent-2"})

    assert {:ok, doc} = Persistence.get_doc("traces", "trace-1")
    assert doc.id == "trace-1"
    assert doc.status == "running"

    docs = Persistence.list_docs("traces", order: :asc, sort_by: :id, limit: 10)
    assert Enum.map(docs, & &1.id) |> Enum.sort() == ["trace-1", "trace-2"]

    assert :ok = Persistence.delete_doc("traces", "trace-2")
    assert :not_found = Persistence.get_doc("traces", "trace-2")
  end

  test "append_event/read_events keeps stream ordering" do
    assert {:ok, %{seq: 1}} = Persistence.append_event("trace:trace-1", %{type: :start, step: 1})
    assert {:ok, %{seq: 2}} = Persistence.append_event("trace:trace-1", %{type: :stop, step: 2})
    assert {:ok, %{seq: 1}} = Persistence.append_event("trace:trace-2", %{type: :start, step: 1})

    events_asc = Persistence.read_events("trace:trace-1", order: :asc, limit: 10)
    assert Enum.map(events_asc, & &1.seq) == [1, 2]

    events_desc = Persistence.read_events("trace:trace-1", order: :desc, limit: 10)
    assert Enum.map(events_desc, & &1.seq) == [2, 1]

    assert length(Persistence.read_events("trace:trace-1", after_seq: 1)) == 1
    assert length(Persistence.read_events("trace:trace-1", before_seq: 2)) == 1
  end

  defp clear_table(table) do
    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end
  end
end
