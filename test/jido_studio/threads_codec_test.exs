defmodule JidoStudio.ThreadsCodecTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Threads.Codec
  alias JidoStudio.Chat.Session

  test "message diff entries round-trip through thread journal" do
    state = Session.with_initial_thread("New Chat")
    {state, pending_id} = Session.append_user_turn(state, "How is weather in Boston?")

    state =
      state
      |> Session.update_pending_tool_events(pending_id, [%{name: "weather", status: :running}])
      |> Session.resolve_assistant_reply(pending_id, "Cold and sunny.")

    messages = Session.active_messages(state)
    {entries, hashes} = Codec.diff_messages(messages, %{})

    assert length(entries) == 2
    assert map_size(hashes) == 2

    thread =
      Jido.Thread.new(id: "thread_codec")
      |> Jido.Thread.append(entries)

    decoded = Codec.messages_from_thread(thread)

    assert Enum.map(decoded, & &1[:role]) == [:user, :assistant]
    assert Enum.at(decoded, 1)[:content] == "Cold and sunny."
    assert map_size(Codec.message_hashes_from_thread(thread)) == 2
  end

  test "workspace checkpoint encode/decode retains thread metadata and context" do
    chat_state = Session.with_initial_thread("Thread One")
    thread = hd(chat_state.threads)

    checkpoint =
      Codec.encode_workspace_checkpoint(chat_state,
        draft_message: "draft",
        thread_records: %{
          thread.id => %{journal_rev: 4, message_hashes: %{"msg_1" => "abc"}}
        },
        thread_contexts: %{thread.id => %{iteration: 2, model: "anthropic:claude-haiku-4-5"}},
        instance_binding: %{agent_slug: "weather", instance_id: "inst-1"}
      )

    decoded = Codec.decode_workspace_checkpoint(checkpoint)

    assert decoded.active_thread_id == thread.id
    assert decoded.draft_message == "draft"
    assert decoded.instance_binding[:agent_slug] == "weather"

    [decoded_thread] = decoded.threads
    assert decoded_thread.journal_rev == 4
    assert decoded_thread.message_hashes == %{"msg_1" => "abc"}
  end
end
