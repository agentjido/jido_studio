defmodule StudioPlaygroundWeb.StudioOverviewTest do
  use StudioPlaygroundWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias StudioPlaygroundWeb.{Endpoint, StudioHostRouter}

  @runtime StudioPlayground.AgentsTestRuntime
  @overview_path "/operations/readonly"
  @partition "review"

  test "shows mount instructions when the host has no configured runtime", %{conn: conn} do
    assert {:ok, view, _html} = conn |> host_get("/operations/inspect") |> live()
    assert has_element?(view, "#studio-overview-runtime-status", "No runtime configured")
    assert has_element?(view, "#studio-overview-mount-instructions summary")
    assert has_element?(view, "#studio-overview-mount-instructions code", "jido: MyApp.Jido")
    refute has_element?(view, "#studio-overview-instances")
    refute has_element?(view, "#studio-overview-refresh")
  end

  test "shows the total and first five IDs from the host partition with scoped links", %{
    conn: conn
  } do
    start_supervised!({Jido, name: @runtime})
    first = "a/team+agent%?#"

    for id <- ["zeta", "epsilon", "delta", "charlie", "bravo", first] do
      start_agent!(id, @partition)
    end

    start_agent!("a-other-partition", "private")

    scope = %{"runtime" => "other-runtime", "node" => "other-node"}
    query = URI.encode_query(Map.put(scope, "partition", "private"))

    assert {:ok, view, _html} = conn |> host_get(@overview_path <> "?" <> query) |> live()
    render_async(view)

    assert has_element?(view, "#studio-overview-scope code", inspect(@runtime))
    assert has_element?(view, "#studio-overview-scope span", @partition)
    refute has_element?(view, "#studio-scope", "other-runtime")
    refute has_element?(view, "#studio-scope", "other-node")
    assert has_element?(view, "#studio-overview-runtime-status", "Runtime reachable")
    assert has_element?(view, "#studio-overview-runtime time[datetime$='Z']")
    assert has_element?(view, "#studio-overview-instance-count", "6 in this partition")
    assert has_element?(view, "#studio-overview-instances p", "Showing 5 of 6")

    for {id, position} <- Enum.with_index([first, "bravo", "charlie", "delta", "epsilon"], 1) do
      assert has_element?(view, "#studio-overview-instance-rows li:nth-child(#{position}) a", id)
    end

    refute has_element?(view, "#studio-overview-instance-rows li:nth-child(6)")

    index_href = @overview_path <> "/agents?" <> URI.encode_query(scope)

    detail_href =
      @overview_path <> "/agents/a%2Fteam%2Bagent%25%3F%23?" <> URI.encode_query(scope)

    assert has_element?(view, "#studio-overview-all-agents[href='#{index_href}']")
    assert has_element?(view, "#studio-overview-instance-rows a[href='#{detail_href}']", first)
  end

  test "retries a stopped runtime and refreshes the same page as the inventory changes", %{
    conn: conn
  } do
    response = host_get(conn, @overview_path)

    assert response
           |> html_response(200)
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#studio-overview-runtime-status")
           |> LazyHTML.text() =~ "Checking runtime"

    assert {:ok, view, _html} = live(response)
    render_async(view)
    assert has_element?(view, "#studio-overview-runtime-status", "Runtime unavailable")
    assert has_element?(view, "#studio-overview-refresh", "Retry")
    refute has_element?(view, "#studio-overview-instance-count")
    refute has_element?(view, "#studio-overview-runtime time")

    start_supervised!({Jido, name: @runtime}, id: @runtime)
    view |> element("#studio-overview-refresh", "Retry") |> render_click()
    render_async(view)
    assert has_element?(view, "#studio-overview-runtime-status", "Runtime reachable")
    assert has_element?(view, "#studio-overview-instance-count", "0 in this partition")
    assert has_element?(view, "#studio-overview-instances .studio-empty", "No resident instances")

    start_agent!("new-agent", @partition)
    view |> element("#studio-overview-refresh", "Refresh") |> render_click()
    render_async(view)
    assert has_element?(view, "#studio-overview-instance-count", "1 in this partition")
    assert has_element?(view, "#studio-overview-instance-rows a", "new-agent")

    stop_supervised!(@runtime)
    view |> element("#studio-overview-refresh", "Refresh") |> render_click()
    render_async(view)
    assert has_element?(view, "#studio-overview-runtime-status", "Runtime unavailable")
    assert has_element?(view, "#studio-overview-runtime p", "Last successful check")
    refute has_element?(view, "#studio-overview-instances")
  end

  defp start_agent!(id, partition) do
    assert {:ok, _pid} =
             Jido.start_agent(@runtime, StudioPlayground.DemoCounter,
               id: id,
               partition: partition
             )
  end

  defp host_get(conn, path) do
    conn
    |> init_test_session(%{})
    |> put_private(:phoenix_endpoint, Endpoint)
    |> dispatch(StudioHostRouter, :get, path)
  end
end
