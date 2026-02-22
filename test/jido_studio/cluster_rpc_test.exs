defmodule JidoStudio.Cluster.RPCTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Cluster.RPC

  test "calls selected node locally" do
    assert {:ok, "ABC"} = RPC.call({:node, Node.self()}, String, :upcase, ["abc"])
  end

  test "calls all nodes and returns node envelopes" do
    assert {:ok, results} = RPC.call(:all, String, :upcase, ["abc"])
    assert is_list(results)
    assert Enum.any?(results, &(&1.node == Node.self() and &1.ok? and &1.value == "ABC"))
  end

  test "map_reduce accumulates per-call results" do
    calls = [
      {String, :length, ["abc"]},
      {String, :length, ["hello"]}
    ]

    total =
      RPC.map_reduce(
        {:node, Node.self()},
        calls,
        fn acc, %{result: result} ->
          case result do
            %{ok?: true, value: value} when is_integer(value) -> acc + value
            _ -> acc
          end
        end,
        initial: 0
      )

    assert total == 8
  end
end
