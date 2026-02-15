defmodule JidoStudio.ThreadsStorageTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Threads.Storage
  alias Jido.Thread.Entry

  setup do
    table = String.to_atom("jido_studio_storage_test_#{System.unique_integer([:positive])}")

    old_storage = Application.get_env(:jido_studio, :thread_storage)
    old_mode = Application.get_env(:jido_studio, :thread_storage_mode)
    old_enabled = Application.get_env(:jido_studio, :thread_persistence)

    Application.put_env(:jido_studio, :thread_storage, {Jido.Storage.ETS, table: table})
    Application.put_env(:jido_studio, :thread_storage_mode, :studio)
    Application.put_env(:jido_studio, :thread_persistence, true)

    on_exit(fn ->
      Application.put_env(:jido_studio, :thread_storage, old_storage)
      Application.put_env(:jido_studio, :thread_storage_mode, old_mode)
      Application.put_env(:jido_studio, :thread_persistence, old_enabled)

      for suffix <- [:checkpoints, :threads, :thread_meta] do
        table_name = String.to_atom("#{table}_#{suffix}")

        if :ets.whereis(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end
    end)

    {:ok, table: table}
  end

  test "workspace checkpoint write/read", %{table: _table} do
    checkpoint = %{foo: "bar", updated_at: System.system_time(:millisecond)}

    assert :ok = Storage.put_workspace_checkpoint("weather", "inst-1", checkpoint)
    assert {:ok, loaded} = Storage.get_workspace_checkpoint("weather", "inst-1")
    assert loaded[:foo] == "bar"
  end

  test "thread append/load keeps order and detects conflicts", %{table: _table} do
    thread_key = Storage.thread_key("weather", "inst-1", "thread-1")

    entry_1 = %Entry{
      id: nil,
      seq: 0,
      at: 0,
      kind: :message,
      payload: %{
        event: :upsert_message,
        message_id: "m1",
        message: %{id: "m1", role: :user, content: "hi", state: :complete, tool_events: [], at: 1}
      },
      refs: %{}
    }

    entry_2 = %Entry{
      id: nil,
      seq: 0,
      at: 0,
      kind: :message,
      payload: %{
        event: :upsert_message,
        message_id: "m2",
        message: %{
          id: "m2",
          role: :assistant,
          content: "hello",
          state: :complete,
          tool_events: [],
          at: 2
        }
      },
      refs: %{}
    }

    assert {:ok, thread} = Storage.append_thread(thread_key, [entry_1], expected_rev: 0)
    assert thread.rev == 1

    assert {:error, :conflict} = Storage.append_thread(thread_key, [entry_2], expected_rev: 0)
    assert {:ok, updated} = Storage.append_thread(thread_key, [entry_2], expected_rev: 1)
    assert updated.rev == 2

    assert {:ok, loaded} = Storage.load_thread(thread_key)
    assert Enum.map(loaded.entries, & &1.payload[:message_id]) == ["m1", "m2"]
  end
end
