defmodule JidoStudio.Threads do
  @moduledoc false

  alias JidoStudio.Threads.Codec
  alias JidoStudio.Threads.Storage

  @spec list_threads(keyword()) :: [map()]
  def list_threads(opts \\ []) do
    query =
      opts
      |> Keyword.get(:query)
      |> normalize_optional_string()

    with {:ok, index} <- Storage.load_workspace_index(storage_opts(opts)) do
      index.items
      |> Enum.flat_map(fn {_workspace_id, item} ->
        list_threads_for_workspace(item, opts)
      end)
      |> maybe_filter_query(query)
      |> Enum.sort_by(&Map.get(&1, :updated_at, 0), :desc)
    else
      _ ->
        []
    end
  end

  @spec get_thread(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | :not_found | {:error, term()}
  def get_thread(agent_slug, instance_id, thread_id, opts \\ [])

  def get_thread(agent_slug, instance_id, thread_id, opts)
      when is_binary(agent_slug) and is_binary(instance_id) and is_binary(thread_id) do
    thread_key = Storage.thread_key(agent_slug, instance_id, thread_id)

    case Storage.load_thread(thread_key, storage_opts(opts)) do
      {:ok, thread} ->
        {:ok,
         %{
           thread: %{
             agent_slug: agent_slug,
             instance_id: instance_id,
             thread_id: thread_id,
             rev: thread.rev,
             entry_count: length(thread.entries || []),
             updated_at: latest_entry_time(thread.entries)
           },
           entries: Enum.map(thread.entries || [], &entry_view/1)
         }}

      :not_found ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  def get_thread(_, _, _, _), do: :not_found

  defp list_threads_for_workspace(item, opts) do
    agent_slug = item[:agent_slug] || item["agent_slug"]
    instance_id = item[:instance_id] || item["instance_id"]

    if is_binary(agent_slug) and is_binary(instance_id) do
      case Storage.get_workspace_checkpoint(agent_slug, instance_id, storage_opts(opts)) do
        {:ok, checkpoint} ->
          checkpoint
          |> Codec.decode_workspace_checkpoint()
          |> Map.get(:threads, [])
          |> Enum.map(fn thread ->
            %{
              thread_id: thread.id,
              title: thread.title,
              entry_count: thread.message_count,
              rev: thread.journal_rev,
              updated_at: thread.updated_at,
              agent_slug: agent_slug,
              agent_id: instance_id,
              instance_id: instance_id
            }
          end)

        _ ->
          []
      end
    else
      []
    end
  end

  defp entry_view(entry) do
    payload = normalize_map(entry.payload)
    refs = normalize_map(entry.refs)

    %{
      seq: entry.seq,
      at: entry.at,
      kind: entry.kind,
      payload: payload,
      payload_preview: payload_preview(payload),
      refs: refs,
      trace_id: trace_id_from(payload, refs),
      span_id: span_id_from(payload, refs)
    }
  end

  defp payload_preview(payload) when is_map(payload) do
    cond do
      is_binary(get_in(payload, [:message, :content])) ->
        get_in(payload, [:message, :content])
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
        |> String.slice(0, 120)

      is_binary(payload[:content]) ->
        payload[:content]
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
        |> String.slice(0, 120)

      true ->
        inspect(payload, limit: 6, printable_limit: 800)
    end
  end

  defp trace_id_from(payload, refs) do
    refs[:trace_id] || refs["trace_id"] || payload[:trace_id] || payload["trace_id"] ||
      payload[:jido_trace_id] || payload["jido_trace_id"]
  end

  defp span_id_from(payload, refs) do
    refs[:span_id] || refs["span_id"] || payload[:span_id] || payload["span_id"] ||
      payload[:jido_span_id] || payload["jido_span_id"]
  end

  defp latest_entry_time(entries) when is_list(entries) do
    entries
    |> Enum.map(&Map.get(&1, :at, 0))
    |> Enum.max(fn -> 0 end)
  end

  defp latest_entry_time(_), do: 0

  defp maybe_filter_query(threads, nil), do: threads

  defp maybe_filter_query(threads, query) do
    q = String.downcase(query)

    Enum.filter(threads, fn thread ->
      searchable =
        [
          thread.thread_id,
          thread.title,
          thread.agent_slug,
          thread.agent_id
        ]
        |> Enum.filter(&is_binary/1)
        |> Enum.join(" ")
        |> String.downcase()

      String.contains?(searchable, q)
    end)
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_), do: %{}

  defp normalize_optional_string(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_string(_), do: nil

  defp storage_opts(opts) do
    []
    |> maybe_put(:jido_instance, Keyword.get(opts, :jido_instance))
    |> maybe_put(:thread_storage_mode, Keyword.get(opts, :thread_storage_mode))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
