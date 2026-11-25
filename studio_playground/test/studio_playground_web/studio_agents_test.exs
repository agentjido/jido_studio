defmodule StudioPlaygroundWeb.StudioAgentsTest do
  use StudioPlaygroundWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias StudioPlaygroundWeb.{Endpoint, StudioHostRouter}

  @runtime StudioPlayground.AgentsTestRuntime
  @list_path "/operations/readonly/agents"

  test "the playground starts a demo counter from an empty Agents page", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/studio/agents")
    assert render_async(view) =~ "No resident instances"
    assert has_element?(view, "#studio-agents-host-action button", "Start demo agent")

    response = post(conn, "/studio/agents/demo")
    assert redirected_to(response, 303) == "/studio/agents"
    assert pid = Jido.whereis_agent(StudioPlayground.Jido, "demo-counter")
    on_exit(fn -> Jido.stop_agent(StudioPlayground.Jido, pid) end)

    assert {:ok, view, _html} = live(recycle(response), "/studio/agents")
    assert render_async(view) =~ "demo-counter"
    assert has_element?(view, "#studio-agent-rows a", "demo-counter")

    assert conn |> post("/studio/agents/demo") |> redirected_to(303) == "/studio/agents"
    assert Jido.whereis_agent(StudioPlayground.Jido, "demo-counter") == pid
  end

  test "sends the typed demo signal and displays the committed turn and its trace", %{conn: conn} do
    assert :ok = StudioPlayground.DemoAgents.start_demo()
    pid = Jido.whereis_agent(StudioPlayground.Jido, "demo-counter")
    on_exit(fn -> Jido.stop_agent(StudioPlayground.Jido, pid) end)

    assert {:ok, view, _html} = live(conn, "/studio/agents/demo-counter")
    render_async(view)
    assert has_element?(view, "#studio-agent-signal-actions button", "Increment counter")
    assert has_element?(view, "#studio-agent-signal-actions pre", "%{amount: 1}")

    render_click(view, "send_signal", %{"type" => "demo.counter.unknown"})
    refute has_element?(view, "#studio-agent-turn")

    render_click(view, "send_signal", %{"type" => "demo.counter.increment", "amount" => 8})
    render_async(view, 2_000)
    assert has_element?(view, "#studio-agent-turn dd", "Committed")
    assert has_element?(view, "#studio-agent-turn dd", "demo.counter.updated")
    assert has_element?(view, "#studio-agent-turn dt", "Count")
    assert has_element?(view, "#studio-agent-trace li", "Turn started")
    assert has_element?(view, "#studio-agent-trace li", "Action finished")
    assert has_element?(view, "#studio-agent-trace li", "State committed")
    assert has_element?(view, "#studio-agent-trace li", "Turn settled")
    assert %{agent: %{state: %{count: 1}}, agent_revision: 1} = Jido.AgentServer.snapshot(pid)
  end

  test "a read-only mount cannot send the same signal", %{conn: conn} do
    start_supervised!({Jido, name: @runtime})

    assert {:ok, pid} =
             Jido.start_agent(@runtime, StudioPlayground.DemoCounter,
               id: "demo-counter",
               partition: "review"
             )

    assert {:ok, view, _html} = conn |> host_get(@list_path <> "/demo-counter") |> live()
    render_async(view)
    refute has_element?(view, "#studio-agent-signal-actions")
    render_click(view, "send_signal", %{"type" => "demo.counter.increment"})
    refute has_element?(view, "#studio-agent-turn")
    assert %{agent: %{state: %{count: 0}}} = Jido.AgentServer.snapshot(pid)
  end

  test "loads resident agents and opens an exact instance ID inside the host mount", %{conn: conn} do
    start_supervised!({Jido, name: @runtime})
    id = "team/agent+100%?#"
    start_agent!(id, "review")
    start_agent!("private-instance", "private")

    scope = %{"runtime" => "ignored", "node" => "ignored"}
    path = @list_path <> "?" <> URI.encode_query(scope)
    response = host_get(conn, path)
    assert html_response(response, 200) =~ "Loading instances"

    assert {:ok, view, _html} = live(response)
    render_async(view)

    detail = @list_path <> "/team%2Fagent%2B100%25%3F%23?" <> URI.encode_query(scope)
    assert has_element?(view, "a[href='#{detail}']", id)
    refute has_element?(view, "#studio-agents-host-action")
    assert has_element?(view, "#studio-agent-list .studio-card-header p", "1 instance")
    refute has_element?(view, "#studio-agent-list a", "private-instance")

    assert {:ok, detail_view, _html} = conn |> host_get(detail) |> live()
    html = render_async(detail_view)
    assert has_element?(detail_view, "h1", id)
    assert has_element?(detail_view, "#studio-agent-status dd", "Idle")
    assert has_element?(detail_view, "#studio-agent-snapshot h3", "Review counter")
    assert has_element?(detail_view, "#studio-agent-snapshot dt", "Agent revision")
    refute html =~ "fixture-state-value"
    assert has_element?(detail_view, "#studio-navigation a[aria-current=page]", "Agents")
    assert has_element?(detail_view, "nav[aria-label='Agent breadcrumb'] a[href='#{path}']")

    legacy_path = @list_path <> "/instance?" <> URI.encode_query(Map.put(scope, "id", id))
    assert conn |> host_get(legacy_path) |> redirected_to() == detail
  end

  test "keeps dot segments and literal escape prefixes distinct in agent URLs", %{conn: conn} do
    start_supervised!({Jido, name: @runtime})

    for {id, segment} <- [{".", "~."}, {"..", "~.."}, {"~.", "~~."}] do
      start_agent!(id, "review")
      assert {:ok, view, _html} = conn |> host_get(@list_path <> "/" <> segment) |> live()
      render_async(view)
      assert has_element?(view, "h1", id)
      assert has_element?(view, "#studio-agent-snapshot h3", "Review counter")

      assert has_element?(
               view,
               "#studio-turn-history-link[href='#{@list_path}/#{segment}/turns']"
             )
    end
  end

  test "distinguishes a stopped runtime from an empty partition and retries without a reload",
       %{conn: conn} do
    assert {:ok, view, _html} = conn |> host_get(@list_path) |> live()
    assert render_async(view) =~ "Studio could not reach the configured Jido runtime."

    start_supervised!({Jido, name: @runtime})
    view |> element("#studio-agent-list-retry") |> render_click()
    assert render_async(view) =~ "No resident instances"

    start_agent!("new-agent", "review")
    view |> element("#studio-refresh-agents") |> render_click()
    assert render_async(view) =~ "new-agent"

    assert :ok = Jido.stop_agent(@runtime, "new-agent", partition: "review")
    view |> element("#studio-refresh-agents") |> render_click()
    assert render_async(view) =~ "No resident instances"
    refute has_element?(view, "#studio-agent-rows a", "new-agent")
  end

  test "keeps status visible while a starting agent's snapshot fails and retries that panel",
       %{conn: conn} do
    Process.register(self(), __MODULE__)
    start_supervised!({Jido, name: @runtime})

    assert {:ok, pid} =
             Jido.start_agent(@runtime, StudioPlayground.StartingAgent,
               id: "starting",
               partition: "review"
             )

    assert_receive {:agent_starting, boot}, 2_000

    response = host_get(conn, @list_path <> "/starting")
    document = response |> html_response(200) |> LazyHTML.from_fragment()

    assert LazyHTML.query(document, "#studio-agent-status .studio-read-loading")
           |> LazyHTML.text() =~
             "Loading runtime status"

    assert LazyHTML.query(document, "#studio-agent-snapshot .studio-read-loading")
           |> LazyHTML.text() =~ "Loading committed snapshot"

    assert {:ok, view, _html} = live(response)
    assert render_async(view) =~ "The instance is still starting."
    assert has_element?(view, "#studio-agent-status dd", "Activating")

    send(boot, :finish_start)
    assert :ok = Jido.AgentServer.await_ready(pid)

    view |> element("#studio-agent-snapshot-retry") |> render_click()
    assert render_async(view) =~ "Starting counter"
    assert has_element?(view, "#studio-agent-status dd", "Activating")
    refute has_element?(view, "#studio-agent-snapshot-retry")

    view |> element("#studio-refresh-instance") |> render_click()
    render_async(view)
    assert has_element?(view, "#studio-agent-status dd", "Active")
  end

  test "does not read a different partition or expose agent data to a forbidden host session",
       %{conn: conn} do
    start_supervised!({Jido, name: @runtime})
    start_agent!("private-instance", "private")

    assert {:ok, view, _html} =
             conn |> host_get(@list_path <> "/private-instance?partition=private") |> live()

    assert render_async(view) =~ "This instance is no longer resident in this partition."
    refute has_element?(view, "#studio-agent-snapshot h3")

    forbidden = init_test_session(conn, studio_test_access: "forbidden")

    assert forbidden
           |> host_get("/operations/inspect/agents/anything")
           |> redirected_to() ==
             "/login"
  end

  defp start_agent!(id, partition) do
    definition =
      Jido.Agent.define!(%{
        name: "Review counter",
        description: "Counts items for review.",
        schema: Jido.Joi.object(%{value: Jido.Joi.string()}),
        initial_state: %{value: "fixture-state-value"}
      })

    assert {:ok, pid} = Jido.start_agent(@runtime, definition, id: id, partition: partition)
    pid
  end

  defp host_get(conn, path) do
    conn
    |> init_test_session(%{})
    |> put_private(:phoenix_endpoint, Endpoint)
    |> dispatch(StudioHostRouter, :get, path)
  end
end
