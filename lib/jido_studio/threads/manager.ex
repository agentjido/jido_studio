defmodule JidoStudio.Threads.Manager do
  @moduledoc false
  use GenServer

  alias JidoStudio.Threads.Codec
  alias JidoStudio.Threads.Storage

  @cleanup_interval_ms :timer.minutes(30)

  @type workspace_payload :: %{
          chat_state: map(),
          draft_message: String.t(),
          thread_contexts: map(),
          source: :fresh | :persisted,
          instance_binding: map()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec load_workspace(String.t(), String.t(), keyword()) ::
          {:ok, workspace_payload()} | {:error, term()}
  def load_workspace(agent_slug, instance_id, opts \\ []) do
    with {:ok, _pid} <- ensure_started() do
      safe_call(
        {:load_workspace, agent_slug, instance_id, opts},
        {:ok, Codec.empty_workspace_payload()}
      )
    end
  end

  @spec save_workspace(String.t(), String.t(), map(), keyword()) :: :ok | {:error, term()}
  def save_workspace(agent_slug, instance_id, chat_state, opts \\ []) do
    with {:ok, _pid} <- ensure_started() do
      safe_call({:save_workspace, agent_slug, instance_id, chat_state, opts}, :ok)
    end
  end

  @spec delete_workspace(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_workspace(agent_slug, instance_id, opts \\ []) do
    with {:ok, _pid} <- ensure_started() do
      safe_call({:delete_workspace, agent_slug, instance_id, opts}, :ok)
    end
  end

  @impl true
  def init(_opts) do
    state = %{cleanup_ref: nil}
    {:ok, schedule_cleanup(state)}
  end

  @impl true
  def handle_call({:load_workspace, agent_slug, instance_id, opts}, _from, state) do
    reply = load_workspace_internal(agent_slug, instance_id, opts)
    {:reply, reply, state}
  end

  def handle_call({:save_workspace, agent_slug, instance_id, chat_state, opts}, _from, state) do
    reply = save_workspace_internal(agent_slug, instance_id, chat_state, opts)
    {:reply, reply, state}
  end

  def handle_call({:delete_workspace, agent_slug, instance_id, opts}, _from, state) do
    reply = delete_workspace_internal(agent_slug, instance_id, opts)
    {:reply, reply, state}
  end

  @impl true
  def handle_info(:cleanup_retention, state) do
    state = %{state | cleanup_ref: nil}
    _ = cleanup_expired_workspaces()
    {:noreply, schedule_cleanup(state)}
  end

  defp load_workspace_internal(agent_slug, instance_id, opts) do
    if not Storage.persistence_enabled?() do
      {:ok, Codec.empty_workspace_payload()}
    else
      storage_opts = storage_opts(opts)

      case Storage.get_workspace_checkpoint(agent_slug, instance_id, storage_opts) do
        {:ok, %{} = checkpoint} ->
          decoded = Codec.decode_workspace_checkpoint(checkpoint)

          {messages_by_thread, threads} =
            load_thread_messages(agent_slug, instance_id, decoded, storage_opts)

          chat_state = Codec.workspace_from_checkpoint(decoded, messages_by_thread)

          {:ok,
           Codec.workspace_payload(decoded, chat_state, %{
             agent_slug: agent_slug,
             instance_id: instance_id
           })
           |> Map.put(:chat_state, %{
             chat_state
             | threads: threads,
               messages_by_thread: messages_by_thread
           })}

        :not_found ->
          {:ok, Codec.empty_workspace_payload()}

        {:error, reason} ->
          {:error, reason}
      end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp save_workspace_internal(agent_slug, instance_id, chat_state, opts) do
    if not Storage.persistence_enabled?() do
      :ok
    else
      storage_opts = storage_opts(opts)
      draft_message = Keyword.get(opts, :draft_message, "")
      thread_contexts = Keyword.get(opts, :thread_contexts, %{})
      instance_binding = Keyword.get(opts, :instance_binding, %{})

      existing_checkpoint =
        case Storage.get_workspace_checkpoint(agent_slug, instance_id, storage_opts) do
          {:ok, %{} = checkpoint} -> Codec.decode_workspace_checkpoint(checkpoint)
          _ -> Codec.decode_workspace_checkpoint(%{})
        end

      existing_records = Codec.thread_records(existing_checkpoint)
      state = normalize_chat_state(chat_state)

      with {:ok, updated_records} <-
             sync_threads(agent_slug, instance_id, state, existing_records, storage_opts),
           :ok <-
             prune_deleted_threads(agent_slug, instance_id, state, existing_records, storage_opts),
           :ok <-
             persist_workspace_checkpoint(
               agent_slug,
               instance_id,
               state,
               updated_records,
               thread_contexts,
               draft_message,
               instance_binding,
               storage_opts
             ),
           :ok <- update_workspace_index(agent_slug, instance_id, storage_opts) do
        :ok
      end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp delete_workspace_internal(agent_slug, instance_id, opts) do
    if not Storage.persistence_enabled?() do
      :ok
    else
      storage_opts = storage_opts(opts)

      with {:ok, decoded} <- load_checkpoint_for_delete(agent_slug, instance_id, storage_opts),
           :ok <- delete_workspace_threads(agent_slug, instance_id, decoded, storage_opts),
           :ok <- Storage.delete_workspace_checkpoint(agent_slug, instance_id, storage_opts),
           :ok <- remove_workspace_index(agent_slug, instance_id, storage_opts) do
        :ok
      end
    end
  end

  defp load_checkpoint_for_delete(agent_slug, instance_id, storage_opts) do
    case Storage.get_workspace_checkpoint(agent_slug, instance_id, storage_opts) do
      {:ok, checkpoint} -> {:ok, Codec.decode_workspace_checkpoint(checkpoint)}
      :not_found -> {:ok, Codec.decode_workspace_checkpoint(%{})}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_threads(agent_slug, instance_id, chat_state, existing_records, storage_opts) do
    Enum.reduce_while(chat_state.threads, {:ok, %{}}, fn thread, {:ok, acc} ->
      messages = Map.get(chat_state.messages_by_thread, thread.id, [])
      existing_record = Map.get(existing_records, thread.id, default_thread_record(thread.id))

      case sync_thread(agent_slug, instance_id, thread, messages, existing_record, storage_opts) do
        {:ok, record} ->
          {:cont, {:ok, Map.put(acc, thread.id, record)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp sync_thread(agent_slug, instance_id, thread, messages, existing_record, storage_opts) do
    thread_key = Storage.thread_key(agent_slug, instance_id, thread.id)
    do_sync_thread(thread_key, messages, existing_record, storage_opts, 1)
  end

  defp do_sync_thread(thread_key, messages, existing_record, storage_opts, retries_left) do
    {entries, hashes} = Codec.diff_messages(messages, existing_record.message_hashes)

    if entries == [] do
      {:ok, %{existing_record | message_hashes: hashes}}
    else
      expected_rev = existing_record.journal_rev

      case Storage.append_thread(
             thread_key,
             entries,
             Keyword.put(storage_opts, :expected_rev, expected_rev)
           ) do
        {:ok, thread} ->
          {:ok,
           %{
             existing_record
             | journal_rev: thread.rev,
               message_hashes: hashes
           }}

        {:error, :conflict} when retries_left > 0 ->
          case Storage.load_thread(thread_key, storage_opts) do
            {:ok, thread} ->
              latest_record = %{
                existing_record
                | journal_rev: thread.rev,
                  message_hashes: Codec.message_hashes_from_thread(thread)
              }

              do_sync_thread(thread_key, messages, latest_record, storage_opts, retries_left - 1)

            :not_found ->
              do_sync_thread(
                thread_key,
                messages,
                %{existing_record | journal_rev: 0, message_hashes: %{}},
                storage_opts,
                retries_left - 1
              )

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp prune_deleted_threads(agent_slug, instance_id, chat_state, existing_records, storage_opts) do
    active_ids = MapSet.new(Enum.map(chat_state.threads, & &1.id))

    existing_records
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(active_ids, &1))
    |> Enum.reduce_while(:ok, fn thread_id, :ok ->
      thread_key = Storage.thread_key(agent_slug, instance_id, thread_id)

      case Storage.delete_thread(thread_key, storage_opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_workspace_checkpoint(
         agent_slug,
         instance_id,
         chat_state,
         thread_records,
         thread_contexts,
         draft_message,
         instance_binding,
         storage_opts
       ) do
    checkpoint =
      Codec.encode_workspace_checkpoint(chat_state,
        thread_records: thread_records,
        thread_contexts: thread_contexts,
        draft_message: draft_message,
        instance_binding: instance_binding,
        updated_at: now_ms()
      )

    Storage.put_workspace_checkpoint(agent_slug, instance_id, checkpoint, storage_opts)
  end

  defp update_workspace_index(agent_slug, instance_id, storage_opts) do
    workspace_id = Storage.workspace_id(agent_slug, instance_id)

    with {:ok, index} <- Storage.load_workspace_index(storage_opts) do
      items =
        Map.put(index.items, workspace_id, %{
          agent_slug: agent_slug,
          instance_id: instance_id,
          updated_at: now_ms()
        })

      Storage.put_workspace_index(%{index | items: items, updated_at: now_ms()}, storage_opts)
    end
  end

  defp remove_workspace_index(agent_slug, instance_id, storage_opts) do
    workspace_id = Storage.workspace_id(agent_slug, instance_id)

    with {:ok, index} <- Storage.load_workspace_index(storage_opts) do
      items = Map.delete(index.items, workspace_id)
      Storage.put_workspace_index(%{index | items: items, updated_at: now_ms()}, storage_opts)
    end
  end

  defp load_thread_messages(agent_slug, instance_id, decoded_checkpoint, storage_opts) do
    Enum.reduce(decoded_checkpoint.threads, {%{}, []}, fn thread, {messages_by_thread, threads} ->
      thread_key = Storage.thread_key(agent_slug, instance_id, thread.id)

      case Storage.load_thread(thread_key, storage_opts) do
        {:ok, thread_log} ->
          messages = Codec.messages_from_thread(thread_log)

          thread =
            thread
            |> Map.put(:message_count, max(thread.message_count, length(messages)))
            |> Map.put(:journal_rev, thread_log.rev)
            |> Map.put(:message_hashes, Codec.message_hashes_from_thread(thread_log))

          {Map.put(messages_by_thread, thread.id, messages), [thread | threads]}

        _ ->
          {Map.put(messages_by_thread, thread.id, []), [thread | threads]}
      end
    end)
    |> then(fn {messages_by_thread, threads} ->
      {messages_by_thread, Enum.sort_by(threads, & &1.updated_at, :desc)}
    end)
  end

  defp delete_workspace_threads(agent_slug, instance_id, decoded, storage_opts) do
    decoded.threads
    |> Enum.map(& &1.id)
    |> Enum.reduce_while(:ok, fn thread_id, :ok ->
      thread_key = Storage.thread_key(agent_slug, instance_id, thread_id)

      case Storage.delete_thread(thread_key, storage_opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp cleanup_expired_workspaces do
    retention_days = Storage.thread_retention_days()

    if retention_days <= 0 or not Storage.persistence_enabled?() do
      :ok
    else
      cutoff = now_ms() - retention_days * 24 * 60 * 60 * 1_000

      case Storage.load_workspace_index([]) do
        {:ok, index} ->
          expired_items =
            index.items
            |> Enum.filter(fn {_workspace_id, item} -> (item[:updated_at] || 0) < cutoff end)

          Enum.each(expired_items, fn {_workspace_id, item} ->
            agent_slug = item[:agent_slug]
            instance_id = item[:instance_id]

            if is_binary(agent_slug) and is_binary(instance_id) do
              _ = delete_workspace_internal(agent_slug, instance_id, [])
            end
          end)

          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end

  defp schedule_cleanup(state) do
    if Storage.persistence_enabled?() and Storage.thread_retention_days() > 0 do
      ref = Process.send_after(self(), :cleanup_retention, @cleanup_interval_ms)
      %{state | cleanup_ref: ref}
    else
      %{state | cleanup_ref: nil}
    end
  end

  defp storage_opts(opts) do
    [
      jido_instance: Keyword.get(opts, :jido_instance),
      thread_storage_mode: Keyword.get(opts, :thread_storage_mode, Storage.thread_storage_mode())
    ]
  end

  defp default_thread_record(thread_id) do
    %{
      id: thread_id,
      title: "New Chat",
      message_count: 0,
      updated_at: now_ms(),
      journal_rev: 0,
      message_hashes: %{}
    }
  end

  defp normalize_chat_state(%{
         threads: threads,
         active_thread_id: active_thread_id,
         messages_by_thread: by_thread
       })
       when is_list(threads) and is_map(by_thread) do
    %{threads: threads, active_thread_id: active_thread_id, messages_by_thread: by_thread}
  end

  defp normalize_chat_state(_), do: %{threads: [], active_thread_id: nil, messages_by_thread: %{}}

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        {:ok, pid}

      _ ->
        case start_link([]) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} when is_pid(pid) -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp safe_call(message, fallback) do
    GenServer.call(__MODULE__, message, 5_000)
  catch
    :exit, {:noproc, _} -> fallback
    :exit, {:normal, _} -> fallback
    :exit, {:shutdown, _} -> fallback
  end

  defp now_ms, do: System.system_time(:millisecond)
end
