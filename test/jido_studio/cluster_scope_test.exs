defmodule JidoStudio.Cluster.ScopeTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Cluster.Scope
  alias JidoStudio.RuntimeScope

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

  test "with_scope_query includes runtime key when present in process" do
    options = [%{key: "primary", module: JidoStudio.TestJido, label: "Primary"}]
    :ok = RuntimeScope.put_process_runtime_key("primary", options)

    scoped = Scope.with_scope_query("/studio/agents?status=running", "all")
    params = scoped |> URI.parse() |> Map.get(:query) |> URI.decode_query()

    assert params["status"] == "running"
    assert params["node"] == "all"
    assert params["runtime"] == "primary"

    :ok = RuntimeScope.put_process_runtime_key(nil, options)
  end
end
