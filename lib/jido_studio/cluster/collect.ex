defmodule JidoStudio.Cluster.Collect do
  @moduledoc false

  alias JidoStudio.Cluster.RPC
  alias JidoStudio.Cluster.Scope

  @spec list(term(), module(), atom(), list(), function()) :: list()
  def list(scope, module, fun, args, rpc_fun \\ &RPC.call/4)
      when is_atom(module) and is_atom(fun) and is_list(args) and is_function(rpc_fun, 4) do
    case scope do
      :all ->
        collect_all(module, fun, args, rpc_fun)

      other ->
        collect_node(other, module, fun, args, rpc_fun)
    end
  end

  defp collect_all(module, fun, args, rpc_fun) do
    case rpc_fun.(:all, module, fun, args) do
      {:ok, [%{ok?: _} | _] = results} ->
        results
        |> Enum.flat_map(fn
          %{ok?: true, value: items} when is_list(items) -> items
          _ -> []
        end)

      {:ok, items} when is_list(items) ->
        items

      _ ->
        []
    end
  end

  defp collect_node(scope, module, fun, args, rpc_fun) do
    node = Scope.selected_node(scope) || Node.self()

    case rpc_fun.({:node, node}, module, fun, args) do
      {:ok, items} when is_list(items) -> items
      _ -> []
    end
  end
end
