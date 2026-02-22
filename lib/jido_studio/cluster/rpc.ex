defmodule JidoStudio.Cluster.RPC do
  @moduledoc false

  alias JidoStudio.Cluster.Scope

  @type scope :: Scope.scope()

  @type node_result :: %{
          node: node(),
          ok?: boolean(),
          value: term() | nil,
          error: map() | nil
        }

  @spec call(scope() | term(), module(), atom(), [term()], keyword()) ::
          {:ok, term()}
          | {:error, map()}
          | {:ok, [node_result()]}
  def call(scope, module, fun, args, opts \\ [])
      when is_atom(module) and is_atom(fun) and is_list(args) do
    timeout_ms = Keyword.get(opts, :timeout_ms, Scope.rpc_timeout_ms())

    case Scope.normalize_scope(scope) do
      :all ->
        nodes = Scope.available_nodes()
        {:ok, Enum.map(nodes, &invoke_node(&1, module, fun, args, timeout_ms))}

      {:node, node} ->
        case invoke_node(node, module, fun, args, timeout_ms) do
          %{ok?: true, value: value} -> {:ok, value}
          %{error: error} -> {:error, error}
        end
    end
  end

  @spec map_reduce(
          scope() | term(),
          [{module(), atom(), [term()]}],
          (term(), map() -> term()),
          keyword()
        ) ::
          term()
  def map_reduce(scope, calls, reducer, opts \\ [])
      when is_list(calls) and is_function(reducer, 2) do
    timeout_ms = Keyword.get(opts, :timeout_ms, Scope.rpc_timeout_ms())
    initial = Keyword.get(opts, :initial, %{})
    nodes = nodes_for_scope(scope)

    Enum.reduce(nodes, initial, fn node, acc ->
      Enum.reduce(calls, acc, fn
        {module, fun, args}, inner_acc when is_atom(module) and is_atom(fun) and is_list(args) ->
          result = invoke_node(node, module, fun, args, timeout_ms)
          reducer.(inner_acc, %{node: node, call: {module, fun, args}, result: result})

        _invalid_call, inner_acc ->
          inner_acc
      end)
    end)
  end

  defp nodes_for_scope(scope) do
    case Scope.normalize_scope(scope) do
      :all -> Scope.available_nodes()
      {:node, node} -> [node]
    end
  end

  defp invoke_node(node, module, fun, args, timeout_ms) do
    if node == Node.self() do
      try do
        %{node: node, ok?: true, value: apply(module, fun, args), error: nil}
      rescue
        exception ->
          %{node: node, ok?: false, value: nil, error: local_error(node, exception)}
      catch
        kind, reason ->
          %{node: node, ok?: false, value: nil, error: local_throw_error(node, kind, reason)}
      end
    else
      case :rpc.call(node, module, fun, args, timeout_ms) do
        {:badrpc, reason} ->
          %{node: node, ok?: false, value: nil, error: rpc_error(node, reason)}

        value ->
          %{node: node, ok?: true, value: value, error: nil}
      end
    end
  end

  defp local_error(node, exception) do
    %{
      node: node,
      kind: :exception,
      reason: Exception.message(exception),
      module: exception.__struct__
    }
  end

  defp local_throw_error(node, kind, reason) do
    %{
      node: node,
      kind: kind,
      reason: reason
    }
  end

  defp rpc_error(node, :timeout), do: %{node: node, kind: :timeout, reason: :timeout}
  defp rpc_error(node, :nodedown), do: %{node: node, kind: :nodedown, reason: :nodedown}

  defp rpc_error(node, {:EXIT, reason}),
    do: %{node: node, kind: :exit, reason: reason}

  defp rpc_error(node, reason), do: %{node: node, kind: :rpc, reason: reason}
end
