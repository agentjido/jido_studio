defmodule JidoStudio.Threads.Codec do
  @moduledoc false

  alias JidoStudio.Chat.Session
  alias JidoStudio.Threads.Storage
  alias Jido.Thread
  alias Jido.Thread.Entry

  @schema_version 1

  @type thread_record :: %{
          id: String.t(),
          title: String.t(),
          message_count: non_neg_integer(),
          updated_at: integer(),
          journal_rev: non_neg_integer(),
          message_hashes: %{optional(String.t()) => String.t()}
        }

  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  @spec encode_workspace_checkpoint(Session.t(), keyword()) :: map()
  def encode_workspace_checkpoint(chat_state, opts \\ []) do
    state = normalize_chat_state(chat_state)
    thread_records = Keyword.get(opts, :thread_records, %{})
    draft_message = Keyword.get(opts, :draft_message, "")
    thread_contexts = Keyword.get(opts, :thread_contexts, %{})
    instance_binding = Keyword.get(opts, :instance_binding, %{})
    updated_at = Keyword.get(opts, :updated_at, now_ms())

    %{
      schema_version: @schema_version,
      active_thread_id: normalize_optional_binary(state.active_thread_id),
      draft_message: normalize_optional_binary(draft_message),
      updated_at: updated_at,
      instance_binding: normalize_map(instance_binding),
      thread_contexts: normalize_map(thread_contexts),
      threads:
        Enum.map(state.threads, fn thread ->
          thread_record = Map.get(thread_records, thread.id, %{})

          %{
            id: thread.id,
            title: thread.title,
            message_count: normalize_non_neg_integer(thread.message_count),
            updated_at: normalize_integer(thread.updated_at, updated_at),
            journal_rev: normalize_non_neg_integer(thread_record[:journal_rev]),
            message_hashes: normalize_hashes(thread_record[:message_hashes] || %{})
          }
        end)
    }
  end

  @spec decode_workspace_checkpoint(map()) :: map()
  def decode_workspace_checkpoint(%{} = checkpoint) do
    %{
      schema_version:
        normalize_non_neg_integer(
          Map.get(checkpoint, :schema_version) || Map.get(checkpoint, "schema_version")
        ),
      active_thread_id:
        normalize_optional_binary(
          Map.get(checkpoint, :active_thread_id) || Map.get(checkpoint, "active_thread_id")
        ),
      draft_message:
        normalize_optional_binary(
          Map.get(checkpoint, :draft_message) || Map.get(checkpoint, "draft_message")
        ),
      updated_at:
        normalize_integer(
          Map.get(checkpoint, :updated_at) || Map.get(checkpoint, "updated_at"),
          now_ms()
        ),
      instance_binding:
        normalize_map(
          Map.get(checkpoint, :instance_binding) || Map.get(checkpoint, "instance_binding") || %{}
        ),
      thread_contexts:
        normalize_map(
          Map.get(checkpoint, :thread_contexts) || Map.get(checkpoint, "thread_contexts") || %{}
        ),
      threads:
        normalize_thread_records(
          Map.get(checkpoint, :threads) || Map.get(checkpoint, "threads") || []
        )
    }
  end

  def decode_workspace_checkpoint(_), do: decode_workspace_checkpoint(%{})

  @spec thread_records(map()) :: %{optional(String.t()) => thread_record()}
  def thread_records(decoded_checkpoint) when is_map(decoded_checkpoint) do
    decoded_checkpoint
    |> Map.get(:threads, [])
    |> Enum.reduce(%{}, fn thread, acc -> Map.put(acc, thread.id, thread) end)
  end

  @spec diff_messages([map()], %{optional(String.t()) => String.t()}) ::
          {[Entry.t()], %{optional(String.t()) => String.t()}}
  def diff_messages(messages, known_hashes) when is_list(messages) and is_map(known_hashes) do
    Enum.reduce(messages, {[], %{}}, fn message, {entries, hashes} ->
      normalized = normalize_message(message)
      message_id = normalized.id
      hash = message_hash(normalized)

      hashes = Map.put(hashes, message_id, hash)

      if Map.get(known_hashes, message_id) != hash do
        payload = %{
          event: :upsert_message,
          message_id: message_id,
          message: normalized,
          hash: hash,
          persisted_at: now_ms()
        }

        entry = %Entry{id: nil, seq: 0, at: now_ms(), kind: :message, payload: payload, refs: %{}}
        {[entry | entries], hashes}
      else
        {entries, hashes}
      end
    end)
    |> then(fn {entries, hashes} -> {Enum.reverse(entries), hashes} end)
  end

  @spec messages_from_thread(Thread.t()) :: [map()]
  def messages_from_thread(%Thread{entries: entries}) when is_list(entries) do
    {order, by_id} =
      entries
      |> Enum.sort_by(& &1.seq)
      |> Enum.reduce({[], %{}}, fn entry, {order, by_id} ->
        case decode_message_entry(entry) do
          {:ok, message} ->
            if Map.has_key?(by_id, message.id) do
              {order, Map.put(by_id, message.id, message)}
            else
              {order ++ [message.id], Map.put(by_id, message.id, message)}
            end

          :skip ->
            {order, by_id}
        end
      end)

    Enum.map(order, fn id -> Map.get(by_id, id) end)
  end

  def messages_from_thread(_), do: []

  @spec message_hashes_from_thread(Thread.t()) :: %{optional(String.t()) => String.t()}
  def message_hashes_from_thread(thread) do
    thread
    |> messages_from_thread()
    |> Enum.reduce(%{}, fn message, acc ->
      normalized = normalize_message(message)
      Map.put(acc, normalized.id, message_hash(normalized))
    end)
  end

  @spec workspace_from_checkpoint(map(), %{optional(String.t()) => [map()]}) :: Session.t()
  def workspace_from_checkpoint(decoded_checkpoint, messages_by_thread)
      when is_map(decoded_checkpoint) and is_map(messages_by_thread) do
    threads = Map.get(decoded_checkpoint, :threads, [])

    active_thread_id =
      decoded_checkpoint
      |> Map.get(:active_thread_id)
      |> normalize_active_thread_id(messages_by_thread)

    %{
      threads: threads,
      active_thread_id: active_thread_id,
      messages_by_thread: messages_by_thread
    }
  end

  @spec empty_workspace_payload() :: map()
  def empty_workspace_payload do
    %{
      chat_state: Session.empty(),
      draft_message: "",
      thread_contexts: %{},
      source: :fresh,
      instance_binding: %{}
    }
  end

  @spec workspace_payload(map(), Session.t(), map()) :: map()
  def workspace_payload(decoded_checkpoint, chat_state, opts \\ %{}) do
    %{
      chat_state: chat_state,
      draft_message: normalize_optional_binary(Map.get(decoded_checkpoint, :draft_message) || ""),
      thread_contexts: normalize_map(Map.get(decoded_checkpoint, :thread_contexts) || %{}),
      source: :persisted,
      instance_binding:
        normalize_map(Map.get(decoded_checkpoint, :instance_binding) || %{})
        |> Map.merge(normalize_map(opts))
    }
  end

  defp decode_message_entry(%Entry{kind: :message, payload: payload}) when is_map(payload) do
    event = Map.get(payload, :event) || Map.get(payload, "event")

    case event do
      :upsert_message -> decode_upsert_message(payload)
      "upsert_message" -> decode_upsert_message(payload)
      _ -> :skip
    end
  end

  defp decode_message_entry(_), do: :skip

  defp decode_upsert_message(payload) do
    message = Map.get(payload, :message) || Map.get(payload, "message")

    if is_map(message) do
      {:ok, normalize_message(message)}
    else
      :skip
    end
  end

  defp normalize_chat_state(%{
         threads: threads,
         active_thread_id: active_thread_id,
         messages_by_thread: by_thread
       })
       when is_list(threads) and is_map(by_thread) do
    %{
      threads: normalize_thread_records(threads),
      active_thread_id: normalize_optional_binary(active_thread_id),
      messages_by_thread: by_thread
    }
  end

  defp normalize_chat_state(_), do: %{threads: [], active_thread_id: nil, messages_by_thread: %{}}

  defp normalize_thread_records(threads) when is_list(threads) do
    threads
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn thread ->
      %{
        id: normalize_optional_binary(Map.get(thread, :id) || Map.get(thread, "id") || ""),
        title:
          normalize_optional_binary(
            Map.get(thread, :title) || Map.get(thread, "title") || "New Chat"
          ),
        message_count:
          normalize_non_neg_integer(
            Map.get(thread, :message_count) || Map.get(thread, "message_count")
          ),
        updated_at:
          normalize_integer(
            Map.get(thread, :updated_at) || Map.get(thread, "updated_at"),
            now_ms()
          ),
        journal_rev:
          normalize_non_neg_integer(
            Map.get(thread, :journal_rev) || Map.get(thread, "journal_rev")
          ),
        message_hashes:
          normalize_hashes(
            Map.get(thread, :message_hashes) || Map.get(thread, "message_hashes") || %{}
          )
      }
    end)
    |> Enum.filter(&(is_binary(&1.id) and &1.id != ""))
    |> Enum.sort_by(& &1.updated_at, :desc)
  end

  defp normalize_thread_records(_), do: []

  defp normalize_active_thread_id(nil, messages_by_thread) do
    case Map.keys(messages_by_thread) do
      [first | _] -> first
      _ -> nil
    end
  end

  defp normalize_active_thread_id(active_thread_id, messages_by_thread)
       when is_binary(active_thread_id) do
    if Map.has_key?(messages_by_thread, active_thread_id) do
      active_thread_id
    else
      normalize_active_thread_id(nil, messages_by_thread)
    end
  end

  defp normalize_active_thread_id(_, messages_by_thread),
    do: normalize_active_thread_id(nil, messages_by_thread)

  defp normalize_message(message) when is_map(message) do
    %{
      id:
        normalize_optional_binary(
          Map.get(message, :id) || Map.get(message, "id") || generated_message_id()
        ),
      role: normalize_role(Map.get(message, :role) || Map.get(message, "role")),
      content:
        normalize_optional_binary(Map.get(message, :content) || Map.get(message, "content")),
      tool_events:
        normalize_tool_events(
          Map.get(message, :tool_events) || Map.get(message, "tool_events") || []
        ),
      state: normalize_message_state(Map.get(message, :state) || Map.get(message, "state")),
      at: normalize_integer(Map.get(message, :at) || Map.get(message, "at"), now_ms())
    }
  end

  defp normalize_message(_), do: normalize_message(%{})

  defp normalize_tool_events(events) when is_list(events) do
    Enum.map(events, fn
      %{} = event -> Storage.sanitize_term(event)
      event -> Storage.sanitize_term(%{event: inspect(event)})
    end)
  end

  defp normalize_tool_events(_), do: []

  defp normalize_role(role) when role in [:user, :assistant, :system], do: role
  defp normalize_role("user"), do: :user
  defp normalize_role("assistant"), do: :assistant
  defp normalize_role("system"), do: :system
  defp normalize_role(_), do: :assistant

  defp normalize_message_state(state) when state in [:complete, :pending, :error], do: state
  defp normalize_message_state("complete"), do: :complete
  defp normalize_message_state("pending"), do: :pending
  defp normalize_message_state("error"), do: :error
  defp normalize_message_state(_), do: :complete

  defp normalize_hashes(hash_map) when is_map(hash_map) do
    Enum.reduce(hash_map, %{}, fn {key, value}, acc ->
      key = normalize_optional_binary(key)
      value = normalize_optional_binary(value)

      if is_binary(key) and key != "" and is_binary(value) and value != "" do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  defp normalize_hashes(_), do: %{}

  defp normalize_map(map) when is_map(map), do: Storage.sanitize_term(map)
  defp normalize_map(_), do: %{}

  defp normalize_optional_binary(value) when is_binary(value), do: value
  defp normalize_optional_binary(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_binary(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_binary(_), do: ""

  defp normalize_integer(value, _default) when is_integer(value), do: value
  defp normalize_integer(_, default), do: default

  defp normalize_non_neg_integer(value) when is_integer(value) and value >= 0, do: value
  defp normalize_non_neg_integer(_), do: 0

  defp message_hash(message) when is_map(message) do
    message
    |> Storage.sanitize_term()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp generated_message_id do
    "msg_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp now_ms, do: System.system_time(:millisecond)
end
