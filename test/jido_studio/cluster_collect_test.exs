defmodule JidoStudio.ClusterCollectTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Cluster.Collect

  test "list/5 flattens successful :all node results" do
    rpc_fun = fn :all, _module, _fun, _args ->
      {:ok,
       [
         %{ok?: true, value: [%{id: 1}, %{id: 2}]},
         %{ok?: false, error: :nodedown},
         %{ok?: true, value: [%{id: 3}]}
       ]}
    end

    assert [%{id: 1}, %{id: 2}, %{id: 3}] == Collect.list(:all, __MODULE__, :noop, [], rpc_fun)
  end

  test "list/5 uses concrete node scope for non-all collection" do
    node = Node.self()

    rpc_fun = fn {:node, ^node}, _module, _fun, _args ->
      {:ok, [%{id: "node-item"}]}
    end

    assert [%{id: "node-item"}] ==
             Collect.list({:node, node}, __MODULE__, :noop, [], rpc_fun)
  end

  test "list/5 returns [] for RPC errors" do
    rpc_fun = fn _scope, _module, _fun, _args ->
      {:error, :timeout}
    end

    assert [] == Collect.list(:all, __MODULE__, :noop, [], rpc_fun)
    assert [] == Collect.list({:node, Node.self()}, __MODULE__, :noop, [], rpc_fun)
  end
end
