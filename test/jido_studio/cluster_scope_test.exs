defmodule JidoStudio.Cluster.ScopeTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Cluster.Scope

  test "normalizes invalid node to all" do
    assert Scope.normalize_node_param("missing@node") == "all"
    assert Scope.scope_from_node_param("missing@node") == :all
  end

  test "normalizes self node" do
    self_node = Atom.to_string(Node.self())

    assert Scope.normalize_node_param(self_node) == self_node
    assert Scope.scope_from_node_param(self_node) == {:node, Node.self()}
  end

  test "adds node query without dropping existing params" do
    scoped = Scope.with_scope_query("/studio/agents?status=running", "all")
    uri = URI.parse(scoped)
    params = URI.decode_query(uri.query || "")

    assert uri.path == "/studio/agents"
    assert params["status"] == "running"
    assert params["node"] == "all"
  end

  test "process node param storage" do
    assert :ok == Scope.put_process_node_param("all")
    assert Scope.current_node_param() == "all"
  end
end
