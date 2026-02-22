defmodule JidoStudio.SidebarScopeTest do
  use JidoStudio.ConnCase, async: false

  setup do
    previous_jido_instances = Application.get_env(:jido_studio, :jido_instances, :__unset__)

    on_exit(fn ->
      case previous_jido_instances do
        :__unset__ -> Application.delete_env(:jido_studio, :jido_instances)
        value -> Application.put_env(:jido_studio, :jido_instances, value)
      end
    end)

    :ok
  end

  test "single runtime hides runtime selector and keeps advanced scope collapsed", %{conn: conn} do
    Application.delete_env(:jido_studio, :jido_instances)

    {:ok, _view, html} = live(conn, "/studio")

    assert html =~ "Scope"
    refute html =~ "Runtime Selector"
    assert html =~ "Advanced Scope"
    assert html =~ "hidden group-data-[advanced-scope-state=expanded]:block"
  end

  test "multi-runtime shows selector and propagates runtime + node in nav links", %{conn: conn} do
    Application.put_env(:jido_studio, :jido_instances, [
      %{key: "primary", module: JidoStudio.TestJido, label: "Primary"},
      %{key: "secondary", module: JidoStudio.AgentRegistry, label: "Secondary"}
    ])

    {:ok, _view, html} = live(conn, "/studio?runtime=secondary&node=all")

    assert html =~ "Runtime Selector"
    assert html =~ ~s(value="secondary" selected)

    assert html =~
             ~r{/studio/agents\?(?:runtime=secondary(?:&amp;|&)node=all|node=all(?:&amp;|&)runtime=secondary)}

    assert html =~
             ~r{/studio/settings\?(?:runtime=secondary(?:&amp;|&)node=all|node=all(?:&amp;|&)runtime=secondary)}
  end

  test "invalid runtime falls back to default with warning", %{conn: conn} do
    Application.put_env(:jido_studio, :jido_instances, [
      %{key: "primary", module: JidoStudio.TestJido, label: "Primary"}
    ])

    {:ok, _view, html} = live(conn, "/studio?runtime=missing")

    assert html =~ "Selected runtime missing is unavailable."
    assert html =~ "Using Primary."
  end
end
