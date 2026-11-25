defmodule StudioPlaygroundWeb.StudioTurnsTest do
  use StudioPlaygroundWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias StudioPlayground.DemoCounter
  alias StudioPlayground.DemoCounter.Increment
  alias StudioPlaygroundWeb.{Endpoint, StudioHostRouter}

  @runtime StudioPlayground.AgentsTestRuntime
  @id "history-agent"
  @path "/operations/readonly/agents/#{@id}/turns"

  test "shows and selects real settled turns from the host partition", %{conn: conn} do
    start_supervised!({Jido, name: @runtime})
    worker = start_counter!("review")
    other_worker = start_counter!("private")

    assert {:ok, view, _html} = conn |> host_get(@path) |> live()
    render_async(view)
    assert has_element?(view, "#studio-turn-list .studio-empty", "No turns recorded")

    assert {:ok, %{turn_id: committed_id, status: :committed}} =
             Jido.AgentServer.call(worker, Increment.new!(%{amount: 2}))

    invalid = Jido.Signal.new!("demo.counter.missing", %{}, source: "/test")

    assert {:ok, %{turn_id: failed_id, status: :failed}} = Jido.AgentServer.call(worker, invalid)

    assert {:ok, %{turn_id: other_id, status: :committed}} =
             Jido.AgentServer.call(other_worker, Increment.new!(%{amount: 3}))

    view |> element("#studio-refresh-turns") |> render_click()
    render_async(view)

    assert has_element?(view, "#studio-turn-rows tr:first-child a code", failed_id)
    assert has_element?(view, "#studio-turn-rows tr:first-child td", "Failed")
    assert has_element?(view, "#studio-turn-rows tr:nth-child(2) a code", committed_id)
    assert has_element?(view, "#studio-turn-rows tr:nth-child(2) td", "Committed")
    refute has_element?(view, "#studio-turn-rows a code", other_id)

    view |> element("#studio-turn-rows tr:nth-child(2) a") |> render_click()
    assert_patch(view, @path <> "?turn=" <> committed_id)
    assert has_element?(view, "#studio-history-turn dd code", committed_id)
    assert has_element?(view, "#studio-history-turn dd code", "demo.counter.increment")

    assert {:ok, reloaded, _html} = conn |> host_get(@path <> "?turn=" <> failed_id) |> live()
    render_async(reloaded)
    assert has_element?(reloaded, "#studio-history-turn dd code", failed_id)
    assert has_element?(reloaded, "#studio-history-turn dd", "Evaluate")
    assert has_element?(reloaded, "#studio-history-turn dd", "No")

    url = @path <> "?turn=" <> other_id <> "&partition=private"
    assert {:ok, crossed, _html} = conn |> host_get(url) |> live()
    render_async(crossed)
    assert has_element?(crossed, ".studio-notice", "Selected turn unavailable")
    refute has_element?(crossed, "#studio-history-turn")
  end

  test "applies the host authorization before opening a history link", %{conn: conn} do
    response =
      conn
      |> init_test_session(studio_test_access: "forbidden")
      |> host_get("/operations/inspect/agents/history-agent/turns")

    assert redirected_to(response) == "/login"
  end

  defp start_counter!(partition) do
    assert {:ok, worker} = Jido.start_agent(@runtime, DemoCounter, id: @id, partition: partition)
    worker
  end

  defp host_get(conn, path) do
    conn
    |> init_test_session(%{})
    |> put_private(:phoenix_endpoint, Endpoint)
    |> dispatch(StudioHostRouter, :get, path)
  end
end
