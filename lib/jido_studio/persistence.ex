defmodule JidoStudio.Persistence do
  @moduledoc false

  @behaviour JidoStudio.Persistence.Adapter

  @default_adapter JidoStudio.Persistence.ETS

  @type namespace :: JidoStudio.Persistence.Adapter.namespace()
  @type id :: JidoStudio.Persistence.Adapter.id()
  @type doc :: JidoStudio.Persistence.Adapter.doc()
  @type stream :: JidoStudio.Persistence.Adapter.stream()
  @type event :: JidoStudio.Persistence.Adapter.event()

  @spec child_specs(keyword()) :: [Supervisor.child_spec()]
  def child_specs(opts \\ []) do
    case resolve_adapter(opts) do
      {:ok, {adapter, adapter_opts}} ->
        if function_exported?(adapter, :child_spec, 1) do
          case adapter.child_spec(adapter_opts) do
            :ignore -> []
            nil -> []
            child_spec -> [child_spec]
          end
        else
          []
        end

      {:error, _reason} ->
        []
    end
  end

  @impl true
  def put_doc(namespace, id, doc, opts \\ []) do
    with {:ok, {adapter, adapter_opts}} <- resolve_adapter(opts) do
      adapter.put_doc(namespace, id, doc, adapter_opts)
    end
  end

  @impl true
  def get_doc(namespace, id, opts \\ []) do
    with {:ok, {adapter, adapter_opts}} <- resolve_adapter(opts) do
      adapter.get_doc(namespace, id, adapter_opts)
    end
  end

  @impl true
  def list_docs(namespace, opts \\ []) do
    case resolve_adapter(opts) do
      {:ok, {adapter, adapter_opts}} -> adapter.list_docs(namespace, adapter_opts)
      {:error, _reason} -> []
    end
  end

  @impl true
  def delete_doc(namespace, id, opts \\ []) do
    with {:ok, {adapter, adapter_opts}} <- resolve_adapter(opts) do
      adapter.delete_doc(namespace, id, adapter_opts)
    end
  end

  @impl true
  def append_event(stream, event, opts \\ []) do
    with {:ok, {adapter, adapter_opts}} <- resolve_adapter(opts) do
      adapter.append_event(stream, event, adapter_opts)
    end
  end

  @impl true
  def read_events(stream, opts \\ []) do
    case resolve_adapter(opts) do
      {:ok, {adapter, adapter_opts}} -> adapter.read_events(stream, adapter_opts)
      {:error, _reason} -> []
    end
  end

  @spec adapter() :: module()
  def adapter do
    case resolve_adapter() do
      {:ok, {adapter, _opts}} -> adapter
      {:error, _} -> @default_adapter
    end
  end

  @spec resolve_adapter(keyword()) :: {:ok, {module(), keyword()}} | {:error, term()}
  def resolve_adapter(runtime_opts \\ []) do
    config = persistence_config()

    adapter =
      runtime_opts
      |> Keyword.get(:adapter)
      |> case do
        nil -> Keyword.get(config, :adapter, @default_adapter)
        value -> value
      end

    adapter_opts =
      config
      |> Keyword.get(:opts, [])
      |> Keyword.merge(Keyword.get(runtime_opts, :opts, []))
      |> Keyword.merge(Keyword.drop(runtime_opts, [:adapter, :opts]))

    _ = Code.ensure_loaded(adapter)

    if valid_adapter?(adapter) do
      {:ok, {adapter, adapter_opts}}
    else
      {:error, {:invalid_persistence_adapter, adapter}}
    end
  rescue
    error ->
      {:error, {:persistence_resolution_failed, Exception.message(error)}}
  end

  defp persistence_config do
    Application.get_env(:jido_studio, :persistence, [])
    |> Keyword.put_new(:adapter, @default_adapter)
    |> Keyword.put_new(:opts, [])
  end

  defp valid_adapter?(adapter) when is_atom(adapter) do
    function_exported?(adapter, :put_doc, 4) and
      function_exported?(adapter, :get_doc, 3) and
      function_exported?(adapter, :list_docs, 2) and
      function_exported?(adapter, :delete_doc, 3) and
      function_exported?(adapter, :append_event, 3) and
      function_exported?(adapter, :read_events, 2)
  end

  defp valid_adapter?(_), do: false
end
