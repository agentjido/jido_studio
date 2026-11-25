defmodule JidoStudio.ThreadsExplorerTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Chat.Session
  alias JidoStudio.Threads
  alias JidoStudio.Threads.Manager

  setup do
    table = String.to_atom("jido_studio_threads_explorer_#{System.unique_integer([:positive])}")

    old_storage = Application.get_env(:jido_studio, :thread_storage)
    old_mode = Application.get_env(:jido_studio, :thread_storage_mode)
    old_enabled = Application.get_env(:jido_studio, :thread_persistence)

    Application.put_env(:jido_studio, :thread_storage, {Jido.Storage.ETS, table: table})
    Application.put_env(:jido_studio, :thread_storage_mode, :studio)
    Application.put_env(:jido_studio, :thread_persistence, true)

    ensure_manager_started()

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

  test "list_threads and get_thread expose persisted entries" do
    state = Session.with_initial_thread("Weather Debug")
    {state, pending_id} = Session.append_user_turn(state, "hello")
    state = Session.resolve_assistant_reply(state, pending_id, "world")

    assert :ok = Manager.save_workspace("weather", "inst-thread-1", state)

    threads = Threads.list_threads()

    assert [%{thread_id: thread_id, agent_slug: "weather", agent_id: "inst-thread-1"} | _] =
             Enum.filter(threads, &(&1.agent_id == "inst-thread-1"))

    assert {:ok, payload} = Threads.get_thread("weather", "inst-thread-1", thread_id)

    assert payload.thread.thread_id == thread_id
    assert payload.thread.entry_count >= 2
    assert length(payload.entries) >= 2
    assert Enum.any?(payload.entries, &is_binary(&1.payload_preview))
  end

  defp ensure_manager_started do
    case Process.whereis(Manager) do
      nil ->
        {:ok, _pid} = Manager.start_link([])

      _pid ->
        :ok
    end
  end
end
