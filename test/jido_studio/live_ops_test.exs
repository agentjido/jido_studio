defmodule JidoStudio.LiveOpsTest do
  use ExUnit.Case, async: true

  alias JidoStudio.LiveOps

  test "normalizes scope and builds topics" do
    scope = LiveOps.normalized_scope(%{"project_id" => "p1", "user_id" => "u1", "ignored" => "x"})
    assert scope.project_id == "p1"
    assert scope.user_id == "u1"

    assert LiveOps.agent_list_topic(scope) =~ "live_ops:agents:"
    assert LiveOps.agent_topic(scope, "agent-1") =~ "live_ops:agent:agent-1:"
  end
end
