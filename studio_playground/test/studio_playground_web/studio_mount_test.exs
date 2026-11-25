defmodule StudioPlaygroundWeb.StudioMountTest do
  use StudioPlaygroundWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StudioPlaygroundWeb.{Endpoint, StudioHostRouter}

  test "mounts Studio inside the playground router", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/studio")
    assert has_element?(view, ~s(#studio-navigation a[aria-current=page][href="/studio"]))
    assert has_element?(view, "#studio-sidebar-toggle[aria-expanded=true]")
    assert has_element?(view, "#studio-theme-toggle[aria-pressed=false]")
    assert has_element?(view, "#studio-main #studio-overview")
    assert has_element?(view, ~s(#studio-navigation a[href="/studio/components"]))
  end

  test "preserves scoped mount paths, safe query keys, and the active example across patches",
       %{conn: conn} do
    conn =
      host_get(
        conn,
        "/operations/inspect/components?node=worker%40local&runtime=dev&tab=empty&private=hidden"
      )

    assert {:ok, view, _html} = live(conn)

    assert has_element?(
             view,
             ~s(#studio-navigation a[aria-current=page][href="/operations/inspect/components?node=worker%40local&runtime=dev"])
           )

    assert has_element?(
             view,
             ~s(#studio-navigation a[href="/operations/inspect?node=worker%40local&runtime=dev"])
           )

    assert has_element?(view, ".studio-empty")
    refute has_element?(view, ".studio-table")
    view |> element(".studio-tabs a", "Instances") |> render_click()
    assert_patch(view, "/operations/inspect/components?node=worker%40local&runtime=dev")
    assert has_element?(view, ".studio-table tbody tr")
  end

  test "applies host CSP nonces and supports a second mount with the showcase disabled",
       %{conn: conn} do
    response = host_get(conn, "/operations/inspect")
    html = html_response(response, 200)
    assert get_resp_header(response, "content-security-policy") != []
    assert html =~ ~s(id="studio-shell-styles" nonce="style-nonce")
    assert html =~ ~s(id="studio-shell-script" nonce="script-nonce")

    assert {:ok, view, html} = conn |> host_get("/operations/readonly") |> live()
    assert html =~ ~s(id="studio-shell-script" nonce="style-nonce")
    refute has_element?(view, "#studio-navigation a[aria-label=Components]")
  end

  test "combines search and status filters and retains them across review states", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/studio/components?runtime=dev")

    view
    |> form("#studio-instance-filters", filters: %{q: "  SIGNAL ", status: "online"})
    |> render_submit()

    assert_patch(view, "/studio/components?q=SIGNAL&runtime=dev&status=online")
    assert has_element?(view, ".studio-table [scope=row]", "Signal Runner")
    refute has_element?(view, ".studio-table [scope=row]", "Scheduler")

    view |> element(".studio-tabs a", "Unavailable") |> render_click()
    assert_patch(view, "/studio/components?q=SIGNAL&runtime=dev&status=online&tab=unavailable")
    assert has_element?(view, ".studio-notice", "Runtime unavailable")

    view |> element(".studio-notice a", "Show sample instances") |> render_click()
    assert_patch(view, "/studio/components?q=SIGNAL&runtime=dev&status=online")
    assert has_element?(view, "#filters_q[value=SIGNAL]")

    view
    |> form("#studio-instance-filters", filters: %{q: "SIGNAL", status: "offline"})
    |> render_submit()

    assert has_element?(view, ".studio-empty", "No matching instances")
    refute has_element?(view, ".studio-table")

    view |> element(".studio-empty a", "Clear filters") |> render_click()
    assert_patch(view, "/studio/components?runtime=dev")
    assert has_element?(view, ".studio-table [scope=row]", "Report Agent")
  end

  test "redirects forbidden hosts on both initial requests and the connected mount", %{conn: conn} do
    forbidden = init_test_session(conn, studio_test_access: "forbidden")
    assert forbidden |> host_get("/operations/inspect/components") |> redirected_to() == "/login"

    disconnected = init_test_session(conn, studio_test_access: "disconnect_only")
    response = host_get(disconnected, "/operations/inspect/components")
    assert html_response(response, 200) =~ "Design components"
    assert {:error, {:redirect, %{to: "/login"}}} = live(response)
  end

  defp host_get(conn, path) do
    conn
    |> init_test_session(%{})
    |> put_private(:phoenix_endpoint, Endpoint)
    |> dispatch(StudioHostRouter, :get, path)
  end
end
