defmodule JidoStudio.ScopeQueryTest do
  use ExUnit.Case, async: true

  alias JidoStudio.ScopeQuery

  test "preserves existing params and includes runtime + node" do
    scoped = ScopeQuery.with_scope_query("/studio/agents?status=running", "primary", "all")
    uri = URI.parse(scoped)
    params = URI.decode_query(uri.query || "")

    assert uri.path == "/studio/agents"
    assert params["status"] == "running"
    assert params["runtime"] == "primary"
    assert params["node"] == "all"
  end

  test "drops runtime query when runtime key is nil" do
    scoped = ScopeQuery.with_scope_query("/studio/catalog?runtime=old&tab=agents", nil, "all")
    params = URI.parse(scoped).query |> URI.decode_query()

    assert params["tab"] == "agents"
    assert params["node"] == "all"
    refute Map.has_key?(params, "runtime")
  end

  test "handles malformed existing query safely" do
    scoped = ScopeQuery.with_scope_query("/studio/activity?bad=%", "primary", "all")
    uri = URI.parse(scoped)
    params = URI.decode_query(uri.query || "")

    assert uri.path == "/studio/activity"
    assert params["runtime"] == "primary"
    assert params["node"] == "all"
  end
end
