defmodule JidoStudio.ChatSessionTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Chat.Session

  test "new thread creation and selection" do
    state = Session.empty() |> Session.add_thread("First")
    first_thread_id = state.active_thread_id

    state = Session.add_thread(state, "Second")

    assert length(state.threads) == 2
    assert Session.active_thread_name(state) == "Second"

    selected = Session.select_thread(state, first_thread_id)
    assert selected.active_thread_id == first_thread_id
    assert Session.active_thread_name(selected) == "First"
  end

  test "append_user_turn adds user and pending assistant messages" do
    state = Session.with_initial_thread()
    {state, pending_id} = Session.append_user_turn(state, "Hello weather bot")
    messages = Session.active_messages(state)

    assert length(messages) == 2
    assert Enum.at(messages, 0).role == :user
    assert Enum.at(messages, 0).content == "Hello weather bot"
    assert Enum.at(messages, 1).id == pending_id
    assert Enum.at(messages, 1).role == :assistant
    assert Enum.at(messages, 1).state == :pending
  end

  test "resolve_assistant_reply replaces pending message content" do
    state = Session.with_initial_thread()
    {state, pending_id} = Session.append_user_turn(state, "How is Seattle today?")

    resolved = Session.resolve_assistant_reply(state, pending_id, "Rainy with mild winds")
    messages = Session.active_messages(resolved)
    assistant = Enum.at(messages, 1)

    assert assistant.content == "Rainy with mild winds"
    assert assistant.state == :complete
  end

  test "resolve_assistant_error preserves order and marks the assistant message as error" do
    state = Session.with_initial_thread()
    {state, pending_id} = Session.append_user_turn(state, "What about tomorrow?")

    resolved = Session.resolve_assistant_error(state, pending_id, "Request timed out")
    messages = Session.active_messages(resolved)

    assert Enum.map(messages, & &1.role) == [:user, :assistant]
    assert Enum.at(messages, 0).content == "What about tomorrow?"
    assert Enum.at(messages, 1).content == "Request timed out"
    assert Enum.at(messages, 1).state == :error
  end

  test "update_pending_content updates only pending assistant message" do
    state = Session.with_initial_thread()
    {state, pending_id} = Session.append_user_turn(state, "How is Fargo?")

    updated = Session.update_pending_content(state, pending_id, "Streaming weather details...")
    messages = Session.active_messages(updated)

    assert Enum.at(messages, 0).content == "How is Fargo?"
    assert Enum.at(messages, 1).state == :pending
    assert Enum.at(messages, 1).content == "Streaming weather details..."

    resolved = Session.resolve_assistant_reply(updated, pending_id, "Final weather answer")

    unchanged =
      Session.update_pending_content(resolved, pending_id, "Should not overwrite complete reply")

    assert Enum.at(Session.active_messages(unchanged), 1).content == "Final weather answer"
  end

  test "update_pending_tool_events attaches tool blocks only to pending message" do
    state = Session.with_initial_thread()
    {state, pending_id} = Session.append_user_turn(state, "Weather in Boston")

    tool_events = [
      %{
        call_id: "tool-call-1",
        name: "weather_geocode",
        arguments: %{"location" => "Boston, MA"},
        result: nil,
        status: :running
      }
    ]

    updated = Session.update_pending_tool_events(state, pending_id, tool_events)
    [user_message, pending_message] = Session.active_messages(updated)

    assert user_message.tool_events == []
    assert pending_message.tool_events == tool_events

    resolved = Session.resolve_assistant_reply(updated, pending_id, "It's cold and sunny.")
    unchanged = Session.update_pending_tool_events(resolved, pending_id, [])
    [_user_after, resolved_message] = Session.active_messages(unchanged)

    assert resolved_message.state == :complete
    assert resolved_message.tool_events == tool_events
  end
end
