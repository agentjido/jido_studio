defmodule JidoStudio.HomeLiveTest do
  use JidoStudio.ConnCase, async: true

  test "renders attention and setup above fleet metrics with example below core modules", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/studio")

    attention_idx = index_of(html, "Attention Needed")
    setup_idx = index_of(html, "Setup Assistant")
    metrics_idx = index_of(html, "Agents Online")
    top_agents_idx = index_of(html, "Top Agents")
    recent_idx = index_of(html, "Recent Activity")
    example_idx = index_of(html, "Open Calculator Example")

    assert attention_idx < metrics_idx
    assert setup_idx < metrics_idx
    assert top_agents_idx < recent_idx
    assert recent_idx < example_idx
  end

  test "renders setup and example visibility controls", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio")

    assert html =~ "data-js-home-setup"
    assert html =~ "data-js-home-setup-show"
    assert html =~ "data-js-home-example"
    assert html =~ "data-js-home-example-show"
  end

  defp index_of(haystack, needle) when is_binary(haystack) and is_binary(needle) do
    case :binary.match(haystack, needle) do
      {index, _len} -> index
      :nomatch -> flunk("expected to find #{inspect(needle)} in response HTML")
    end
  end
end
