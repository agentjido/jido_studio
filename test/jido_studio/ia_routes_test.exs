defmodule JidoStudio.IARoutesTest do
  use JidoStudio.ConnCase, async: true

  test "root route renders HomeLive", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio")

    assert html =~ "Your agent fleet at a glance"
    assert html =~ "What this page is for"
    assert html =~ "Click to play"
    assert html =~ "Calculator Agent"
    assert html =~ "Open Calculator Example"
  end

  test "catalog route renders canonical catalog page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/catalog")

    assert html =~ "Agent Catalog"
    assert html =~ "What your agents can do"
  end

  test "registry route redirects to catalog preserving query params", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: to_path}}} =
             live(conn, "/studio/registry?tab=actions&q=tool&selected=my-action&node=all")

    uri = URI.parse(to_path)

    assert uri.path == "/studio/catalog"

    params = URI.decode_query(uri.query || "")
    assert params["tab"] == "actions"
    assert params["q"] == "tool"
    assert params["selected"] == "my-action"
    assert params["node"] == "all"
  end

  test "sidebar core nav order includes catalog above settings", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio")

    home_idx = index_of(html, ">Home<")
    agents_idx = index_of(html, ">Agents<")
    catalog_idx = index_of(html, ">Catalog<")
    activity_idx = index_of(html, ">Activity<")
    diagnostics_idx = index_of(html, ">Diagnostics<")
    settings_idx = index_of(html, ">Settings<")
    about_idx = index_of(html, ">About<")

    assert home_idx < agents_idx
    assert agents_idx < catalog_idx
    assert catalog_idx < activity_idx
    assert activity_idx < diagnostics_idx
    assert diagnostics_idx < settings_idx
    assert settings_idx < about_idx
  end

  test "node query param is propagated in sidebar links", %{conn: conn} do
    node = URI.encode_www_form(to_string(Node.self()))

    {:ok, _view, html} = live(conn, "/studio/catalog?node=#{node}")

    assert html =~ "/studio/agents?node=#{node}"
    assert html =~ "/studio/catalog?node=#{node}"
    assert html =~ "/studio/settings?node=#{node}"
  end

  test "only one core nav item is active per page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/agents?node=all")

    marker =
      "span class=\"absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-4 bg-js-primary rounded-r\""

    active_marker_count =
      String.split(html, marker)
      |> length()
      |> Kernel.-(1)

    assert active_marker_count == 1
  end

  defp index_of(haystack, needle) when is_binary(haystack) and is_binary(needle) do
    case :binary.match(haystack, needle) do
      {index, _len} -> index
      :nomatch -> flunk("expected to find #{inspect(needle)} in response HTML")
    end
  end
end
