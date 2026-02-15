defmodule JidoStudio.ThreadsManagerTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Chat.Session
  alias JidoStudio.Threads.Codec
  alias JidoStudio.Threads.Manager
  alias JidoStudio.Threads.Storage
  alias Jido.Thread.Entry

  setup do
    table = String.to_atom("jido_studio_manager_test_#{System.unique_integer([:positive])}")

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

  test "load returns fresh workspace when no persisted state" do
    assert {:ok, payload} = Manager.load_workspace("weather", "instance-a")
    assert payload.source == :fresh
    assert payload.chat_state.threads == []
  end

  test "save and reload workspace keeps messages and context" do
    state = Session.with_initial_thread("New Chat")
    {state, pending_id} = Session.append_user_turn(state, "hello")
    state = Session.resolve_assistant_reply(state, pending_id, "world")

    context = %{state.active_thread_id => %{iteration: 2, model: "anthropic:claude-haiku-4-5"}}

    assert :ok =
             Manager.save_workspace("weather", "instance-b", state,
               draft_message: "draft",
               thread_contexts: context,
               instance_binding: %{agent_slug: "weather"}
             )

    assert {:ok, payload} = Manager.load_workspace("weather", "instance-b")
    assert payload.source == :persisted
    assert payload.draft_message == "draft"
    assert payload.thread_contexts[state.active_thread_id][:iteration] == 2

    messages = Map.get(payload.chat_state.messages_by_thread, state.active_thread_id)
    assert Enum.map(messages, & &1[:role]) == [:user, :assistant]
    assert Enum.at(messages, 1)[:content] == "world"
  end

  test "save retries on journal conflict and succeeds" do
    state = Session.with_initial_thread("New Chat")
    {state, pending_id} = Session.append_user_turn(state, "first")
    state = Session.resolve_assistant_reply(state, pending_id, "done")

    assert :ok = Manager.save_workspace("weather", "instance-c", state)

    thread_id = state.active_thread_id
    thread_key = Storage.thread_key("weather", "instance-c", thread_id)

    assert {:ok, checkpoint} = Storage.get_workspace_checkpoint("weather", "instance-c")
    decoded = Codec.decode_workspace_checkpoint(checkpoint)
    rev = decoded.threads |> hd() |> Map.fetch!(:journal_rev)

    external_entry = %Entry{
      id: nil,
      seq: 0,
      at: System.system_time(:millisecond),
      kind: :message,
      payload: %{
        event: :upsert_message,
        message_id: "external_msg",
        message: %{
          id: "external_msg",
          role: :assistant,
          content: "external",
          state: :complete,
          tool_events: [],
          at: System.system_time(:millisecond)
        }
      },
      refs: %{}
    }

    assert {:ok, _thread} = Storage.append_thread(thread_key, [external_entry], expected_rev: rev)

    {updated_state, updated_pending_id} = Session.append_user_turn(state, "second")

    updated_state =
      Session.resolve_assistant_reply(updated_state, updated_pending_id, "second done")

    assert :ok = Manager.save_workspace("weather", "instance-c", updated_state)

    assert {:ok, payload} = Manager.load_workspace("weather", "instance-c")
    messages = Map.get(payload.chat_state.messages_by_thread, thread_id)

    assert Enum.any?(messages, &(&1[:id] == "external_msg"))
    assert Enum.any?(messages, &(&1[:content] == "second done"))
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
