defmodule JidoStudio.LiveOpsTest do
  use ExUnit.Case, async: true

  alias JidoStudio.LiveOps

  setup do
    old_live_ops = Application.get_env(:jido_studio, :live_ops, [])

    on_exit(fn ->
      Application.put_env(:jido_studio, :live_ops, old_live_ops)
    end)

    :ok
  end

  test "normalizes scope and builds topics" do
    scope = LiveOps.normalized_scope(%{"project_id" => "p1", "user_id" => "u1", "ignored" => "x"})
    assert scope.project_id == "p1"
    assert scope.user_id == "u1"

    assert LiveOps.agent_list_topic(scope) =~ "live_ops:agents:"
    assert LiveOps.agent_topic(scope, "agent-1") =~ "live_ops:agent:agent-1:"
  end

  test "live_ops defaults include event stream and polling controls" do
    Application.put_env(:jido_studio, :live_ops, [])

    assert LiveOps.event_stream_limit() == 100
    assert LiveOps.agent_list_poll_ms() == 2_000
    assert LiveOps.viewer_tracking?() == true
  end

  test "viewer APIs no-op safely without presence module" do
    Application.put_env(:jido_studio, :live_ops,
      enabled: true,
      viewer_tracking: true,
      presence_module: false
    )

    assert LiveOps.subscribe_viewers("inst-1") == :ok
    assert LiveOps.track_viewer("inst-1", "viewer-1", %{}) == :ok
    assert LiveOps.untrack_viewer("inst-1", "viewer-1") == :ok
    assert LiveOps.viewer_count("inst-1") == 0
  end

  test "presence defaults to built-in module when not configured" do
    Application.put_env(:jido_studio, :live_ops, enabled: true, viewer_tracking: true)

    assert LiveOps.presence_available?()
  end
end
