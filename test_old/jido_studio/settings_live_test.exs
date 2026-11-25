defmodule JidoStudio.SettingsLiveTest do
  use JidoStudio.ConnCase, async: false

  setup do
    old_live_ops = Application.get_env(:jido_studio, :live_ops, :__unset__)

    on_exit(fn ->
      restore_env(:live_ops, old_live_ops)
    end)

    :ok
  end

  test "renders setup re-entry card and runtime configuration summary", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/settings")

    assert html =~ "Setup Assistant"
    assert html =~ "Re-test"
    assert html =~ "Runtime Connected"
    assert html =~ "Persistence Selected"
    assert html =~ "Realtime Enabled"
    assert html =~ "Chat Credentials (Optional)"
    assert html =~ "Smoke Test"
    assert html =~ "Setup Profile Guidance"
    assert html =~ "Apply profile snippet"
    assert html =~ "Runtime Configuration"
    assert html =~ "Thread Storage Mode"
    assert html =~ "Live Ops Enabled"
  end

  test "re-test recomputes setup checks and profile selection updates snippet", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/studio/settings")

    Application.put_env(:jido_studio, :live_ops, enabled: false, presence_module: false)

    render_click(view, "retest_setup")

    rendered = render(view)
    assert rendered =~ "Live Ops is disabled; realtime updates are limited."

    view
    |> element(
      "button[phx-click='select_setup_profile'][phx-value-value='team_durable_ops']",
      "Team Durable Ops"
    )
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Profile C"
    assert rendered =~ "presence_module: MyApp.Presence"
  end

  defp restore_env(key, :__unset__), do: Application.delete_env(:jido_studio, key)
  defp restore_env(key, value), do: Application.put_env(:jido_studio, key, value)
end
