defmodule JidoStudio.PageCopyContractTest do
  use JidoStudio.ConnCase, async: true

  test "home copy aligns to primary question and provides next action", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio")

    assert html =~ "Are your agents healthy right now?"
    assert html =~ "What this page is for: review fleet health"
    assert html =~ "Open Agents"
  end

  test "agents copy aligns to primary question", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/agents")

    assert html =~ "Which agents are running and what should you do next?"
    assert html =~ "Active Instances"
  end

  test "guide copy aligns to onboarding question and next action", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/guide")

    assert html =~ "How do you get value from Studio in under five minutes?"
    assert html =~ "What this page is for: choose a guided workflow"
    assert html =~ "Start Tour"
  end

  test "catalog copy aligns to capability discovery question", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/catalog")

    assert html =~ "What can your agents do across runtime and discovery?"
    assert html =~ "What this page is for: discover capabilities"
    assert html =~ "Schema Hint"
  end

  test "activity copy aligns to recency question", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/activity")

    assert html =~ "What happened recently across your agents?"
    assert html =~ "What this page is for: monitor the live stream"
    assert html =~ "Signals"
  end

  test "diagnostics copy aligns to failure triage question", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/diagnostics")

    assert html =~ "Why did this fail in the selected runtime and node?"
    assert html =~ "What this page is for: validate cluster connectivity"
    assert html =~ "Timeline (Advanced)"
  end

  test "settings copy aligns to configuration question", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/settings")

    assert html =~ "How is Studio configured for this runtime?"
    assert html =~ "What this page is for: verify setup state"
    assert html =~ "Re-test"
  end

  test "about copy aligns to product narrative and links", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/about")

    assert html =~ "What Jido Studio is and where to go next"
    assert html =~ "What this page is for: understand the product boundary"
    assert html =~ "Community and Resources"
  end
end
