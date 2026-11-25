defmodule JidoStudio.HomeLiveTest do
  use JidoStudio.ConnCase, async: true

  test "renders attention and setup above fleet metrics with starter card below core modules", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/studio")

    attention_idx = index_of(html, "Attention Needed")
    setup_idx = index_of(html, "Setup Assistant")
    metrics_idx = index_of(html, "Agents Online")
    top_agents_idx = index_of(html, "Top Agents")
    recent_idx = index_of(html, "Recent Activity")
    example_idx = index_of(html, "Open Starter Agent")

    assert attention_idx < metrics_idx
    assert setup_idx < metrics_idx
    assert top_agents_idx < recent_idx
    assert recent_idx < example_idx
  end

  test "renders setup summary labels and profile guidance", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio")

    assert html =~ "Setup Assistant"
    assert html =~ "Recommended Improvements"
    assert html =~ "Active Profile:"
    assert html =~ "Apply profile snippet"
    assert html =~ "What changes?"
    assert html =~ "Rollback:"
  end

  test "renders setup check CTAs for recovery and guidance", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio")

    assert html =~ "Open config snippet"
    assert html =~ "Re-test"
    assert html =~ "Use durable profile"
    assert html =~ "Continue with polling"
    assert html =~ "Use Interact (non-chat)"
    assert html =~ "Run smoke interaction"
  end

  test "renders setup and example visibility controls", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio")

    assert html =~ "data-js-home-setup"
    assert html =~ "data-js-home-setup-complete="
    assert html =~ "data-js-home-setup-regressed"
    assert html =~ "data-js-home-setup-show"
    assert html =~ "data-js-home-example"
    assert html =~ "data-js-home-example-show"
  end

  test "open_starter_agent emits onboarding starter telemetry", %{conn: conn} do
    event = [:jido_studio, :onboarding, :starter_opened]
    handler_id = "home-starter-opened-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, view, _html} = live(conn, "/studio")

    render_click(view, "open_starter_agent", %{
      "path" => "/studio/agents",
      "mode" => "home_card",
      "starter_slug" => "starter",
      "starter_module" => "JidoStudio.BeginnerAgent"
    })

    assert_receive {:telemetry_event, ^event, measurements, metadata}
    assert measurements.count == 1
    assert metadata.source == "home_starter_card"
    assert metadata.mode == "home_card"
    assert metadata.starter_slug == "starter"
  end

  test "open_attention_item emits triage warning telemetry", %{conn: conn} do
    event = [:jido_studio, :triage, :warning_opened]
    handler_id = "home-triage-warning-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, view, _html} = live(conn, "/studio")

    render_click(view, "open_attention_item", %{
      "path" => "/studio/activity",
      "kind" => "test_warning"
    })

    assert_receive {:telemetry_event, ^event, measurements, metadata}
    assert measurements.count == 1
    assert metadata.warning_kind == "test_warning"
    assert metadata.source == "home_attention"
  end

  defp index_of(haystack, needle) when is_binary(haystack) and is_binary(needle) do
    case :binary.match(haystack, needle) do
      {index, _len} -> index
      :nomatch -> flunk("expected to find #{inspect(needle)} in response HTML")
    end
  end

  def handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end
