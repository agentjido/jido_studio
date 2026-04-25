defmodule JidoStudio.AgentsLiveTest do
  use JidoStudio.ConnCase, async: false

  alias JidoStudio.AgentRegistry
  alias JidoStudio.Chat.Session, as: ChatSession
  alias JidoStudio.TestJido
  alias JidoStudio.Threads.Manager, as: ThreadsManager

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

    assert html =~ "Basic View"
    assert html =~ "2. Set Inputs and Run"
    assert html =~ "Current Agent State"
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

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?view=advanced")

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

    {:ok, view, html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?view=advanced")

    assert html =~ "Signal and action introspection with guarded runtime dispatch."
    assert has_element?(view, "span[title='Chat unavailable for this instance']", "Chat")
  end

  test "guarded runner requires arming before execute and succeeds after arming", %{conn: conn} do
    started_event = [:jido_studio, :interaction, :started]
    completed_event = [:jido_studio, :interaction, :completed]
    first_success_event = [:jido_studio, :onboarding, :first_interaction_succeeded]
    handler_id = "agents-interaction-metrics-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [started_event, completed_event, first_success_event],
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    instance_id = "non-chat-runner-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, NonChatAgent, id: instance_id)

    slug = slug_for_module(NonChatAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?view=advanced")

    assert has_element?(view, "button[phx-click='run_selected_interaction'][disabled]")

    render_click(view, "arm_runner_execute", %{})
    refute has_element?(view, "button[phx-click='run_selected_interaction'][disabled]")

    render_click(view, "run_selected_interaction", %{})

    assert render(view) =~ "status: :ok"

    assert_receive {:telemetry_event, ^started_event, started_measurements, started_metadata}
    assert started_measurements.count == 1
    assert started_metadata.mode == "interact"
    assert started_metadata.source == "agents_interact"

    assert_receive {:telemetry_event, ^completed_event, completed_measurements,
                    completed_metadata}

    assert completed_measurements.count == 1
    assert completed_metadata.mode == "interact"
    assert completed_metadata.status == "success"

    assert_receive {:telemetry_event, ^first_success_event, first_measurements, first_metadata}
    assert first_measurements.count == 1
    assert first_metadata.mode == "interact"
    assert first_metadata.source == "agents_interact"
  end

  test "dispatch failure emits interaction error telemetry without first-success metric", %{
    conn: conn
  } do
    started_event = [:jido_studio, :interaction, :started]
    completed_event = [:jido_studio, :interaction, :completed]
    first_success_event = [:jido_studio, :onboarding, :first_interaction_succeeded]
    handler_id = "agents-interaction-failure-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [started_event, completed_event, first_success_event],
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    instance_id = "non-chat-failing-runner-#{System.unique_integer([:positive])}"

    assert {:ok, agent_pid} = Jido.start_agent(TestJido, NonChatAgent, id: instance_id)

    slug = slug_for_module(NonChatAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?view=advanced")

    render_click(view, "arm_runner_execute", %{})

    Process.exit(agent_pid, :kill)
    Process.sleep(30)

    render_click(view, "run_selected_interaction", %{})

    assert_receive {:telemetry_event, ^started_event, started_measurements, started_metadata}
    assert started_measurements.count == 1
    assert started_metadata.mode == "interact"
    assert started_metadata.dispatch_mode == "sync"
    assert started_metadata.source == "agents_interact"

    assert_receive {:telemetry_event, ^completed_event, completed_measurements,
                    completed_metadata}

    assert completed_measurements.count == 1
    assert completed_metadata.mode == "interact"
    assert completed_metadata.status == "error"
    assert completed_metadata.dispatch_mode == "sync"
    assert completed_metadata.source == "agents_interact"

    refute_receive {:telemetry_event, ^first_success_event, _first_measurements, _first_metadata},
                   50
  end

  test "runner arm resets when payload changes", %{conn: conn} do
    instance_id = "non-chat-runner-reset-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, NonChatAgent, id: instance_id)

    slug = slug_for_module(NonChatAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?view=advanced")

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

  test "basic view renders starter operations and prefill emits telemetry", %{conn: conn} do
    event = [:jido_studio, :onboarding, :starter_payload_prefilled]
    handler_id = "agents-starter-prefill-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    instance_id = "beginner-prefill-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, JidoStudio.BeginnerAgent, id: instance_id)

    slug = slug_for_module(JidoStudio.BeginnerAgent)

    {:ok, view, html} = live(conn, "/studio/agents/#{slug}/#{instance_id}")

    assert html =~ "1. Pick a Starter Operation"
    assert html =~ "Ping"

    render_click(view, "prefill_starter_operation", %{"id" => "starter:beginner.ping"})

    updated = render(view)
    assert updated =~ "Ping (check instance health)"
    assert updated =~ "beginner.ping"
    assert updated =~ ~s(value="hello")

    assert_receive {:telemetry_event, ^event, %{count: 1}, metadata}
    assert metadata.source == "agents_basic_starter"
    assert metadata.starter_operation == "starter:beginner.ping"
  end

  test "basic view shows guided next actions after successful run", %{conn: conn} do
    instance_id = "beginner-delta-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, JidoStudio.BeginnerAgent, id: instance_id)

    slug = slug_for_module(JidoStudio.BeginnerAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}")

    render_click(view, "prefill_starter_operation", %{"id" => "starter:beginner.add"})
    render_click(view, "arm_runner_execute", %{})
    render_click(view, "run_selected_interaction", %{})

    updated = render(view)
    assert updated =~ "Run Succeeded"
    assert updated =~ "Show what changed"
    assert updated =~ "Open Events"
    assert updated =~ "Open Thread Context"
  end

  test "open_next_action emits basic next-action telemetry", %{conn: conn} do
    event = [:jido_studio, :interaction, :next_action_opened]
    handler_id = "agents-next-action-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    instance_id = "beginner-next-action-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, JidoStudio.BeginnerAgent, id: instance_id)

    slug = slug_for_module(JidoStudio.BeginnerAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}")

    render_click(view, "open_next_action", %{
      "path" => "/studio/agents",
      "next_action" => "instance_events",
      "trace_id" => ""
    })

    assert_receive {:telemetry_event, ^event, %{count: 1}, metadata}
    assert metadata.source == "agents_basic_result"
    assert metadata.next_action == "instance_events"
  end

  test "clear workspace removes persisted chat state for an instance", %{conn: conn} do
    table =
      String.to_atom("jido_studio_agents_live_workspace_#{System.unique_integer([:positive])}")

    restore_persistence = stash_app_env(:jido_studio, :thread_persistence, true)
    restore_storage_mode = stash_app_env(:jido_studio, :thread_storage_mode, :studio)

    restore_storage =
      stash_app_env(:jido_studio, :thread_storage, {Jido.Storage.ETS, table: table})

    on_exit(fn ->
      restore_persistence.()
      restore_storage_mode.()
      restore_storage.()

      for suffix <- [:checkpoints, :threads, :thread_meta] do
        table_name = String.to_atom("#{table}_#{suffix}")

        if :ets.whereis(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end
    end)

    instance_id = "workspace-clear-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    state =
      ChatSession.with_initial_thread("Saved Thread")
      |> ChatSession.append_user_turn("persisted hello")
      |> then(fn {session, pending_id} ->
        ChatSession.resolve_assistant_reply(session, pending_id, "persisted world")
      end)

    assert :ok =
             ThreadsManager.save_workspace(slug, instance_id, state,
               jido_instance: TestJido,
               draft_message: "persisted draft"
             )

    assert {:ok, saved_payload} =
             ThreadsManager.load_workspace(slug, instance_id, jido_instance: TestJido)

    assert saved_payload.source == :persisted

    {:ok, view, html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?view=advanced")
    assert html =~ "Saved Thread"

    render_click(view, "clear_workspace", %{})

    assert {:ok, cleared_payload} =
             ThreadsManager.load_workspace(slug, instance_id, jido_instance: TestJido)

    assert cleared_payload.source == :fresh

    rendered = render(view)
    refute rendered =~ "Saved Thread"
  end

  test "show renders persisted thread context when model metadata is structured", %{conn: conn} do
    table =
      String.to_atom(
        "jido_studio_agents_live_structured_model_#{System.unique_integer([:positive])}"
      )

    restore_persistence = stash_app_env(:jido_studio, :thread_persistence, true)
    restore_storage_mode = stash_app_env(:jido_studio, :thread_storage_mode, :studio)

    restore_storage =
      stash_app_env(:jido_studio, :thread_storage, {Jido.Storage.ETS, table: table})

    on_exit(fn ->
      restore_persistence.()
      restore_storage_mode.()
      restore_storage.()

      for suffix <- [:checkpoints, :threads, :thread_meta] do
        table_name = String.to_atom("#{table}_#{suffix}")

        if :ets.whereis(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end
    end)

    instance_id = "structured-model-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, NonChatAgent, id: instance_id)

    slug = slug_for_module(NonChatAgent)
    chat_state = ChatSession.with_initial_thread("Saved Thread")
    thread_id = chat_state.active_thread_id

    assert :ok =
             ThreadsManager.save_workspace(
               slug,
               instance_id,
               chat_state,
               jido_instance: TestJido,
               thread_contexts: %{
                 thread_id => %{
                   captured_at: System.system_time(:millisecond),
                   status: :running,
                   strategy_thread_id: thread_id,
                   iteration: 2,
                   conversation_count: 1,
                   pending_tool_calls_count: 0,
                   thinking_blocks_count: 0,
                   termination_reason: :waiting,
                   model: %{provider: :openai, id: "openai/gpt-oss-20b"}
                 }
               }
             )

    {:ok, view, _html} =
      live(
        conn,
        "/studio/agents/#{slug}/#{instance_id}/observe?panel=thread_context&view=advanced"
      )

    rendered = render(view)

    assert rendered =~ "Persisted Context Snapshot"
    assert rendered =~ "Persisted Workspace"
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

    {:ok, _view, html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?view=advanced")

    assert html =~ "How can I help you today?"
  end

  test "index splits internal agents into separate section", %{conn: conn} do
    instance_id = "internal-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = Jido.start_agent(TestJido, InternalTaggedAgent, id: instance_id)

    {:ok, _view, html} = live(conn, "/studio/agents")

    assert html =~ "Internal Agents"
    assert html =~ "internal"
  end

  test "index renders inventory explainer, source app column, and starter card", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/agents")

    assert html =~ "Discovered Modules"
    assert html =~ "Inventory Model"
    assert html =~ "Source App"
    assert html =~ "Starter Agent"
  end

  test "open_starter_agent emits onboarding starter telemetry", %{conn: conn} do
    event = [:jido_studio, :onboarding, :starter_opened]
    handler_id = "agents-starter-opened-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, view, _html} = live(conn, "/studio/agents")

    render_click(view, "open_starter_agent", %{
      "path" => "/studio/agents",
      "mode" => "agents_index_card",
      "starter_slug" => "starter",
      "starter_module" => "JidoStudio.BeginnerAgent"
    })

    assert_receive {:telemetry_event, ^event, %{count: 1}, metadata}
    assert metadata.source == "agents_starter_card"
    assert metadata.mode == "agents_index_card"
    assert metadata.starter_slug == "starter"
  end

  test "start=1 opens start modal, bypasses auto-follow, and emits modal telemetry", %{conn: conn} do
    event = [:jido_studio, :onboarding, :starter_start_modal_opened]
    handler_id = "agents-starter-modal-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    instance_id = "start-modal-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}?start=1")

    assert has_element?(view, "h3#start-instance-modal-title", "Start Instance")
    assert render(view) =~ "Select a running instance to open chat, settings, and threads."
    refute render(view) =~ "Instance Menu"
    assert AgentRegistry.running_count(TestJido) == 1

    assert_receive {:telemetry_event, ^event, %{count: 1}, metadata}
    assert metadata.source == "agents_start_query"
    assert metadata.mode == "deep_link"
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

  defp stash_app_env(app, key, value) when is_atom(app) and is_atom(key) do
    previous = Application.get_env(app, key)
    Application.put_env(app, key, value)

    fn ->
      if is_nil(previous) do
        Application.delete_env(app, key)
      else
        Application.put_env(app, key, previous)
      end
    end
  end

  def handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end
