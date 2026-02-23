defmodule JidoStudio.GuideLiveTest do
  use JidoStudio.ConnCase, async: true

  test "renders guided tour flows and controls", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/guide")

    assert html =~ "Guide"
    assert html =~ "How do you get value from Studio in under five minutes?"
    assert html =~ "First 5 Minutes"
    assert html =~ "Setup + First Interaction"
    assert html =~ "Incident Triage"
    assert html =~ "Start Tour"
    assert html =~ "data-js-tour-flow="
    assert html =~ "data-js-tour-start="
    assert html =~ "data-js-tour-resume="
    assert html =~ "data-js-tour-replay="
    assert html =~ "Why Discovered Counts Can Be High"
    assert html =~ "Discovered modules"
    assert html =~ "Running instances"
    assert html =~ "Active instances"
    assert html =~ "Open Starter In Agents"
  end
end
