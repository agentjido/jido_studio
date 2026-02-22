defmodule JidoStudio.AgentsLiveTest do
  use JidoStudio.ConnCase, async: false

  alias JidoStudio.AgentRegistry
  alias JidoStudio.TestJido

  defmodule NonChatAgent do
    use Jido.Agent,
      name: "non_chat_agent",
      description: "Test-only non chat agent",
      tags: ["test", "non-chat"],
      schema: []

    @impl true
    def signal_routes(_ctx) do
      [{"demo.ping", Jido.Actions.Control.Noop}]
    end
  end

  defmodule InternalTaggedAgent do
    use Jido.Agent,
      name: "internal_tagged_agent",
      description: "Test-only internal tagged agent",
      tags: ["internal", "test"],
      schema: []

    @impl true
    def signal_routes(_ctx) do
      [{"internal.ping", Jido.Actions.Control.Noop}]
    end
  end

  setup do
    old_live_ops = Application.get_env(:jido_studio, :live_ops, [])
    old_agent_interactions = Application.get_env(:jido_studio, :agent_interactions, [])

    Application.put_env(:jido_studio, :live_ops,
      enabled: true,
      auto_follow_default: false,
      viewer_tracking: false,
      event_stream_limit: 40,
      agent_list_poll_ms: 500
    )

    Application.put_env(:jido_studio, :agent_interactions,
      enabled: true,
      default_tab: :auto,
      runner_timeout_ms: 2_000,
      runner_history_limit: 20,
      internal_agent_tags: ["internal"]
    )

    case Process.whereis(TestJido) do
      pid when is_pid(pid) ->
        Process.exit(pid, :kill)
        Process.sleep(20)

      _ ->
        :ok
    end

    start_supervised!(TestJido)

    on_exit(fn ->
      Application.put_env(:jido_studio, :live_ops, old_live_ops)
      Application.put_env(:jido_studio, :agent_interactions, old_agent_interactions)
    end)

    :ok
  end

  test "index renders active instances and supports follow/unfollow", %{conn: conn} do
    instance_id = "alpha-follow-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.WeatherAgent, id: instance_id)

    {:ok, view, html} = live(conn, "/studio/agents")

    assert html =~ "Active Instances"
    assert html =~ short(instance_id)

    view
    |> element("button[phx-click='follow_instance'][phx-value-id='#{instance_id}']")
    |> render_click()

    assert render(view) =~ "Following: #{short(instance_id)}"

    view
    |> element("button[phx-click='unfollow_instance']", "Following")
    |> render_click()

    refute render(view) =~ "Following: #{short(instance_id)}"
  end

  test "index filters running instances by search query", %{conn: conn} do
    alpha_id = "alpha-filter-#{System.unique_integer([:positive])}"
    beta_id = "beta-filter-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.WeatherAgent, id: alpha_id)

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.WeatherAgent, id: beta_id)

    {:ok, view, _html} = live(conn, "/studio/agents")

    assert render(view) =~ short(alpha_id)
    assert render(view) =~ short(beta_id)

    view
    |> element("form[phx-change='update_instance_filters']")
    |> render_change(%{
      "filters" => %{
        "status_filter" => "all",
        "presence_filter" => "all",
        "search_query" => alpha_id,
        "sort_by" => "last_activity"
      }
    })

    filtered = render(view)
    assert filtered =~ short(alpha_id)
    refute filtered =~ short(beta_id)
  end

  test "auto-follow target selects the first matching instance", %{conn: conn} do
    target_id = "target-auto-#{System.unique_integer([:positive])}"
    other_id = "other-auto-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.WeatherAgent, id: other_id)

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.WeatherAgent, id: target_id)

    {:ok, view, _html} = live(conn, "/studio/agents")

    view
    |> element("form[phx-change='update_auto_follow_target']")
    |> render_change(%{
      "target" => %{
        "instance_id" => target_id,
        "project_id" => "",
        "user_id" => ""
      }
    })

    view
    |> element("button[phx-click='toggle_auto_follow_instances']")
    |> render_click()

    assert render(view) =~ "Following: #{short(target_id)}"
  end

  test "show defaults to interact for non-chat agents", %{conn: conn} do
    instance_id = "non-chat-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, NonChatAgent, id: instance_id)

    slug = slug_for_module(NonChatAgent)

    {:ok, _view, html} = live(conn, "/studio/agents/#{slug}/#{instance_id}")

    assert html =~ "Signal and action introspection with guarded runtime dispatch."
  end

  test "show route disconnected render uses workbench shell layout", %{conn: conn} do
    instance_id = "layout-shell-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    conn = get(conn, "/studio/agents/#{slug}/#{instance_id}")
    html = html_response(conn, 200)

    assert html =~ "js-main-workbench"
    assert html =~ ~s(id="studio-main")
    assert html =~ ~s(data-prefix="/studio")
  end

  test "workbench renders section menu and section-specific panels", %{conn: conn} do
    instance_id = "workbench-sections-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}")

    assert has_element?(view, "a", "Play")
    assert has_element?(view, "a", "Observe")
    assert has_element?(view, "a", "Configure")
    assert has_element?(view, "a[href*='/play'][href*='panel=interact']")
    assert has_element?(view, "a[href*='node=all'][href*='panel=interact']")
    refute has_element?(view, "a[href*='?node=all?panel=interact']")
    refute has_element?(view, "a[href*='panel=thread_context']")
    assert has_element?(view, ".js-agent-summary-pane")

    view
    |> element("a[href*='/observe']", "Observe")
    |> render_click()

    assert has_element?(view, "a[href*='panel=thread_context']")
    assert has_element?(view, "h4", "Live Triage")
    assert has_element?(view, ".js-agent-summary-pane")

    view
    |> element("a[href*='/configure']", "Configure")
    |> render_click()

    assert has_element?(view, "h4", "Live Triage")
    assert has_element?(view, ".js-agent-summary-pane")
  end

  test "requested chat panel falls back to interact for non-chat agents", %{conn: conn} do
    instance_id = "non-chat-panel-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, NonChatAgent, id: instance_id)

    slug = slug_for_module(NonChatAgent)

    {:ok, view, html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?panel=chat")

    assert html =~ "Signal and action introspection with guarded runtime dispatch."
    assert has_element?(view, "span[title='Chat unavailable for this instance']", "Chat")
  end

  test "chat defaults to interact when provider credentials are missing", %{conn: conn} do
    restore_api_key = stash_env("ANTHROPIC_API_KEY")
    restore_claude_key = stash_env("CLAUDE_API_KEY")
    restore_openai_key = stash_env("OPENAI_API_KEY")
    restore_groq_key = stash_env("GROQ_API_KEY")

    on_exit(fn ->
      restore_api_key.()
      restore_claude_key.()
      restore_openai_key.()
      restore_groq_key.()
    end)

    instance_id = "calculator-no-keys-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    {:ok, view, html} = live(conn, "/studio/agents/#{slug}/#{instance_id}")

    assert html =~ "Signal and action introspection with guarded runtime dispatch."
    assert has_element?(view, "span[title='Chat unavailable for this instance']", "Chat")
  end

  test "guarded runner requires arming before execute and succeeds after arming", %{conn: conn} do
    instance_id = "non-chat-runner-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, NonChatAgent, id: instance_id)

    slug = slug_for_module(NonChatAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}")

    assert has_element?(view, "button[phx-click='run_selected_interaction'][disabled]")

    render_click(view, "arm_runner_execute", %{})
    refute has_element?(view, "button[phx-click='run_selected_interaction'][disabled]")

    render_click(view, "run_selected_interaction", %{})

    assert render(view) =~ "status: :ok"
  end

  test "runner arm resets when payload changes", %{conn: conn} do
    instance_id = "non-chat-runner-reset-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, NonChatAgent, id: instance_id)

    slug = slug_for_module(NonChatAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}")

    render_click(view, "arm_runner_execute", %{})
    assert render(view) =~ "Armed"
    refute has_element?(view, "button[phx-click='run_selected_interaction'][disabled]")

    view
    |> element("form[phx-change='update_runner_payload']")
    |> render_change(%{
      "runner" => %{
        "payload_json" => ~s({"count": 1})
      }
    })

    assert render(view) =~ "Arm Execute"
    assert has_element?(view, "button[phx-click='run_selected_interaction'][disabled]")
  end

  test "show defaults to chat for chat-capable agents", %{conn: conn} do
    restore_api_key = stash_env("ANTHROPIC_API_KEY")
    restore_claude_key = stash_env("CLAUDE_API_KEY")

    System.put_env("ANTHROPIC_API_KEY", "test-key")

    on_exit(fn ->
      restore_api_key.()
      restore_claude_key.()
    end)

    instance_id = "weather-chat-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.WeatherAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.WeatherAgent)

    {:ok, _view, html} = live(conn, "/studio/agents/#{slug}/#{instance_id}")

    assert html =~ "How can I help you today?"
  end

  test "index splits internal agents into separate section", %{conn: conn} do
    instance_id = "internal-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, InternalTaggedAgent, id: instance_id)

    {:ok, _view, html} = live(conn, "/studio/agents")

    assert html =~ "Internal Agents"
    assert html =~ "internal"
  end

  defp short(id) when is_binary(id), do: String.slice(id, 0, 12)

  defp slug_for_module(module) do
    AgentRegistry.list_agents(jido_instance: TestJido)
    |> Enum.find(&(&1.module == module))
    |> case do
      %{slug: slug} when is_binary(slug) -> slug
      _ -> raise "Unable to resolve slug for #{inspect(module)}"
    end
  end

  defp stash_env(var) when is_binary(var) do
    previous = System.get_env(var)
    System.delete_env(var)

    fn ->
      if is_binary(previous) do
        System.put_env(var, previous)
      else
        System.delete_env(var)
      end
    end
  end
end
