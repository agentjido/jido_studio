defmodule StudioPlaygroundWeb.GoliathDefinitionLiveTest do
  use StudioPlaygroundWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @path "/studio/definitions/goliath"

  test "opens the read-only definition and patches between routes", %{conn: conn} do
    assert {:ok, agents, _html} = live(conn, "/studio/agents")
    assert has_element?(agents, "#studio-agents-definition[href='#{@path}']")

    assert {:ok, view, _html} = live(conn, @path)
    assert has_element?(view, "#studio-definition h1", "Goliath")
    assert has_element?(view, "#studio-definition-state-title", "Initial state")
    assert has_element?(view, "#studio-definition dd", "INC-042")

    assert has_element?(
             view,
             "#studio-definition-routes a[aria-current]",
             "goliath.review.requested"
           )

    refute has_element?(
             view,
             "#studio-definition form[method='post'] button, #studio-definition [phx-click]"
           )

    view
    |> form("#studio-definition-filter", signals: %{query: "evidence"})
    |> render_change()

    assert has_element?(view, "#studio-definition-routes a", "goliath.evidence.collected")
    refute has_element?(view, "#studio-definition-routes a", "goliath.incident.open")

    view
    |> element("#studio-definition-routes a", "goliath.evidence.collected")
    |> render_click()

    assert_patch(view, @path <> "?signal=goliath.evidence.collected")
    assert has_element?(view, "#studio-definition-inspector", "Commit from output.next_state")
    assert has_element?(view, "#studio-definition-inspector", "goliath.evidence.recorded")
    refute Jido.whereis_agent(StudioPlayground.Jido, "lab/goliath")
  end

  test "renders nested parallel work and wait options from a flow route", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, @path <> "?signal=goliath.review.requested")
    assert has_element?(view, "#studio-definition-inspector-title", "Request review")
    assert has_element?(view, "[data-level='1'] h4", "Assemble packet")
    assert has_element?(view, "[data-level='1'] [aria-label='Depends on'] li", "Recall decisions")
    assert has_element?(view, "[data-level='2'] h4", "Decision")
    assert has_element?(view, "[data-level='2'] [aria-label='Depends on'] li", "Assemble packet")
    assert has_element?(view, "details summary", "Expand flow")
    assert has_element?(view, "details .studio-definition-kind", "Parallel")
    assert has_element?(view, "details li", "Jido.Connect.GitHub.Actions.GetPullRequest")
    assert has_element?(view, "details li", "Jido.Connect.Zendesk.Actions.GetTicket")
    assert has_element?(view, "#studio-definition-inspector", "goliath.review.approved")
    assert has_element?(view, "#studio-definition-inspector", "After 15 min")
  end

  test "follows declared topology and schedule links without starting Goliath", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, @path <> "?signal=goliath.evidence.collect")
    view |> element("#studio-definition-inspector a", "View signal topology") |> render_click()

    assert has_element?(view, "#studio-definition-topology", "4 members · 7 declared connections")
    assert has_element?(view, ".studio-definition-destinations li", "Broadcast · ×3")
    assert has_element?(view, ".studio-definition-actors li", "Jido.Lab.Goliath.AuditDesk")

    view |> element("nav[aria-label='Definition views'] a", "Resources") |> render_click()

    for resource <- ["Chat", "Connect", "Harness", "Realms", "Memory"] do
      assert has_element?(view, "#studio-definition-resources h3", resource)
    end

    view
    |> element(".studio-definition-schedules a", "goliath.review.heartbeat")
    |> render_click()

    assert_patch(view, @path <> "?signal=goliath.review.heartbeat")
    assert has_element?(view, "#studio-definition-inspector-title", "goliath.review.heartbeat")
    refute Jido.whereis_agent(StudioPlayground.Jido, "lab/goliath")
  end

  test "inspects flow nodes, connections, and the nested parallel flow on the canvas", %{
    conn: conn
  } do
    assert {:ok, view, _html} =
             live(conn, @path <> "?signal=goliath.review.requested&view=canvas")

    view |> element("[data-canvas-node='step:assemble_packet']") |> render_click()
    assert has_element?(view, "#studio-canvas-inspector h3", "Assemble packet")
    assert has_element?(view, "#studio-canvas-inspector dd", "recall_decisions.result.recall")

    view
    |> element("#studio-canvas-inspector button", "Recall decisions → Assemble packet")
    |> render_click()

    assert has_element?(view, "#studio-canvas-inspector h3", "Dependency")
    assert has_element?(view, "#studio-canvas-inspector dd", "Recall decisions")

    view |> element("[data-canvas-node='step:collect_sources']") |> render_click()
    view |> element("#studio-canvas-inspector a", "Open flow") |> render_click()

    assert has_element?(view, "#studio-canvas-title", "Goliath collect sources")
    assert has_element?(view, "[data-canvas-node='step:provider_reads:pull_request']")
    assert has_element?(view, "[data-canvas-node='step:provider_reads:support_ticket']")

    assert has_element?(
             view,
             "path[data-from='step:provider_reads:pull_request'][data-to='output']"
           )

    assert has_element?(
             view,
             "path[data-from='step:provider_reads:support_ticket'][data-to='output']"
           )
  end

  test "the topology canvas uses declared members and highlights the selected signal", %{
    conn: conn
  } do
    path = @path <> "?signal=goliath.evidence.collect&view=canvas&graph=topology"
    assert {:ok, view, _html} = live(conn, path)
    assert has_element?(view, "[data-canvas-node='agent:evidence_workers']", "×3 declared")

    assert has_element?(
             view,
             "path[data-from='bus:goliath_audit'][data-to='agent:evidence_workers'][data-highlight]"
           )

    view |> element("[data-canvas-node='agent:evidence_workers']") |> render_click()

    assert has_element?(view, "#studio-canvas-inspector h3", "Evidence workers")
    assert has_element?(view, "#studio-canvas-inspector button", "Evidence workers → Audit")
    refute Jido.whereis_agent(StudioPlayground.Jido, "lab/goliath")
  end
end
