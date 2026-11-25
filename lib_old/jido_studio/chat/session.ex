defmodule JidoStudio.Chat.Session do
  @moduledoc false

  @default_thread_title "New Chat"
  @thinking_placeholder "Thinking..."

  @type message_state :: :complete | :pending | :error

  @type message :: %{
          id: String.t(),
          role: :user | :assistant | :system,
          content: String.t(),
          tool_events: [map()],
          state: message_state(),
          at: integer()
        }

  @type thread :: %{
          id: String.t(),
          title: String.t(),
          message_count: non_neg_integer(),
          updated_at: integer()
        }

  @type t :: %{
          threads: [thread()],
          active_thread_id: String.t() | nil,
          messages_by_thread: %{optional(String.t()) => [message()]}
        }

  @spec empty() :: t()
  def empty do
    %{threads: [], active_thread_id: nil, messages_by_thread: %{}}
  end

  @spec with_initial_thread(String.t()) :: t()
  def with_initial_thread(title \\ @default_thread_title) when is_binary(title) do
    empty()
    |> add_thread(title)
  end

  @spec add_thread(t(), String.t()) :: t()
  def add_thread(state, title \\ @default_thread_title) when is_binary(title) do
    state = normalize_state(state)
    thread = new_thread(title)

    %{
      state
      | threads: [thread | state.threads],
        active_thread_id: thread.id,
        messages_by_thread: Map.put(state.messages_by_thread, thread.id, [])
    }
  end

  @spec select_thread(t(), String.t() | nil) :: t()
  def select_thread(state, thread_id) when is_binary(thread_id) do
    state = normalize_state(state)

    if Map.has_key?(state.messages_by_thread, thread_id) do
      %{state | active_thread_id: thread_id}
    else
      state
    end
  end

  def select_thread(state, _thread_id), do: normalize_state(state)

  @spec append_user_turn(t(), String.t(), keyword()) :: {t(), String.t()}
  def append_user_turn(state, message, opts \\ []) when is_binary(message) do
    state = ensure_active_thread(normalize_state(state))
    thread_id = state.active_thread_id
    current_messages = Map.get(state.messages_by_thread, thread_id, [])

    pending_content = Keyword.get(opts, :pending_content, @thinking_placeholder)

    user_message = new_message(:user, message, :complete)
    pending_message = new_message(:assistant, pending_content, :pending)
    messages = current_messages ++ [user_message, pending_message]

    updated_state =
      state
      |> put_messages(thread_id, messages)
      |> touch_thread(thread_id, message, length(messages))

    {updated_state, pending_message.id}
  end

  @spec resolve_assistant_reply(t(), String.t(), String.t()) :: t()
  def resolve_assistant_reply(state, message_id, content)
      when is_binary(message_id) and is_binary(content) do
    resolve_message(state, message_id, fn msg ->
      %{msg | role: :assistant, state: :complete, content: String.trim(content)}
    end)
  end

  @spec resolve_assistant_error(t(), String.t(), String.t()) :: t()
  def resolve_assistant_error(state, message_id, content)
      when is_binary(message_id) and is_binary(content) do
    resolve_message(state, message_id, fn msg ->
      %{msg | role: :assistant, state: :error, content: String.trim(content)}
    end)
  end

  @spec update_pending_content(t(), String.t(), String.t()) :: t()
  def update_pending_content(state, message_id, content)
      when is_binary(message_id) and is_binary(content) do
    resolve_message(state, message_id, fn msg ->
      if msg.state == :pending do
        %{msg | content: content}
      else
        msg
      end
    end)
  end

  @spec update_pending_tool_events(t(), String.t(), [map()]) :: t()
  def update_pending_tool_events(state, message_id, tool_events)
      when is_binary(message_id) and is_list(tool_events) do
    resolve_message(state, message_id, fn msg ->
      if msg.state == :pending do
        %{msg | tool_events: tool_events}
      else
        msg
      end
    end)
  end

  @spec active_messages(t()) :: [message()]
  def active_messages(state) do
    state = normalize_state(state)
    Map.get(state.messages_by_thread, state.active_thread_id, [])
  end

  @spec active_thread_name(t()) :: String.t()
  def active_thread_name(state) do
    state = normalize_state(state)

    case Enum.find(state.threads, &(&1.id == state.active_thread_id)) do
      nil -> "Chat"
      thread -> thread.title
    end
  end

  defp normalize_state(%{
         threads: threads,
         active_thread_id: active_thread_id,
         messages_by_thread: map
       })
       when is_list(threads) and is_map(map) do
    %{threads: threads, active_thread_id: active_thread_id, messages_by_thread: map}
  end

  defp normalize_state(_), do: empty()

  defp ensure_active_thread(%{active_thread_id: id, messages_by_thread: map} = state)
       when is_binary(id) and is_map_key(map, id) do
    state
  end

  defp ensure_active_thread(state), do: add_thread(state, @default_thread_title)

  defp resolve_message(state, message_id, updater) do
    state = normalize_state(state)

    {messages_by_thread, found?} =
      Enum.reduce(state.messages_by_thread, {%{}, false}, fn {thread_id, messages},
                                                             {acc, found?} ->
        {updated_messages, updated?} = update_message(messages, message_id, updater)
        {Map.put(acc, thread_id, updated_messages), found? or updated?}
      end)

    if found? do
      %{state | messages_by_thread: messages_by_thread}
    else
      state
    end
  end

  defp update_message(messages, message_id, updater) do
    Enum.reduce(messages, {[], false}, fn message, {acc, found?} ->
      if message.id == message_id do
        {[updater.(message) | acc], true}
      else
        {[message | acc], found?}
      end
    end)
    |> then(fn {reversed, found?} -> {Enum.reverse(reversed), found?} end)
  end

  defp put_messages(state, thread_id, messages) do
    %{state | messages_by_thread: Map.put(state.messages_by_thread, thread_id, messages)}
  end

  defp new_thread(title) do
    now = System.system_time(:millisecond)

    %{
      id: "thread_#{System.unique_integer([:positive, :monotonic])}",
      title: title,
      message_count: 0,
      updated_at: now
    }
  end

  defp new_message(role, content, state) do
    %{
      id: "msg_#{System.unique_integer([:positive, :monotonic])}",
      role: role,
      content: content,
      tool_events: [],
      state: state,
      at: System.system_time(:millisecond)
    }
  end

  defp touch_thread(state, thread_id, message, message_count) do
    now = System.system_time(:millisecond)

    threads =
      state.threads
      |> Enum.map(fn thread ->
        if thread.id == thread_id do
          %{
            thread
            | title: maybe_update_title(thread.title, message),
              message_count: message_count,
              updated_at: now
          }
        else
          thread
        end
      end)
      |> Enum.sort_by(& &1.updated_at, :desc)

    %{state | threads: threads}
  end

  defp maybe_update_title("New Chat", message), do: summarize_message(message)
  defp maybe_update_title(title, _message), do: title

  defp summarize_message(message) do
    message
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 36)
  end
end
