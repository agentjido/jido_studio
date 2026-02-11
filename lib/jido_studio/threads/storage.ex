defmodule JidoStudio.Threads.Storage do
  @moduledoc false

  alias Jido.Storage

  @default_storage {Jido.Storage.File, path: "priv/jido_studio/storage"}
  @workspace_index_key {:jido_studio, :workspace_index}
  @workspace_index_version 1
  @max_depth 8
  @max_map_entries 200
  @max_list_entries 200
  @max_binary_size 8_192

  @type storage_opts :: keyword()

  @spec persistence_enabled?() :: boolean()
  def persistence_enabled? do
    Application.get_env(:jido_studio, :thread_persistence, true) == true
  end

  @spec auto_start_runtime?() :: boolean()
  def auto_start_runtime? do
    Application.get_env(:jido_studio, :auto_start_runtime, true) == true
  end

  @spec thread_storage_mode() :: :studio | :inherit_jido_instance
  def thread_storage_mode do
    case Application.get_env(:jido_studio, :thread_storage_mode, :studio) do
      :inherit_jido_instance -> :inherit_jido_instance
      _ -> :studio
    end
  end

  @spec thread_retention_days() :: non_neg_integer()
  def thread_retention_days do
    case Application.get_env(:jido_studio, :thread_retention_days, 30) do
      days when is_integer(days) and days >= 0 -> days
      _ -> 30
    end
  end

  @spec persist_strategy_context_mode() :: :off | :summary | :full
  def persist_strategy_context_mode do
    case Application.get_env(:jido_studio, :persist_strategy_context, :summary) do
      :off -> :off
      :full -> :full
      _ -> :summary
    end
  end

  @spec workspace_key(String.t(), String.t()) :: tuple()
  def workspace_key(agent_slug, instance_id) when is_binary(agent_slug) and is_binary(instance_id) do
    {:studio_workspace, agent_slug, instance_id}
  end

  @spec workspace_id(String.t(), String.t()) :: String.t()
  def workspace_id(agent_slug, instance_id) when is_binary(agent_slug) and is_binary(instance_id) do
    "#{agent_slug}::#{instance_id}"
  end

  @spec thread_key(String.t(), String.t(), String.t()) :: String.t()
  def thread_key(agent_slug, instance_id, thread_id)
      when is_binary(agent_slug) and is_binary(instance_id) and is_binary(thread_id) do
    "studio:#{agent_slug}:#{instance_id}:#{thread_id}"
  end

  @spec workspace_index_key() :: tuple()
  def workspace_index_key, do: @workspace_index_key

  @spec get_workspace_checkpoint(String.t(), String.t(), storage_opts()) ::
          {:ok, map()} | :not_found | {:error, term()}
  def get_workspace_checkpoint(agent_slug, instance_id, opts \\ []) do
    get_checkpoint(workspace_key(agent_slug, instance_id), opts)
  end

  @spec put_workspace_checkpoint(String.t(), String.t(), map(), storage_opts()) ::
          :ok | {:error, term()}
  def put_workspace_checkpoint(agent_slug, instance_id, checkpoint, opts \\ []) when is_map(checkpoint) do
    put_checkpoint(workspace_key(agent_slug, instance_id), checkpoint, opts)
  end

  @spec delete_workspace_checkpoint(String.t(), String.t(), storage_opts()) :: :ok | {:error, term()}
  def delete_workspace_checkpoint(agent_slug, instance_id, opts \\ []) do
    delete_checkpoint(workspace_key(agent_slug, instance_id), opts)
  end

  @spec get_checkpoint(term(), storage_opts()) :: {:ok, map()} | :not_found | {:error, term()}
  def get_checkpoint(key, opts \\ []) do
    with {:ok, {adapter, adapter_opts}} <- resolve_storage(opts) do
      adapter.get_checkpoint(key, adapter_opts)
    end
  end

  @spec put_checkpoint(term(), map(), storage_opts()) :: :ok | {:error, term()}
  def put_checkpoint(key, checkpoint, opts \\ []) when is_map(checkpoint) do
    with {:ok, {adapter, adapter_opts}} <- resolve_storage(opts) do
      adapter.put_checkpoint(key, sanitize_term(checkpoint), adapter_opts)
    end
  end

  @spec delete_checkpoint(term(), storage_opts()) :: :ok | {:error, term()}
  def delete_checkpoint(key, opts \\ []) do
    with {:ok, {adapter, adapter_opts}} <- resolve_storage(opts) do
      adapter.delete_checkpoint(key, adapter_opts)
    end
  end

  @spec load_thread(String.t(), storage_opts()) ::
          {:ok, Jido.Thread.t()} | :not_found | {:error, term()}
  def load_thread(thread_key, opts \\ []) when is_binary(thread_key) do
    with {:ok, {adapter, adapter_opts}} <- resolve_storage(opts) do
      adapter.load_thread(thread_key, adapter_opts)
    end
  end

  @spec append_thread(String.t(), [Jido.Thread.Entry.t()], storage_opts()) ::
          {:ok, Jido.Thread.t()} | {:error, term()}
  def append_thread(thread_key, entries, opts \\ []) when is_binary(thread_key) and is_list(entries) do
    with {:ok, {adapter, adapter_opts}} <- resolve_storage(opts) do
      expected_rev = Keyword.get(opts, :expected_rev)

      append_opts =
        adapter_opts ++
          if is_integer(expected_rev) and expected_rev >= 0 do
            [expected_rev: expected_rev]
          else
            []
          end

      safe_entries = Enum.map(entries, &sanitize_entry/1)
      adapter.append_thread(thread_key, safe_entries, append_opts)
    end
  end

  @spec delete_thread(String.t(), storage_opts()) :: :ok | {:error, term()}
  def delete_thread(thread_key, opts \\ []) when is_binary(thread_key) do
    with {:ok, {adapter, adapter_opts}} <- resolve_storage(opts) do
      adapter.delete_thread(thread_key, adapter_opts)
    end
  end

  @spec load_workspace_index(storage_opts()) :: {:ok, map()} | {:error, term()}
  def load_workspace_index(opts \\ []) do
    case get_checkpoint(@workspace_index_key, opts) do
      {:ok, %{} = index} ->
        {:ok, normalize_workspace_index(index)}

      :not_found ->
        {:ok, empty_workspace_index()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec put_workspace_index(map(), storage_opts()) :: :ok | {:error, term()}
  def put_workspace_index(index, opts \\ []) when is_map(index) do
    put_checkpoint(@workspace_index_key, normalize_workspace_index(index), opts)
  end

  @spec empty_workspace_index() :: map()
  def empty_workspace_index do
    %{schema_version: @workspace_index_version, updated_at: now_ms(), items: %{}}
  end

  @spec normalize_workspace_index(map()) :: map()
  def normalize_workspace_index(index) when is_map(index) do
    %{
      schema_version: @workspace_index_version,
      updated_at: normalize_integer(Map.get(index, :updated_at) || Map.get(index, "updated_at"), now_ms()),
      items: normalize_index_items(Map.get(index, :items) || Map.get(index, "items") || %{})
    }
  end

  @spec resolve_storage(storage_opts()) :: {:ok, {module(), keyword()}} | {:error, term()}
  def resolve_storage(opts \\ []) do
    mode = Keyword.get(opts, :thread_storage_mode, thread_storage_mode())
    jido_instance = Keyword.get(opts, :jido_instance)

    storage_config =
      case mode do
        :inherit_jido_instance ->
          storage_from_instance(jido_instance) || configured_storage()

        _ ->
          configured_storage()
      end

    {adapter, adapter_opts} = Storage.normalize_storage(storage_config)
    _ = Code.ensure_loaded(adapter)

    if function_exported?(adapter, :get_checkpoint, 2) and
         function_exported?(adapter, :put_checkpoint, 3) and
         function_exported?(adapter, :delete_checkpoint, 2) and
         function_exported?(adapter, :load_thread, 2) and
         function_exported?(adapter, :append_thread, 3) and
         function_exported?(adapter, :delete_thread, 2) do
      {:ok, {adapter, adapter_opts}}
    else
      {:error, {:invalid_storage_adapter, adapter}}
    end
  rescue
    error -> {:error, {:storage_resolution_failed, Exception.message(error)}}
  end

  @spec sanitize_term(term()) :: term()
  def sanitize_term(term), do: sanitize_term(term, 0)

  defp configured_storage do
    Application.get_env(:jido_studio, :thread_storage, @default_storage)
  end

  defp storage_from_instance(instance) when is_atom(instance) do
    if function_exported?(instance, :__jido_storage__, 0) do
      instance.__jido_storage__()
    end
  rescue
    _ -> nil
  end

  defp storage_from_instance(_), do: nil

  defp sanitize_entry(%Jido.Thread.Entry{} = entry) do
    %{entry | payload: sanitize_term(entry.payload), refs: sanitize_term(entry.refs)}
  end

  defp sanitize_entry(other), do: sanitize_term(other)

  defp sanitize_term(term, depth) when depth >= @max_depth do
    inspect(term, limit: 25, printable_limit: 2_000)
  end

  defp sanitize_term(map, depth) when is_map(map) do
    map
    |> Enum.take(@max_map_entries)
    |> Enum.map(fn {key, value} ->
      if stacktrace_key?(key) do
        {key, "[OMITTED]"}
      else
        {key, sanitize_term(value, depth + 1)}
      end
    end)
    |> Map.new()
  end

  defp sanitize_term(list, depth) when is_list(list) do
    list
    |> Enum.take(@max_list_entries)
    |> Enum.map(&sanitize_term(&1, depth + 1))
  end

  defp sanitize_term(binary, _depth) when is_binary(binary) and byte_size(binary) > @max_binary_size do
    binary_part(binary, 0, @max_binary_size) <> "...[truncated]"
  end

  defp sanitize_term(tuple, depth) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&sanitize_term(&1, depth + 1))
    |> List.to_tuple()
  end

  defp sanitize_term(other, _depth), do: other

  defp stacktrace_key?(key) when key in [:stacktrace, "stacktrace"], do: true

  defp stacktrace_key?(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> stacktrace_key?()
  end

  defp stacktrace_key?(key) when is_binary(key) do
    String.contains?(String.downcase(key), "stacktrace")
  end

  defp stacktrace_key?(_), do: false

  defp normalize_index_items(items) when is_map(items) do
    Enum.reduce(items, %{}, fn {workspace_id, item}, acc ->
      case normalize_index_item(workspace_id, item) do
        nil -> acc
        normalized -> Map.put(acc, workspace_id, normalized)
      end
    end)
  end

  defp normalize_index_items(_), do: %{}

  defp normalize_index_item(workspace_id, item)
       when is_binary(workspace_id) and is_map(item) do
    agent_slug = Map.get(item, :agent_slug) || Map.get(item, "agent_slug")
    instance_id = Map.get(item, :instance_id) || Map.get(item, "instance_id")

    if is_binary(agent_slug) and is_binary(instance_id) do
      %{
        agent_slug: agent_slug,
        instance_id: instance_id,
        updated_at:
          normalize_integer(Map.get(item, :updated_at) || Map.get(item, "updated_at"), now_ms())
      }
    end
  end

  defp normalize_index_item(_, _), do: nil

  defp normalize_integer(value, _default) when is_integer(value), do: value
  defp normalize_integer(_, default), do: default

  defp now_ms, do: System.system_time(:millisecond)
end
