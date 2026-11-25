defmodule JidoStudio.Cluster.Scope do
  @moduledoc false

  alias JidoStudio.RuntimeScope
  alias JidoStudio.ScopeQuery

  @default_rpc_timeout_ms 3_000
  @process_node_key {__MODULE__, :node_param}

  @type scope :: :all | {:node, node()}

  @spec enabled?() :: boolean()
  def enabled? do
    Keyword.get(config(), :enabled, true) != false
  end

  @spec rpc_timeout_ms() :: pos_integer()
  def rpc_timeout_ms do
    config()
    |> Keyword.get(:rpc_timeout_ms, @default_rpc_timeout_ms)
    |> normalize_timeout_ms()
  end

  @spec default_scope() :: scope()
  def default_scope do
    case Keyword.get(config(), :default_scope, :all) do
      :all ->
        :all

      {:node, node} when is_atom(node) ->
        normalize_scope({:node, node})

      node when is_atom(node) ->
        normalize_scope({:node, node})

      node when is_binary(node) ->
        scope_from_node_param(node)

      _ ->
        :all
    end
  end

  @spec available_nodes() :: [node()]
  def available_nodes do
    [Node.self() | Node.list()]
    |> maybe_limit_to_self()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec dropdown_options() :: [map()]
  def dropdown_options do
    [
      %{label: "All Nodes", value: "all", self?: false}
      | Enum.map(available_nodes(), fn node ->
          %{label: to_string(node), value: Atom.to_string(node), self?: node == Node.self()}
        end)
    ]
  end

  @spec normalize_node_param(term()) :: String.t()
  def normalize_node_param(value) do
    case normalize_node_string(value) do
      nil -> "all"
      "all" -> "all"
      node_name -> if(node_available?(node_name), do: node_name, else: "all")
    end
  end

  @spec scope_from_params(map()) :: scope()
  def scope_from_params(params) when is_map(params) do
    scope_from_node_param(Map.get(params, "node"))
  end

  def scope_from_params(_), do: default_scope()

  @spec scope_from_node_param(term()) :: scope()
  def scope_from_node_param(value) do
    case normalize_node_param(value) do
      "all" -> :all
      node_name -> {:node, find_node(node_name)}
    end
  end

  @spec query_param_for_scope(scope() | String.t() | nil) :: String.t()
  def query_param_for_scope(scope_or_node_param) do
    case normalize_scope_or_node(scope_or_node_param) do
      :all -> "all"
      {:node, node} -> Atom.to_string(node)
    end
  end

  @spec normalize_scope(scope() | term()) :: scope()
  def normalize_scope(scope) do
    case scope do
      :all ->
        :all

      {:node, node} when is_atom(node) ->
        node_name = Atom.to_string(node)

        if node_available?(node_name) do
          {:node, find_node(node_name)}
        else
          :all
        end

      node when is_atom(node) ->
        normalize_scope({:node, node})

      node when is_binary(node) ->
        scope_from_node_param(node)

      _ ->
        :all
    end
  end

  @spec selected_node(scope() | term()) :: node() | nil
  def selected_node(scope) do
    case normalize_scope(scope) do
      {:node, node} -> node
      :all -> nil
    end
  end

  @spec with_scope_query(String.t(), scope() | String.t() | nil) :: String.t()
  def with_scope_query(path, scope_or_node_param) when is_binary(path) do
    node_param = query_param_for_scope(scope_or_node_param)
    runtime_key = RuntimeScope.current_runtime_key()

    ScopeQuery.with_scope_query(path, runtime_key, node_param)
  end

  @spec put_process_node_param(term()) :: :ok
  def put_process_node_param(value) do
    Process.put(@process_node_key, normalize_node_param(value))
    :ok
  end

  @spec current_node_param() :: String.t()
  def current_node_param do
    Process.get(@process_node_key)
    |> case do
      nil -> query_param_for_scope(default_scope())
      value -> normalize_node_param(value)
    end
  end

  @spec current_scope() :: scope()
  def current_scope do
    scope_from_node_param(current_node_param())
  end

  defp maybe_limit_to_self(nodes) do
    if enabled?(), do: nodes, else: [Node.self()]
  end

  defp normalize_timeout_ms(value) when is_integer(value) and value > 0, do: value
  defp normalize_timeout_ms(_), do: @default_rpc_timeout_ms

  defp normalize_scope_or_node(scope_or_node_param) do
    case scope_or_node_param do
      nil ->
        default_scope()

      :all ->
        :all

      {:node, _node} = scope ->
        normalize_scope(scope)

      node when is_binary(node) or is_atom(node) ->
        scope_from_node_param(node)

      _ ->
        :all
    end
  end

  defp normalize_node_string(nil), do: nil
  defp normalize_node_string(""), do: nil

  defp normalize_node_string("all"), do: "all"

  defp normalize_node_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_node_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_node_string(_), do: nil

  defp node_available?(node_name) when is_binary(node_name) do
    Enum.any?(available_nodes(), &(Atom.to_string(&1) == node_name))
  end

  defp find_node(node_name) do
    Enum.find(available_nodes(), Node.self(), &(Atom.to_string(&1) == node_name))
  end

  defp config do
    Application.get_env(:jido_studio, :cluster, [])
  end
end
