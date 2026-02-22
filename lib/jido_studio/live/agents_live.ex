defmodule JidoStudio.AgentsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components
  import JidoStudio.Live.AgentsLive.Panes
  import JidoStudio.Live.AgentsLive.Support

  alias JidoStudio.AgentInteractions
  alias JidoStudio.AgentRegistry
  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Agents.FilterForm, as: AgentsFilterForm
  alias JidoStudio.Agents.Introspection
  alias JidoStudio.Agents.MessageSnapshot
  alias JidoStudio.Agents.Runner
  alias JidoStudio.Agents.RunnerForm
  alias JidoStudio.Chat.Runtime, as: ChatRuntime
  alias JidoStudio.Chat.Session, as: ChatSession
  alias JidoStudio.Delegation
  alias JidoStudio.LiveOps
  alias JidoStudio.Observability
  alias JidoStudio.Observability.Incidents
  alias JidoStudio.PresenterResolver
  alias JidoStudio.Presenters.Default
  alias JidoStudio.TraceBuffer
  alias JidoStudio.Threads.Manager, as: ThreadsManager
  alias JidoStudio.Threads.Storage, as: ThreadsStorage

  @default_model "claude-sonnet-4-5"
  @chat_provider_options ["anthropic", "openai", "groq", "ollama", "custom"]

  @impl true
  def mount(_params, _session, socket) do
    jido_instance = resolve_jido_instance(socket.assigns[:jido_instance])

    agents =
      AgentRegistry.list_agents(
        jido_instance: jido_instance,
        scope: socket.assigns[:cluster_scope]
      )

    {product_agents, internal_agents} = split_discovered_agents(agents)

    running_count =
      AgentRegistry.running_count(
        jido_instance,
        scope: socket.assigns[:cluster_scope]
      )

    start_form_schema = Default.start_form_schema(%{})
    scope_filters = %{project_id: nil, user_id: nil, agent_id: nil}

    socket =
      socket
      |> assign(:page_title, "Agents")
      |> assign(:jido_instance, jido_instance)
      |> assign(:agents, agents)
      |> assign(:product_agents, product_agents)
      |> assign(:internal_agents, internal_agents)
      |> assign(:running_count, running_count)
      |> assign(:jido_configured?, jido_instance != nil)
      |> assign(:agent_interactions_enabled?, AgentInteractions.enabled?())
      |> assign(:internal_agent_tags, AgentInteractions.internal_agent_tags())
      |> assign(:agent, nil)
      |> assign(:presenter, Default)
      |> assign(:agent_workspace_key, nil)
      |> assign(:running_instances, [])
      |> assign(:instance_cards, [])
      |> assign(:active_instance_id, nil)
      |> assign(:active_instance_pid, nil)
      |> assign(:runtime_status, nil)
      |> assign(:chat_state, ChatSession.empty())
      |> assign(:chat_config, default_chat_config())
      |> assign(:chat_enabled?, false)
      |> assign(:chat_pending?, false)
      |> assign(:chat_pending_message_id, nil)
      |> assign(:chat_stream, nil)
      |> assign(:draft_message, "")
      |> assign(:workspace_source, :fresh)
      |> assign(:persisted_thread_contexts, %{})
      |> assign(:thread_persistence?, ThreadsStorage.persistence_enabled?())
      |> assign(:persist_workspace_ref, nil)
      |> assign(:workbench_tab, :chat)
      |> assign(:detail_tabs, [%{id: :overview, label: "Overview"}])
      |> assign(:detail_tab, :overview)
      |> assign(:sections_by_tab, %{})
      |> assign(:system_prompt, "No system prompt configured.")
      |> assign(:ui_model, @default_model)
      |> assign(:start_modal_open?, false)
      |> assign(:starting_instance?, false)
      |> assign(:trace_preview_limit, Observability.trace_preview_limit())
      |> assign(:trace_include_agent_debug?, Observability.trace_include_agent_debug?())
      |> assign(:live_event_query, "")
      |> assign(:live_event_limit, LiveOps.event_stream_limit())
      |> assign(:instance_observability_events, [])
      |> assign(:instance_debug_events, [])
      |> assign(:instance_telemetry_events, [])
      |> assign(:instance_debug_error, nil)
      |> assign(:instance_debug_enabled?, false)
      |> assign(:instance_debug_level, "off")
      |> assign(:subagents, [])
      |> assign(:tasks, [])
      |> assign(:delegation_graph, %{nodes: [], edges: []})
      |> assign(:tool_insights, [])
      |> assign(:middleware_snapshots, [])
      |> assign(:triage_links, %{})
      |> assign(:runtime_messages, [])
      |> assign(:runtime_todos, [])
      |> assign(:instance_event_stream, [])
      |> assign(:instance_event_query, "")
      |> assign(:subagent_events, %{})
      |> assign(:expanded_subagent_id, nil)
      |> assign(:subagent_detail_tab, "config")
      |> assign(:expanded_event_ids, MapSet.new())
      |> assign(:interaction_model, empty_interaction_model())
      |> assign(:runner_form, RunnerForm.new())
      |> assign(:runner_result, nil)
      |> assign(:runner_history, [])
      |> assign(:interaction_history, %{})
      |> assign(:show_advanced_signals?, true)
      |> assign(:signal_scope, "entry_advanced")
      |> assign(:scope_filters, scope_filters)
      |> assign(:agent_filters, AgentsFilterForm.new())
      |> assign(:active_instances, [])
      |> assign(:filtered_instances, [])
      |> assign(:followed_instance_id, nil)
      |> assign(:auto_follow_instances?, LiveOps.auto_follow_default?())
      |> assign(:auto_follow_target, %{instance_id: nil, project_id: nil, user_id: nil})
      |> assign(:viewer_subscriptions, MapSet.new())
      |> assign(:viewer_id, viewer_id())
      |> assign(:tracked_viewer_instance_id, nil)
      |> assign(:user_timezone, "UTC")
      |> assign(:live_ops_enabled?, LiveOps.enabled?())
      |> assign(:live_ops_presence?, LiveOps.presence_available?())
      |> assign(:live_ops_realtime?, false)
      |> assign(:start_form_schema, start_form_schema)
      |> assign(:start_form, default_start_form(start_form_schema))
      |> assign(:start_form_error, nil)
      |> assign_chat_controls(@default_model)

    socket = setup_live_ops(socket)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    jido_instance = socket.assigns[:jido_instance]

    agents =
      AgentRegistry.list_agents(
        jido_instance: jido_instance,
        scope: socket.assigns[:cluster_scope]
      )
      |> filter_agents_by_scope(socket.assigns[:scope_filters])

    {product_agents, internal_agents} = split_discovered_agents(agents)

    active_instances =
      build_active_instances(agents,
        now: DateTime.utc_now(),
        viewer_count_fun: &LiveOps.viewer_count/1
      )

    filtered_instances =
      AgentsFilterForm.apply_filters(active_instances, socket.assigns.agent_filters)

    running_count =
      AgentRegistry.running_count(
        jido_instance,
        scope: socket.assigns[:cluster_scope]
      )

    socket =
      socket
      |> assign(:agents, agents)
      |> assign(:product_agents, product_agents)
      |> assign(:internal_agents, internal_agents)
      |> assign(:running_count, running_count)
      |> assign(:active_instances, active_instances)
      |> assign(:filtered_instances, filtered_instances)
      |> maybe_subscribe_viewers(active_instances)
      |> maybe_auto_follow_filtered_instances()

    {:noreply,
     socket
     |> assign(:followed_instance_id, resolve_followed_instance(socket, filtered_instances))
     |> maybe_track_followed_viewer()}
  end

  @impl true
  def handle_event("update_scope_filters", %{"scope" => scope_params}, socket) do
    filters = normalize_scope_filters(scope_params)
    jido_instance = socket.assigns[:jido_instance]

    if connected?(socket) and socket.assigns[:live_ops_enabled?] do
      _ = LiveOps.subscribe_agent_list(filters)
    end

    agents =
      AgentRegistry.list_agents(
        jido_instance: jido_instance,
        scope: socket.assigns[:cluster_scope]
      )
      |> filter_agents_by_scope(filters)

    {product_agents, internal_agents} = split_discovered_agents(agents)

    active_instances =
      build_active_instances(agents,
        now: DateTime.utc_now(),
        viewer_count_fun: &LiveOps.viewer_count/1
      )

    filtered_instances =
      AgentsFilterForm.apply_filters(active_instances, socket.assigns.agent_filters)

    socket =
      socket
      |> assign(:scope_filters, filters)
      |> assign(:agents, agents)
      |> assign(:product_agents, product_agents)
      |> assign(:internal_agents, internal_agents)
      |> assign(:active_instances, active_instances)
      |> assign(:filtered_instances, filtered_instances)
      |> maybe_subscribe_viewers(active_instances)
      |> maybe_auto_follow_filtered_instances()

    socket =
      socket
      |> assign(:followed_instance_id, resolve_followed_instance(socket, filtered_instances))
      |> maybe_track_followed_viewer()

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_instance_filters", %{"filters" => params}, socket) do
    filters = AgentsFilterForm.parse(params, socket.assigns.agent_filters)
    filtered_instances = AgentsFilterForm.apply_filters(socket.assigns.active_instances, filters)

    socket =
      socket
      |> assign(:agent_filters, filters)
      |> assign(:filtered_instances, filtered_instances)
      |> maybe_auto_follow_filtered_instances()

    socket =
      socket
      |> assign(:followed_instance_id, resolve_followed_instance(socket, filtered_instances))
      |> maybe_track_followed_viewer()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_auto_follow_instances", _params, socket) do
    socket =
      socket
      |> assign(:auto_follow_instances?, not socket.assigns.auto_follow_instances?)
      |> maybe_auto_follow_filtered_instances()

    socket =
      socket
      |> assign(
        :followed_instance_id,
        resolve_followed_instance(socket, socket.assigns.filtered_instances)
      )
      |> maybe_track_followed_viewer()

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_auto_follow_target", %{"target" => params}, socket) do
    target = normalize_auto_follow_target(params, socket.assigns.auto_follow_target)

    socket =
      socket
      |> assign(:auto_follow_target, target)
      |> maybe_auto_follow_filtered_instances()

    socket =
      socket
      |> assign(
        :followed_instance_id,
        resolve_followed_instance(socket, socket.assigns.filtered_instances)
      )
      |> maybe_track_followed_viewer()

    {:noreply, socket}
  end

  @impl true
  def handle_event("follow_instance", %{"id" => instance_id}, socket) do
    socket =
      socket
      |> assign(:followed_instance_id, normalize_scope_value(instance_id))
      |> maybe_track_followed_viewer()

    {:noreply, socket}
  end

  @impl true
  def handle_event("unfollow_instance", _params, socket) do
    socket =
      socket
      |> assign(:followed_instance_id, nil)
      |> maybe_track_followed_viewer()

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_timezone", %{"timezone" => timezone}, socket) do
    normalized =
      timezone
      |> to_string()
      |> String.trim()

    socket =
      socket
      |> assign(:user_timezone, if(normalized == "", do: "UTC", else: normalized))
      |> maybe_track_followed_viewer()

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_timezone", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_instance_event_query", %{"query" => query}, socket) do
    {:noreply, assign(socket, :instance_event_query, String.trim(query || ""))}
  end

  @impl true
  def handle_event("toggle_event_row", %{"id" => event_id}, socket) do
    expanded = socket.assigns[:expanded_event_ids] || MapSet.new()

    expanded =
      if MapSet.member?(expanded, event_id) do
        MapSet.delete(expanded, event_id)
      else
        MapSet.put(expanded, event_id)
      end

    {:noreply, assign(socket, :expanded_event_ids, expanded)}
  end

  @impl true
  def handle_event("toggle_subagent_row", %{"id" => subagent_id}, socket) do
    expanded =
      if socket.assigns.expanded_subagent_id == subagent_id do
        nil
      else
        subagent_id
      end

    socket =
      socket
      |> assign(:expanded_subagent_id, expanded)
      |> maybe_load_subagent_events(expanded)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_subagent_detail_tab", %{"tab" => tab}, socket) do
    tab =
      case tab do
        value when value in ["config", "messages", "middleware", "tools", "events"] -> value
        _ -> "config"
      end

    socket =
      socket
      |> assign(:subagent_detail_tab, tab)
      |> maybe_load_subagent_events(
        if(tab == "events", do: socket.assigns.expanded_subagent_id, else: nil)
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("new_thread", _params, socket) do
    socket =
      socket
      |> assign(:chat_state, ChatSession.add_thread(socket.assigns.chat_state))
      |> assign(:draft_message, "")
      |> schedule_workspace_persist(:threads)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_thread", %{"id" => thread_id}, socket) do
    socket =
      socket
      |> assign(:chat_state, ChatSession.select_thread(socket.assigns.chat_state, thread_id))
      |> schedule_workspace_persist(:thread_select)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_detail_tab", %{"tab" => tab}, socket) do
    detail_tab = parse_detail_tab(tab, socket.assigns.detail_tabs)
    socket = assign(socket, :detail_tab, detail_tab)

    if socket.assigns.workbench_tab == :instance and is_binary(socket.assigns.active_instance_id) and
         socket.assigns.agent do
      {:noreply,
       push_patch(socket,
         to:
           workbench_path(
             socket.assigns.prefix,
             socket.assigns.agent,
             socket.assigns.active_instance_id,
             :instance,
             detail_tab
           )
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_workbench_tab", %{"panel" => panel}, socket) do
    workbench_tab = parse_workbench_tab(panel)
    socket = assign(socket, :workbench_tab, workbench_tab)

    if is_binary(socket.assigns.active_instance_id) and socket.assigns.agent do
      {:noreply,
       push_patch(socket,
         to:
           workbench_path(
             socket.assigns.prefix,
             socket.assigns.agent,
             socket.assigns.active_instance_id,
             workbench_tab,
             socket.assigns.detail_tab
           )
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_signal", %{"key" => key}, socket) do
    form =
      socket.assigns.runner_form
      |> RunnerForm.select_signal(key)
      |> maybe_apply_payload_template(socket.assigns.interaction_model, {:signal, key})

    {:noreply, socket |> assign(:runner_form, form) |> assign(:runner_result, nil)}
  end

  @impl true
  def handle_event("select_action", %{"key" => key}, socket) do
    form =
      socket.assigns.runner_form
      |> RunnerForm.select_action(key)
      |> maybe_apply_payload_template(socket.assigns.interaction_model, {:action, key})

    {:noreply, socket |> assign(:runner_form, form) |> assign(:runner_result, nil)}
  end

  @impl true
  def handle_event("update_runner_payload", %{"runner" => params}, socket) do
    form = RunnerForm.parse(params, socket.assigns.runner_form)
    {:noreply, assign(socket, :runner_form, form)}
  end

  @impl true
  def handle_event("set_dispatch_mode", %{"mode" => mode}, socket) do
    form =
      RunnerForm.parse(%{"dispatch_mode" => mode}, socket.assigns.runner_form)
      |> RunnerForm.disarm()

    {:noreply, assign(socket, :runner_form, form)}
  end

  @impl true
  def handle_event("arm_runner_execute", _params, socket) do
    {:noreply, assign(socket, :runner_form, RunnerForm.arm(socket.assigns.runner_form))}
  end

  @impl true
  def handle_event("clear_runner_history", _params, socket) do
    instance_id = socket.assigns[:active_instance_id]
    interaction_history = socket.assigns[:interaction_history] || %{}

    interaction_history =
      if is_binary(instance_id) do
        Map.put(interaction_history, instance_id, [])
      else
        interaction_history
      end

    {:noreply,
     socket
     |> assign(:runner_history, [])
     |> assign(:interaction_history, interaction_history)
     |> assign(:runner_result, nil)
     |> schedule_workspace_persist(:interaction_history, 100)}
  end

  @impl true
  def handle_event("run_selected_interaction", _params, socket) do
    with true <- is_pid(socket.assigns[:active_instance_pid]),
         true <- RunnerForm.can_execute?(socket.assigns.runner_form),
         {:ok, payload} <- decode_runner_payload(socket.assigns.runner_form.payload_json),
         {:ok, dispatch_ref} <- selected_dispatch_ref(socket),
         {:ok, result} <-
           Runner.dispatch(socket.assigns.active_instance_pid, dispatch_ref, payload,
             dispatch_mode: socket.assigns.runner_form.dispatch_mode,
             timeout_ms: AgentInteractions.runner_timeout_ms()
           ) do
      instance_id = socket.assigns[:active_instance_id]
      history_entry = normalize_runner_history_entry(result, dispatch_ref)
      history = prepend_runner_history(socket.assigns[:runner_history], history_entry)

      interaction_history =
        update_interaction_history(socket.assigns[:interaction_history], instance_id, history)

      {:noreply,
       socket
       |> assign(:runner_result, %{status: :ok, value: result})
       |> assign(:runner_history, history)
       |> assign(:interaction_history, interaction_history)
       |> assign(:runner_form, RunnerForm.disarm(socket.assigns.runner_form))
       |> schedule_workspace_persist(:interaction_history, 100)}
    else
      false ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Select a running instance and arm execute before dispatching."
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:runner_result, %{status: :error, value: reason})
         |> put_flash(:error, "Dispatch failed: #{format_dispatch_error(reason)}")}
    end
  end

  @impl true
  def handle_event("toggle_advanced_signals", _params, socket) do
    {:noreply, assign(socket, :show_advanced_signals?, not socket.assigns.show_advanced_signals?)}
  end

  @impl true
  def handle_event("update_draft", params, socket) do
    message = Map.get(params, "message", socket.assigns.draft_message || "")
    provider = Map.get(params, "provider", socket.assigns.chat_provider)
    model = Map.get(params, "model", socket.assigns.chat_model)

    {provider, model, model_options} = normalize_chat_controls(provider, model)

    socket =
      socket
      |> assign(:draft_message, message)
      |> assign(:chat_provider, provider)
      |> assign(:chat_model, model)
      |> assign(:chat_model_options, model_options)
      |> schedule_workspace_persist(:draft, 600)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_instance_debug", _params, socket) do
    with true <- is_pid(socket.assigns.active_instance_pid),
         :ok <-
           Jido.AgentServer.set_debug(
             socket.assigns.active_instance_pid,
             not socket.assigns.instance_debug_enabled?
           ) do
      status = if socket.assigns.instance_debug_enabled?, do: "disabled", else: "enabled"

      {:noreply,
       socket
       |> put_flash(:info, "Debug event buffer #{status} for this instance.")
       |> refresh_instance_observability()}
    else
      false ->
        {:noreply, put_flash(socket, :error, "No running instance selected.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle debug mode: #{inspect(reason)}")}
    end
  rescue
    error ->
      {:noreply,
       put_flash(socket, :error, "Failed to toggle debug mode: #{Exception.message(error)}")}
  end

  @impl true
  def handle_event("set_debug_level", %{"level" => level}, socket) do
    with true <- is_pid(socket.assigns.active_instance_pid),
         debug_flag <- level in ["on", "verbose"],
         :ok <- Jido.AgentServer.set_debug(socket.assigns.active_instance_pid, debug_flag) do
      {:noreply,
       socket
       |> assign(:instance_debug_level, normalize_debug_level(level, debug_flag))
       |> put_flash(:info, "Debug level set to #{normalize_debug_level(level, debug_flag)}.")
       |> refresh_instance_observability()}
    else
      false ->
        {:noreply, put_flash(socket, :error, "No running instance selected.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to set debug level: #{inspect(reason)}")}
    end
  rescue
    error ->
      {:noreply,
       put_flash(socket, :error, "Failed to set debug level: #{Exception.message(error)}")}
  end

  @impl true
  def handle_event("update_live_event_query", %{"query" => query}, socket) do
    {:noreply, assign(socket, :live_event_query, String.trim(query || ""))}
  end

  @impl true
  def handle_event("open_start_modal", _params, socket) do
    if socket.assigns.jido_configured? do
      {:noreply,
       socket
       |> assign(:start_modal_open?, true)
       |> assign(:start_form_error, nil)
       |> assign(:start_form, default_start_form(socket.assigns.start_form_schema))}
    else
      {:noreply, put_flash(socket, :error, "No Jido instance configured for starting agents.")}
    end
  end

  @impl true
  def handle_event("close_start_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:start_modal_open?, false)
     |> assign(:starting_instance?, false)
     |> assign(:start_form_error, nil)}
  end

  @impl true
  def handle_event("update_start_form", %{"start" => form}, socket) do
    {:noreply,
     socket
     |> assign(:start_form, normalize_start_form(form, socket.assigns.start_form_schema))
     |> assign(:start_form_error, nil)}
  end

  @impl true
  def handle_event("start_instance_with_options", %{"start" => form}, socket) do
    normalized_form = normalize_start_form(form, socket.assigns.start_form_schema)

    socket =
      socket
      |> assign(:start_form, normalized_form)
      |> assign(:starting_instance?, true)
      |> assign(:start_form_error, nil)

    with {:ok, jido_instance} <- fetch_jido_instance(socket),
         {:ok, start_opts} <- build_start_opts(normalized_form),
         {:ok, pid} <- Jido.start_agent(jido_instance, socket.assigns.agent.module, start_opts),
         {:ok, instance_id} <- resolve_instance_id(jido_instance, pid, start_opts) do
      {:noreply,
       socket
       |> assign(:starting_instance?, false)
       |> assign(:start_modal_open?, false)
       |> assign(:start_form, default_start_form(socket.assigns.start_form_schema))
       |> put_flash(:info, "Started instance #{short_instance_id(instance_id)}")
       |> push_navigate(
         to: agent_instance_path(socket.assigns.prefix, socket.assigns.agent, instance_id)
       )}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:starting_instance?, false)
         |> assign(:start_form_error, format_start_error(reason))}
    end
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    message = String.trim(socket.assigns.draft_message || "")

    cond do
      message == "" ->
        {:noreply, socket}

      socket.assigns.chat_pending? ->
        {:noreply, socket}

      not socket.assigns.chat_enabled? ->
        {:noreply, socket}

      true ->
        pending_content = "Thinking..."

        {chat_state, pending_id} =
          ChatSession.append_user_turn(socket.assigns.chat_state, message,
            pending_content: pending_content
          )

        timeout_ms = socket.assigns.chat_config.timeout_ms
        agent_module = socket.assigns.agent && socket.assigns.agent.module
        pid = socket.assigns.active_instance_pid
        stream_enabled? = socket.assigns.chat_config.streaming_enabled == true
        since_entry_count = stream_since_entry_count(pid)
        traces_path = current_traces_path(socket)

        socket =
          socket
          |> assign(:chat_state, chat_state)
          |> assign(:draft_message, "")
          |> assign(:chat_pending?, true)
          |> assign(:chat_pending_message_id, pending_id)
          |> schedule_workspace_persist(:send_message)

        cond do
          stream_enabled? and ChatRuntime.supports_async?(agent_module) ->
            case ChatRuntime.start_request(agent_module, pid, message) do
              {:ok, request} ->
                request_id = ChatRuntime.request_id(request) || pending_id

                poll_ms =
                  ChatRuntime.stream_poll_ms(
                    stream_poll_ms: socket.assigns.chat_config.stream_poll_ms
                  )

                Process.send_after(self(), {:chat_stream_tick, pending_id, request_id}, poll_ms)

                {:noreply,
                 socket
                 |> assign(
                   :chat_stream,
                   %{
                     pending_id: pending_id,
                     request_id: request_id,
                     request: request,
                     agent_module: agent_module,
                     pid: pid,
                     since_entry_count: since_entry_count,
                     instance_id: socket.assigns.active_instance_id,
                     traces_path: traces_path,
                     poll_ms: poll_ms,
                     last_text: "",
                     last_tool_events: []
                   }
                 )
                 |> start_async({:chat_turn_async, pending_id, request_id}, fn ->
                   ChatRuntime.await_request(agent_module, request, timeout_ms: timeout_ms)
                 end)}

              {:error, reason} ->
                error_message = ChatRuntime.to_user_message(reason, timeout_ms: timeout_ms)

                {:noreply,
                 socket
                 |> assign(
                   :chat_state,
                   ChatSession.resolve_assistant_error(
                     socket.assigns.chat_state,
                     pending_id,
                     error_message
                   )
                 )
                 |> clear_chat_pending()
                 |> schedule_workspace_persist(:chat_error)}
            end

          true ->
            {:noreply,
             socket
             |> start_async({:chat_turn_sync, pending_id}, fn ->
               ChatRuntime.ask(agent_module, pid, message, timeout_ms: timeout_ms)
             end)}
        end
    end
  end

  @impl true
  def handle_async({:chat_turn_sync, pending_id}, {:ok, {:ok, reply}}, socket) do
    {:noreply, resolve_chat_reply(socket, pending_id, reply)}
  end

  @impl true
  def handle_async({:chat_turn_async, pending_id, request_id}, {:ok, {:ok, reply}}, socket) do
    if chat_stream_match?(socket, pending_id, request_id) do
      {:noreply, resolve_chat_reply(socket, pending_id, reply)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async({:chat_turn_sync, pending_id}, {:ok, {:error, reason}}, socket) do
    {:noreply, resolve_chat_error(socket, pending_id, reason)}
  end

  @impl true
  def handle_async({:chat_turn_async, pending_id, request_id}, {:ok, {:error, reason}}, socket) do
    if chat_stream_match?(socket, pending_id, request_id) do
      {:noreply, resolve_chat_error(socket, pending_id, reason)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async({:chat_turn_sync, pending_id}, {:exit, reason}, socket) do
    {:noreply, resolve_chat_error(socket, pending_id, reason)}
  end

  @impl true
  def handle_async({:chat_turn_async, pending_id, request_id}, {:exit, reason}, socket) do
    if chat_stream_match?(socket, pending_id, request_id) do
      {:noreply, resolve_chat_error(socket, pending_id, reason)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async({:chat_turn_sync, pending_id}, {:ok, other}, socket) do
    {:noreply, resolve_chat_error(socket, pending_id, {:unexpected_result, other})}
  end

  @impl true
  def handle_async({:chat_turn_async, pending_id, request_id}, {:ok, other}, socket) do
    if chat_stream_match?(socket, pending_id, request_id) do
      {:noreply, resolve_chat_error(socket, pending_id, {:unexpected_result, other})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async(_name, _result, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_stream_tick, pending_id, request_id}, socket) do
    if chat_stream_match?(socket, pending_id, request_id) do
      stream = socket.assigns.chat_stream

      socket =
        case ChatRuntime.stream_snapshot(stream.pid,
               since_entry_count: stream.since_entry_count
             ) do
          {:ok, snapshot} ->
            partial_text = snapshot.streaming_text || ""

            tool_events =
              enrich_tool_events(
                snapshot.tool_events || [],
                stream.instance_id,
                stream.traces_path
              )

            updated_socket =
              socket
              |> maybe_update_pending_content(
                pending_id,
                partial_text,
                stream.last_text
              )
              |> maybe_update_pending_tool_events(
                pending_id,
                tool_events,
                stream.last_tool_events
              )

            assign(updated_socket, :chat_stream, %{
              stream
              | last_text: partial_text,
                last_tool_events: tool_events
            })

          {:error, _reason} ->
            socket
        end

      if chat_stream_match?(socket, pending_id, request_id) do
        Process.send_after(self(), {:chat_stream_tick, pending_id, request_id}, stream.poll_ms)
      end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:jido_studio_live_ops, :agent_list, payload}, socket) do
    socket =
      if scope_filters_match?(Map.get(payload, :scope), socket.assigns[:scope_filters]) do
        jido_instance = socket.assigns[:jido_instance]

        agents =
          AgentRegistry.list_agents(
            jido_instance: jido_instance,
            scope: socket.assigns[:cluster_scope]
          )
          |> filter_agents_by_scope(socket.assigns[:scope_filters])

        {product_agents, internal_agents} = split_discovered_agents(agents)

        active_instances =
          build_active_instances(agents,
            now: DateTime.utc_now(),
            viewer_count_fun: &LiveOps.viewer_count/1
          )

        filtered_instances =
          AgentsFilterForm.apply_filters(active_instances, socket.assigns.agent_filters)

        socket =
          socket
          |> assign(:agents, agents)
          |> assign(:product_agents, product_agents)
          |> assign(:internal_agents, internal_agents)
          |> assign(
            :running_count,
            AgentRegistry.running_count(jido_instance, scope: socket.assigns[:cluster_scope])
          )
          |> assign(:active_instances, active_instances)
          |> assign(:filtered_instances, filtered_instances)
          |> maybe_subscribe_viewers(active_instances)
          |> maybe_auto_follow_filtered_instances()

        assign(
          socket,
          :followed_instance_id,
          resolve_followed_instance(socket, filtered_instances)
        )
      else
        socket
      end

    {:noreply, maybe_track_followed_viewer(socket)}
  end

  @impl true
  def handle_info({:jido_studio_live_ops, :agent, payload}, socket) do
    active_instance_id = socket.assigns[:active_instance_id]
    payload_agent = payload[:agent_id]

    socket =
      if is_binary(active_instance_id) and is_binary(payload_agent) and
           payload_agent == active_instance_id do
        refresh_instance_observability(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", topic: topic}, socket) do
    if String.starts_with?(topic, "live_ops:viewers:") and socket.assigns.live_action == :index do
      agents = socket.assigns.agents || []

      active_instances =
        build_active_instances(agents,
          now: DateTime.utc_now(),
          viewer_count_fun: &LiveOps.viewer_count/1
        )

      filtered_instances =
        AgentsFilterForm.apply_filters(active_instances, socket.assigns.agent_filters)

      socket =
        socket
        |> assign(:active_instances, active_instances)
        |> assign(:filtered_instances, filtered_instances)
        |> maybe_auto_follow_filtered_instances()

      {:noreply,
       socket
       |> assign(:followed_instance_id, resolve_followed_instance(socket, filtered_instances))
       |> maybe_track_followed_viewer()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refresh_instance_observability, socket) do
    refreshed = refresh_instance_observability(socket)

    if socket.assigns.live_action == :index do
      agents =
        AgentRegistry.list_agents(
          jido_instance: socket.assigns[:jido_instance],
          scope: socket.assigns[:cluster_scope]
        )
        |> filter_agents_by_scope(socket.assigns[:scope_filters])

      {product_agents, internal_agents} = split_discovered_agents(agents)

      active_instances =
        build_active_instances(agents,
          now: DateTime.utc_now(),
          viewer_count_fun: &LiveOps.viewer_count/1
        )

      filtered_instances =
        AgentsFilterForm.apply_filters(active_instances, socket.assigns.agent_filters)

      refreshed =
        refreshed
        |> assign(:agents, agents)
        |> assign(:product_agents, product_agents)
        |> assign(:internal_agents, internal_agents)
        |> assign(
          :running_count,
          AgentRegistry.running_count(
            socket.assigns[:jido_instance],
            scope: socket.assigns[:cluster_scope]
          )
        )
        |> assign(:active_instances, active_instances)
        |> assign(:filtered_instances, filtered_instances)
        |> maybe_subscribe_viewers(active_instances)
        |> maybe_auto_follow_filtered_instances()

      {:noreply,
       refreshed
       |> assign(:followed_instance_id, resolve_followed_instance(refreshed, filtered_instances))
       |> maybe_track_followed_viewer()}
    else
      {:noreply, maybe_track_followed_viewer(refreshed)}
    end
  end

  @impl true
  def handle_info({:persist_workspace, token, reason}, socket) do
    socket =
      case socket.assigns.persist_workspace_ref do
        {_, ^token} ->
          socket
          |> assign(:persist_workspace_ref, nil)
          |> persist_workspace(reason)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  defp resolve_chat_reply(socket, pending_id, reply) do
    socket
    |> assign(
      :chat_state,
      ChatSession.resolve_assistant_reply(socket.assigns.chat_state, pending_id, reply)
    )
    |> clear_chat_pending()
    |> schedule_workspace_persist(:chat_reply)
  end

  defp resolve_chat_error(socket, pending_id, reason) do
    message =
      ChatRuntime.to_user_message(reason, timeout_ms: socket.assigns.chat_config.timeout_ms)

    socket
    |> assign(
      :chat_state,
      ChatSession.resolve_assistant_error(socket.assigns.chat_state, pending_id, message)
    )
    |> clear_chat_pending()
    |> schedule_workspace_persist(:chat_error)
  end

  defp clear_chat_pending(socket) do
    socket
    |> assign(:chat_pending?, false)
    |> assign(:chat_pending_message_id, nil)
    |> assign(:chat_stream, nil)
  end

  defp maybe_update_pending_content(socket, _pending_id, "", _last_text), do: socket

  defp maybe_update_pending_content(socket, pending_id, partial_text, last_text) do
    if partial_text != last_text do
      socket
      |> assign(
        :chat_state,
        ChatSession.update_pending_content(
          socket.assigns.chat_state,
          pending_id,
          partial_text
        )
      )
      |> schedule_workspace_persist(:stream_partial, 400)
    else
      socket
    end
  end

  defp maybe_update_pending_tool_events(socket, _pending_id, tool_events, last_tool_events)
       when tool_events == last_tool_events,
       do: socket

  defp maybe_update_pending_tool_events(socket, pending_id, tool_events, _last_tool_events) do
    socket
    |> assign(
      :chat_state,
      ChatSession.update_pending_tool_events(socket.assigns.chat_state, pending_id, tool_events)
    )
    |> schedule_workspace_persist(:stream_tool_events, 400)
  end

  defp chat_stream_match?(socket, pending_id, request_id) do
    stream = socket.assigns[:chat_stream]

    is_map(stream) and socket.assigns.chat_pending? and stream.pending_id == pending_id and
      stream.request_id == request_id
  end

  defp apply_action(socket, :index, params) do
    start_form_schema = Default.start_form_schema(%{})
    jido_instance = socket.assigns[:jido_instance]

    base_scope = socket.assigns[:scope_filters] || %{project_id: nil, user_id: nil, agent_id: nil}
    scope_filters = merge_scope_filters(base_scope, Map.get(params, "scope"))
    base_filters = socket.assigns[:agent_filters] || AgentsFilterForm.new()
    agent_filters = AgentsFilterForm.parse(Map.get(params, "filters"), base_filters)

    listed_agents =
      AgentRegistry.list_agents(
        jido_instance: jido_instance,
        scope: socket.assigns[:cluster_scope]
      )

    agents = filter_agents_by_scope(listed_agents, scope_filters)
    {product_agents, internal_agents} = split_discovered_agents(agents)

    active_instances =
      build_active_instances(agents,
        now: DateTime.utc_now(),
        viewer_count_fun: &LiveOps.viewer_count/1
      )

    filtered_instances = AgentsFilterForm.apply_filters(active_instances, agent_filters)
    followed_from_params = normalize_scope_value(Map.get(params, "followed_instance_id"))

    running_count =
      AgentRegistry.running_count(
        jido_instance,
        scope: socket.assigns[:cluster_scope]
      )

    socket =
      socket
      |> assign(:page_title, "Agents")
      |> assign(:scope_filters, scope_filters)
      |> assign(:agent_filters, agent_filters)
      |> assign(:agents, agents)
      |> assign(:product_agents, product_agents)
      |> assign(:internal_agents, internal_agents)
      |> assign(:active_instances, active_instances)
      |> assign(:filtered_instances, filtered_instances)
      |> assign(
        :followed_instance_id,
        followed_from_params || socket.assigns[:followed_instance_id]
      )
      |> assign(:running_count, running_count)
      |> assign(:agent, nil)
      |> assign(:presenter, Default)
      |> assign(:agent_workspace_key, nil)
      |> assign(:running_instances, [])
      |> assign(:instance_cards, [])
      |> assign(:active_instance_id, nil)
      |> assign(:active_instance_pid, nil)
      |> assign(:runtime_status, nil)
      |> assign(:chat_state, ChatSession.empty())
      |> assign(:chat_config, default_chat_config())
      |> assign(:chat_enabled?, false)
      |> assign(:chat_pending?, false)
      |> assign(:chat_pending_message_id, nil)
      |> assign(:chat_stream, nil)
      |> assign(:draft_message, "")
      |> assign(:workspace_source, :fresh)
      |> assign(:persisted_thread_contexts, %{})
      |> assign(:persist_workspace_ref, nil)
      |> assign(:workbench_tab, :chat)
      |> assign(:runtime_messages, [])
      |> assign(:runtime_todos, [])
      |> assign(:instance_event_stream, [])
      |> assign(:instance_event_query, "")
      |> assign(:expanded_event_ids, MapSet.new())
      |> assign(:expanded_subagent_id, nil)
      |> assign(:subagent_detail_tab, "config")
      |> assign(:subagent_events, %{})
      |> assign(:interaction_model, empty_interaction_model())
      |> assign(:runner_form, RunnerForm.new())
      |> assign(:runner_result, nil)
      |> assign(:runner_history, [])
      |> assign(:interaction_history, %{})
      |> assign(:show_advanced_signals?, true)
      |> assign(:signal_scope, "entry_advanced")
      |> assign_chat_controls(@default_model)
      |> assign(:start_form_schema, start_form_schema)
      |> assign(:start_form, default_start_form(start_form_schema))
      |> assign(:instance_observability_events, [])
      |> assign(:instance_debug_events, [])
      |> assign(:instance_telemetry_events, [])
      |> assign(:instance_debug_error, nil)
      |> assign(:instance_debug_enabled?, false)
      |> assign(:instance_debug_level, "off")
      |> assign(:subagents, [])
      |> assign(:tasks, [])
      |> assign(:delegation_graph, %{nodes: [], edges: []})
      |> assign(:tool_insights, [])
      |> assign(:middleware_snapshots, [])
      |> assign(:triage_links, %{})
      |> maybe_subscribe_viewers(active_instances)
      |> maybe_auto_follow_filtered_instances()

    socket
    |> assign(:followed_instance_id, resolve_followed_instance(socket, filtered_instances))
    |> maybe_track_followed_viewer()
  end

  defp apply_action(socket, :show, %{"slug" => slug} = params) do
    jido_instance = socket.assigns[:jido_instance]
    requested_instance_id = Map.get(params, "instance_id")
    requested_workbench_tab = requested_workbench_tab(params)
    scope_filters = merge_scope_filters(socket.assigns[:scope_filters], Map.get(params, "scope"))

    case AgentRegistry.get_agent(
           slug,
           jido_instance: jido_instance,
           scope: socket.assigns[:cluster_scope]
         ) do
      nil ->
        socket
        |> put_flash(:error, "Agent not found")
        |> push_navigate(to: scoped_path("#{socket.assigns.prefix}/agents"))

      agent ->
        running_instances = agent.running_instances || []
        presenter = PresenterResolver.resolve(agent.module)

        instance_runtime_map =
          Map.new(running_instances, fn instance ->
            {instance.id, instance_runtime_details(instance)}
          end)

        selected_instance =
          case requested_instance_id do
            nil ->
              if LiveOps.auto_follow_default?() do
                List.first(running_instances)
              else
                nil
              end

            id ->
              Enum.find(running_instances, &(&1.id == id))
          end

        active_instance_id =
          if(selected_instance, do: selected_instance.id, else: requested_instance_id)

        active_instance_pid = selected_instance && selected_instance.pid

        runtime_status =
          if selected_instance do
            instance_runtime_map
            |> Map.get(selected_instance.id, %{})
            |> Map.get(:status)
          else
            nil
          end

        instance_cards =
          build_instance_cards(
            presenter,
            agent,
            running_instances,
            instance_runtime_map,
            socket.assigns.prefix
          )

        start_form_schema = presenter_start_form_schema(presenter, agent)

        traces_path =
          traces_path(socket.assigns.prefix, agent, active_instance_id, active_instance_id)

        observability_preview =
          if selected_instance do
            load_instance_observability(
              selected_instance.id,
              selected_instance.pid,
              socket.assigns.trace_preview_limit,
              socket.assigns.trace_include_agent_debug?
            )
          else
            %{events: []}
          end

        interaction_model =
          if AgentInteractions.enabled?() do
            Introspection.build(agent.module, %{pid: active_instance_pid},
              events: observability_preview[:events] || []
            )
          else
            empty_interaction_model()
          end

        view_model =
          presenter_view_model(
            presenter,
            agent,
            runtime_status,
            instance_id: active_instance_id,
            pid: active_instance_pid,
            debug_enabled: selected_instance && instance_debug_enabled(selected_instance),
            raw_state: runtime_status && runtime_status.raw_state,
            observability_preview: if(selected_instance, do: observability_preview, else: nil),
            traces_path: traces_path
          )

        chat_config =
          presenter_chat_config(
            presenter,
            agent,
            runtime_status,
            instance_id: active_instance_id,
            pid: active_instance_pid,
            supported?: ChatRuntime.supports?(agent.module)
          )

        chat_enabled = chat_config.enabled and is_pid(active_instance_pid)

        workbench_tab =
          resolve_default_workbench_tab(requested_workbench_tab, interaction_model, chat_enabled)

        tabs =
          view_model
          |> Map.get(:tabs, [%{id: :overview, label: "Overview"}])
          |> ordered_detail_tabs()

        socket
        |> assign(:page_title, humanize_agent_name(agent.name))
        |> assign(:agent, agent)
        |> assign(:presenter, presenter)
        |> assign(:running_instances, running_instances)
        |> assign(:instance_cards, instance_cards)
        |> assign(:active_instance_id, active_instance_id)
        |> assign(:followed_instance_id, active_instance_id)
        |> assign(:active_instance_pid, active_instance_pid)
        |> assign(:runtime_status, runtime_status)
        |> assign(:scope_filters, scope_filters)
        |> assign(
          :instance_debug_enabled?,
          if(selected_instance, do: instance_debug_enabled(selected_instance), else: false)
        )
        |> assign(
          :instance_debug_level,
          if(selected_instance && instance_debug_enabled(selected_instance),
            do: "on",
            else: "off"
          )
        )
        |> assign(:chat_config, chat_config)
        |> assign(:chat_enabled?, chat_enabled)
        |> assign(:interaction_model, interaction_model)
        |> assign(:workbench_tab, workbench_tab)
        |> assign(:runner_form, sync_runner_form(socket.assigns[:runner_form], interaction_model))
        |> assign(:runner_result, nil)
        |> assign(:runner_history, current_runner_history(socket, active_instance_id))
        |> assign(:detail_tabs, tabs)
        |> assign(:detail_tab, parse_detail_tab(Map.get(params, "tab"), tabs))
        |> assign(:sections_by_tab, Map.get(view_model, :sections_by_tab, %{}))
        |> assign(:start_form_schema, start_form_schema)
        |> assign(:start_form, default_start_form(start_form_schema))
        |> assign(
          :system_prompt,
          Map.get(view_model, :system_prompt, "No system prompt configured.")
        )
        |> ensure_workspace_state(agent, active_instance_id)
        |> maybe_subscribe_live_ops(active_instance_id, scope_filters)
        |> assign(
          :triage_links,
          triage_links(socket.assigns.prefix, active_instance_id, scope_filters)
        )
        |> refresh_instance_observability()
        |> maybe_track_followed_viewer()
    end
  end

  defp ensure_workspace_state(socket, agent, active_instance_id) do
    case active_instance_id do
      nil ->
        cancel_workspace_persist_timer(socket.assigns[:persist_workspace_ref])

        socket
        |> assign(:agent_workspace_key, "#{agent.slug}:module")
        |> assign(:chat_state, ChatSession.empty())
        |> assign(:draft_message, "")
        |> assign(:workspace_source, :fresh)
        |> assign(:persisted_thread_contexts, %{})
        |> assign(:interaction_history, %{})
        |> assign(:runner_history, [])
        |> assign(:persist_workspace_ref, nil)
        |> assign(:chat_pending?, false)
        |> assign(:chat_pending_message_id, nil)
        |> assign(:chat_stream, nil)
        |> assign(:ui_model, strategy_model(agent.module))
        |> assign_chat_controls(strategy_model(agent.module))

      instance_id when is_binary(instance_id) ->
        workspace_key = "#{agent.slug}:#{instance_id}"

        if socket.assigns.agent_workspace_key == workspace_key do
          socket
        else
          cancel_workspace_persist_timer(socket.assigns[:persist_workspace_ref])

          socket
          |> assign(:agent_workspace_key, workspace_key)
          |> assign(:persist_workspace_ref, nil)
          |> assign(:chat_pending?, false)
          |> assign(:chat_pending_message_id, nil)
          |> assign(:chat_stream, nil)
          |> assign(:runner_result, nil)
          |> assign(:ui_model, strategy_model(agent.module))
          |> assign_chat_controls(strategy_model(agent.module))
          |> load_workspace_for(agent.slug, instance_id)
        end
    end
  end

  @impl true
  def render(%{agent: agent, live_action: action, active_instance_id: nil} = assigns)
      when not is_nil(agent) and action == :show do
    assigns =
      assigns
      |> assign(:module_path, agent_module_path(assigns.prefix, agent))
      |> assign(:traces_path, traces_path(assigns.prefix, agent, nil, nil))

    ~H"""
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between border-b border-js-border pb-4 gap-3">
        <div class="flex items-center gap-2 text-sm text-js-text-muted">
          <.link navigate={scoped_path(@prefix <> "/agents")} class="hover:text-js-text">
            Agents
          </.link>
          <span>/</span>
          <span class="text-js-text">{humanize_agent_name(@agent.name)}</span>
        </div>
        <div class="flex items-center gap-2">
          <.button
            size={:sm}
            phx-click="open_start_modal"
            title="Start agent instance"
          >
            Start Instance
          </.button>
          <.link
            navigate={@traces_path}
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-sm text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            <Lucideicons.activity class="w-4 h-4" /> Traces
          </.link>
        </div>
      </div>

      <.card>
        <div class="space-y-4">
          <div>
            <h2 class="text-xl font-semibold text-js-text">{humanize_agent_name(@agent.name)}</h2>
            <p class="text-sm text-js-text-muted mt-1">
              Select a running instance to open chat, settings, and threads.
            </p>
          </div>

          <%= if @instance_cards == [] do %>
            <.empty_state
              title="No running instances"
              description="Start an instance of this agent, then select it here."
            />
          <% else %>
            <div class="space-y-3">
              <div
                :for={instance <- @instance_cards}
                class="flex items-stretch gap-3"
              >
                <.link
                  navigate={instance.path}
                  class="group flex-1 rounded-lg border border-js-border bg-js-bg/30 px-4 py-3 hover:bg-js-bg-elevated transition-colors"
                >
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0 space-y-1.5">
                      <div class="flex items-center gap-2.5 flex-wrap">
                        <span class="text-sm text-js-text font-medium">{instance.summary.title}</span>
                        <.badge
                          :for={badge <- Map.get(instance.summary, :badges, [])}
                          variant={Map.get(badge, :variant, :default)}
                        >
                          {badge.label}
                        </.badge>
                      </div>
                      <div
                        :if={Map.get(instance.summary, :subtitle)}
                        class="text-xs text-js-text-subtle truncate leading-5"
                      >
                        {instance.summary.subtitle}
                      </div>
                      <ul class="mt-0.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-js-text-muted leading-5">
                        <li
                          :for={{label, value} <- Map.get(instance.summary, :meta, [])}
                          class="flex items-center gap-1 whitespace-nowrap"
                        >
                          <span class="text-js-text-subtle">{label}:</span>
                          <span>{value}</span>
                        </li>
                      </ul>
                    </div>
                    <span class="inline-flex items-center gap-1.5 rounded-md border border-js-border px-2.5 py-1.5 text-xs font-medium text-js-text-muted group-hover:text-js-text group-hover:border-js-primary/60">
                      Open <Lucideicons.chevron_right class="w-3 h-3" />
                    </span>
                  </div>
                </.link>
                <.link
                  navigate={instance.traces_path}
                  class="inline-flex min-w-[96px] shrink-0 items-center justify-center gap-1.5 rounded-lg border border-js-border px-3 py-2.5 text-xs font-medium text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
                >
                  <Lucideicons.activity class="w-3.5 h-3.5" />
                  <span>Traces</span>
                </.link>
              </div>
            </div>
          <% end %>
        </div>
      </.card>

      <.start_instance_modal
        show={@start_modal_open?}
        start_form={@start_form}
        start_form_schema={@start_form_schema}
        start_form_error={@start_form_error}
        starting_instance?={@starting_instance?}
      />
    </div>
    """
  end

  @impl true
  def render(
        %{agent: agent, live_action: action, active_instance_id: active_instance_id} = assigns
      )
      when not is_nil(agent) and action == :show and not is_nil(active_instance_id) do
    workbench_tab = assigns.workbench_tab || :chat
    summary_visible? = workbench_tab != :instance

    context_sections =
      thread_context_sections(
        assigns.sections_by_tab,
        assigns.persisted_thread_contexts,
        assigns.chat_state.active_thread_id,
        is_pid(assigns.active_instance_pid)
      )

    thread_scope_id = active_strategy_thread_id(assigns.runtime_status)

    thread_events =
      thread_events_for_display(
        assigns.instance_observability_events,
        thread_scope_id,
        assigns.live_event_query,
        assigns.live_event_limit
      )

    instance_events =
      instance_events_for_display(
        assigns.instance_event_stream,
        assigns.instance_event_query,
        assigns.live_event_limit
      )

    assigns =
      assigns
      |> assign(:active_messages, ChatSession.active_messages(assigns.chat_state))
      |> assign(:active_thread_name, ChatSession.active_thread_name(assigns.chat_state))
      |> assign(:runtime_messages, List.wrap(assigns.runtime_messages))
      |> assign(:runtime_todos, List.wrap(assigns.runtime_todos))
      |> assign(:instance_events, instance_events)
      |> assign(
        :interaction_signals,
        interaction_signals_for_display(
          assigns.interaction_model,
          assigns.show_advanced_signals?
        )
      )
      |> assign(
        :interaction_actions,
        interaction_actions_for_display(assigns.interaction_model)
      )
      |> assign(:selected_runner_target, RunnerForm.selected_target(assigns.runner_form))
      |> assign(:expanded_event_ids, assigns.expanded_event_ids || MapSet.new())
      |> assign(:workbench_tab, workbench_tab)
      |> assign(:summary_visible?, summary_visible?)
      |> assign(:workbench_grid_class, workbench_grid_class(summary_visible?))
      |> assign(:threads_rail_class, workbench_threads_rail_class(summary_visible?))
      |> assign(:thread_context_sections, context_sections)
      |> assign(:thread_events, thread_events)
      |> assign(:thread_scope_id, thread_scope_id)
      |> assign(:instance_online?, is_pid(assigns.active_instance_pid))
      |> assign(:module_path, agent_module_path(assigns.prefix, agent))
      |> assign(
        :traces_path,
        traces_path(assigns.prefix, agent, assigns.active_instance_id, assigns.active_instance_id)
      )
      |> assign(
        :instance_links,
        instance_links(
          assigns.prefix,
          agent,
          assigns.running_instances,
          assigns.active_instance_id
        )
      )
      |> assign(:summary_meta, summary_meta(assigns.runtime_status, assigns.ui_model))

    ~H"""
    <div
      class="p-3 lg:p-4 space-y-2 lg:flex-1 lg:min-h-0 lg:overflow-hidden lg:flex lg:flex-col"
      id="agent-workbench"
    >
      <div class="flex items-center justify-between border-b border-js-border pb-3 gap-3 shrink-0">
        <div class="flex items-center gap-2 text-sm text-js-text-muted">
          <.link navigate={scoped_path(@prefix <> "/agents")} class="hover:text-js-text">
            Agents
          </.link>
          <span>/</span>
          <.link navigate={@module_path} class="hover:text-js-text">
            {humanize_agent_name(@agent.name)}
          </.link>
          <span :if={@active_instance_id}>
            / <span class="text-js-text-subtle">{short_instance_id(@active_instance_id)}</span>
          </span>
          <.badge :if={@workspace_source == :persisted} variant={:warning}>
            Persisted Workspace
          </.badge>
          <.badge :if={not @instance_online?} variant={:default}>
            Instance Offline
          </.badge>
        </div>
        <div class="flex items-center gap-2">
          <.link
            navigate={@traces_path}
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-sm text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            <Lucideicons.activity class="w-4 h-4" /> Traces
          </.link>
        </div>
      </div>

      <div class={[@workbench_grid_class, "lg:flex-1 lg:min-h-0"]}>
        <.chat_threads_rail
          class={"min-h-[12rem] lg:min-h-0 lg:h-full #{@threads_rail_class || ""}"}
          threads={@chat_state.threads}
          active_thread_id={@chat_state.active_thread_id}
          messages_by_thread={@chat_state.messages_by_thread}
          chat_pending?={@chat_pending?}
        />

        <div class="min-h-[22rem] lg:min-h-0 lg:h-full flex flex-col gap-1.5">
          <div class="px-0.5">
            <div class="inline-flex min-h-9 w-full flex-wrap items-center gap-1 rounded-lg border border-js-border bg-js-bg-elevated px-1 py-1">
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="chat"
                class={workbench_tab_button_class(@workbench_tab == :chat)}
              >
                Chat
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="interact"
                class={workbench_tab_button_class(@workbench_tab == :interact)}
              >
                Interact
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="messages"
                class={workbench_tab_button_class(@workbench_tab == :messages)}
              >
                Messages
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="events"
                class={workbench_tab_button_class(@workbench_tab == :events)}
              >
                Events
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="todos"
                class={workbench_tab_button_class(@workbench_tab == :todos)}
              >
                TODOs
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="thread_context"
                class={workbench_tab_button_class(@workbench_tab == :thread_context)}
              >
                Thread Context
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="thread_events"
                class={workbench_tab_button_class(@workbench_tab == :thread_events)}
              >
                Thread Events
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="instance"
                class={workbench_tab_button_class(@workbench_tab == :instance)}
              >
                Instance
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="sub_agents"
                class={workbench_tab_button_class(@workbench_tab == :sub_agents)}
              >
                Sub-Agents
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="tasks"
                class={workbench_tab_button_class(@workbench_tab == :tasks)}
              >
                Tasks
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="tool_insights"
                class={workbench_tab_button_class(@workbench_tab == :tool_insights)}
              >
                Tool Insights
              </button>
              <button
                type="button"
                phx-click="select_workbench_tab"
                phx-value-panel="middleware"
                class={workbench_tab_button_class(@workbench_tab == :middleware)}
              >
                Middleware
              </button>
            </div>
          </div>

          <%= case @workbench_tab do %>
            <% :interact -> %>
              <.card class="min-h-0 h-full overflow-hidden p-0">
                <div class="px-3 py-2 border-b border-js-border">
                  <h3 class="text-sm font-medium text-js-text">Interact</h3>
                  <p class="text-xs text-js-text-muted mt-1">
                    Signal and action introspection with guarded runtime dispatch.
                  </p>
                </div>
                <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-3 flex-1 min-h-0">
                  <%= if @interaction_model.warnings != [] do %>
                    <div class="rounded-md border border-js-warning/40 bg-js-warning/10 p-2 space-y-1">
                      <p class="text-xs text-js-warning font-medium">Introspection warnings</p>
                      <p
                        :for={warning <- @interaction_model.warnings}
                        class="text-[11px] text-js-warning/90"
                      >
                        {warning}
                      </p>
                    </div>
                  <% end %>

                  <div class="grid grid-cols-1 xl:grid-cols-2 gap-3">
                    <div class="space-y-2">
                      <div class="flex items-center justify-between gap-2">
                        <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">
                          Consumed Signals
                        </h4>
                        <button
                          type="button"
                          phx-click="toggle_advanced_signals"
                          class="text-xs text-js-info hover:text-js-text"
                        >
                          {if(@show_advanced_signals?, do: "Hide advanced", else: "Show advanced")}
                        </button>
                      </div>
                      <%= if @interaction_signals == [] do %>
                        <.empty_state
                          title="No signal routes"
                          description="No runtime or static signal routes were discovered."
                        />
                      <% else %>
                        <div class="space-y-1.5">
                          <div
                            :for={signal <- @interaction_signals}
                            class={[
                              "rounded-md border px-2 py-2 bg-js-bg-elevated/30",
                              if(@selected_runner_target == {:signal, signal.key},
                                do: "border-js-info/60",
                                else: "border-js-border"
                              )
                            ]}
                          >
                            <div class="flex items-center justify-between gap-2">
                              <div class="text-xs font-mono text-js-text break-all">
                                {signal.signal_type}
                              </div>
                              <div class="flex items-center gap-1">
                                <.badge variant={
                                  if(signal.route_available?, do: :success, else: :warning)
                                }>
                                  {if(signal.route_available?, do: "runtime", else: "static")}
                                </.badge>
                                <.badge variant={if(signal.advanced?, do: :default, else: :info)}>
                                  {if(signal.advanced?, do: "advanced", else: "entry")}
                                </.badge>
                              </div>
                            </div>
                            <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                              src: {signal.source} / priority: {signal.priority} / target: {signal.target_summary}
                            </div>
                            <div
                              :if={is_integer(signal.last_seen_at)}
                              class="mt-1 text-[11px] text-js-text-subtle"
                            >
                              last seen:
                              <time data-js-ts={signal.last_seen_at} data-js-relative="true">
                                {format_event_timestamp(signal.last_seen_at)}
                              </time>
                            </div>
                            <button
                              type="button"
                              phx-click="select_signal"
                              phx-value-key={signal.key}
                              class="mt-2 inline-flex rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text"
                            >
                              Use Signal
                            </button>
                          </div>
                        </div>
                      <% end %>
                    </div>

                    <div class="space-y-2">
                      <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">
                        Action Schemas
                      </h4>
                      <%= if @interaction_actions == [] do %>
                        <.empty_state
                          title="No action schemas"
                          description="No route or plugin actions were discovered."
                        />
                      <% else %>
                        <div class="space-y-1.5">
                          <div
                            :for={action <- @interaction_actions}
                            class={[
                              "rounded-md border px-2 py-2 bg-js-bg-elevated/30",
                              if(@selected_runner_target == {:action, action.key},
                                do: "border-js-info/60",
                                else: "border-js-border"
                              )
                            ]}
                          >
                            <div class="flex items-center justify-between gap-2">
                              <div class="text-xs text-js-text font-mono break-all">
                                {action.label}
                              </div>
                              <.badge variant={
                                if(action.convertible_schema?, do: :success, else: :warning)
                              }>
                                {if(action.convertible_schema?, do: "schema ok", else: "raw fallback")}
                              </.badge>
                            </div>
                            <p
                              :if={is_binary(action.doc)}
                              class="mt-1 text-[11px] text-js-text-subtle"
                            >
                              {action.doc}
                            </p>
                            <div class="mt-1 text-[11px] text-js-text-subtle">
                              required: {if(action.required_fields == [],
                                do: "none",
                                else: Enum.join(action.required_fields, ", ")
                              )}
                            </div>
                            <div
                              :if={action.schema_error}
                              class="mt-1 text-[11px] text-js-warning"
                            >
                              {action.schema_error}
                            </div>
                            <button
                              type="button"
                              phx-click="select_action"
                              phx-value-key={action.key}
                              class="mt-2 inline-flex rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text"
                            >
                              Use Action
                            </button>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <div class="rounded-md border border-js-border bg-js-bg-elevated/20 p-3 space-y-2">
                    <div class="flex items-center justify-between gap-2">
                      <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">Runner</h4>
                      <.badge variant={
                        if(@interaction_model.dispatch_available?, do: :success, else: :warning)
                      }>
                        {if(@interaction_model.dispatch_available?,
                          do: "instance online",
                          else: "instance offline"
                        )}
                      </.badge>
                    </div>
                    <div class="text-xs text-js-text-muted">
                      Selected:
                      <span class="font-mono text-js-text">
                        <%= case @selected_runner_target do %>
                          <% {:signal, key} -> %>
                            signal {key}
                          <% {:action, key} -> %>
                            action {key}
                          <% _ -> %>
                            none
                        <% end %>
                      </span>
                    </div>

                    <form phx-change="update_runner_payload" class="space-y-2">
                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                        <label class="text-xs text-js-text-muted">
                          Dispatch Mode
                          <select
                            name="runner[dispatch_mode]"
                            class="mt-1 w-full rounded-md border border-js-border bg-js-bg px-2 py-1.5 text-xs text-js-text"
                          >
                            <option value="sync" selected={@runner_form.dispatch_mode == "sync"}>
                              sync
                            </option>
                            <option value="async" selected={@runner_form.dispatch_mode == "async"}>
                              async
                            </option>
                          </select>
                        </label>
                        <label class="text-xs text-js-text-muted">
                          Schema View
                          <select
                            name="runner[schema_mode]"
                            class="mt-1 w-full rounded-md border border-js-border bg-js-bg px-2 py-1.5 text-xs text-js-text"
                          >
                            <option value="fields" selected={@runner_form.schema_mode == "fields"}>
                              fields
                            </option>
                            <option value="raw" selected={@runner_form.schema_mode == "raw"}>
                              raw
                            </option>
                          </select>
                        </label>
                      </div>
                      <label class="text-xs text-js-text-muted block">
                        Payload JSON <textarea
                          name="runner[payload_json]"
                          rows="8"
                          class="mt-1 w-full rounded-md border border-js-border bg-js-bg p-2 text-xs text-js-text font-mono"
                        ><%= @runner_form.payload_json %></textarea>
                      </label>
                    </form>

                    <div class="flex flex-wrap items-center gap-2">
                      <button
                        type="button"
                        phx-click="arm_runner_execute"
                        class={
                          if(@runner_form.guard_armed?,
                            do:
                              "inline-flex rounded-md border border-js-success/40 bg-js-success/10 px-2.5 py-1 text-xs text-js-success",
                            else:
                              "inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text"
                          )
                        }
                      >
                        {if(@runner_form.guard_armed?, do: "Armed", else: "Arm Execute")}
                      </button>
                      <button
                        type="button"
                        phx-click="run_selected_interaction"
                        disabled={!RunnerForm.can_execute?(@runner_form)}
                        class="inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        Run
                      </button>
                      <button
                        type="button"
                        phx-click="clear_runner_history"
                        class="inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text"
                      >
                        Clear History
                      </button>
                    </div>

                    <pre
                      :if={@runner_result}
                      class="text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"
                    ><%= inspect(@runner_result, pretty: true, limit: 120, printable_limit: 20_000) %></pre>

                    <%= if @runner_history != [] do %>
                      <div class="space-y-1.5">
                        <p class="text-[11px] uppercase tracking-wider text-js-text-subtle">
                          Recent Runs
                        </p>
                        <div
                          :for={entry <- @runner_history}
                          class="rounded border border-js-border bg-js-bg/60 px-2 py-1.5 text-[11px] text-js-text-subtle font-mono"
                        >
                          <span>{entry[:mode]} {entry[:signal_type]}</span>
                          <span class="mx-1">/</span>
                          <time data-js-ts={entry[:timestamp_ms]} data-js-relative="true">
                            {format_event_timestamp(entry[:timestamp_ms])}
                          </time>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              </.card>
            <% :messages -> %>
              <.card class="min-h-0 h-full overflow-hidden p-0">
                <div class="px-3 py-2 border-b border-js-border">
                  <h3 class="text-sm font-medium text-js-text">Messages</h3>
                  <p class="text-xs text-js-text-muted mt-1">
                    Normalized runtime thread messages including tool calls and thinking blocks.
                  </p>
                </div>
                <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
                  <%= if @runtime_messages == [] do %>
                    <.empty_state
                      title="No runtime messages"
                      description="Send a message or run strategy steps to capture a thread snapshot."
                    />
                  <% else %>
                    <div
                      :for={message <- @runtime_messages}
                      class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
                    >
                      <div class="flex items-center justify-between gap-2">
                        <span class="text-xs font-medium text-js-text">
                          {message[:role] || :unknown}
                        </span>
                        <.badge variant={
                          if(message[:status] in ["error", :error], do: :error, else: :default)
                        }>
                          {message[:status] || "ok"}
                        </.badge>
                      </div>
                      <div class="mt-1 text-xs text-js-text-muted whitespace-pre-wrap break-words">
                        <%= case message[:content] do %>
                          <% content when is_binary(content) -> %>
                            {content}
                          <% content when is_list(content) -> %>
                            <div :for={part <- content} class="mb-1">
                              <span
                                :if={part[:type] == :thinking}
                                class="inline-flex rounded bg-js-info/10 px-1.5 py-0.5 text-[11px] text-js-info mr-1"
                              >
                                thinking
                              </span>
                              <span>{part[:content] || inspect(part[:data], limit: 40)}</span>
                            </div>
                          <% other -> %>
                            {inspect(other, pretty: true, limit: 40)}
                        <% end %>
                      </div>
                      <div :if={message[:tool_calls] != []} class="mt-2 space-y-1">
                        <div class="text-[11px] uppercase tracking-wider text-js-text-subtle">
                          Tool Calls
                        </div>
                        <div
                          :for={call <- message[:tool_calls]}
                          class="text-xs text-js-text-subtle font-mono"
                        >
                          {call[:name]} ({call[:call_id]})
                        </div>
                      </div>
                      <div :if={message[:tool_results] != []} class="mt-2 space-y-1">
                        <div class="text-[11px] uppercase tracking-wider text-js-text-subtle">
                          Tool Results
                        </div>
                        <div
                          :for={result <- message[:tool_results]}
                          class="text-xs text-js-text-subtle font-mono"
                        >
                          {result[:name]} [{result[:status] || "ok"}]
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </.card>
            <% :events -> %>
              <.card class="min-h-0 h-full overflow-hidden p-0">
                <div class="px-3 py-2 border-b border-js-border flex items-center justify-between gap-2">
                  <div>
                    <h3 class="text-sm font-medium text-js-text">Events</h3>
                    <p class="text-xs text-js-text-muted mt-1">
                      Merged event stream with expandable raw telemetry payloads.
                    </p>
                  </div>
                  <.link
                    :if={@traces_path}
                    navigate={@traces_path}
                    class="text-xs text-js-info hover:text-js-text transition-colors"
                  >
                    Open Traces
                  </.link>
                </div>
                <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
                  <form phx-change="update_instance_event_query" class="mb-2">
                    <input
                      type="text"
                      name="query"
                      value={@instance_event_query}
                      placeholder="Search merged events"
                      class="w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text focus:outline-none focus:ring-2 focus:ring-js-ring"
                    />
                  </form>
                  <%= if @instance_events == [] do %>
                    <.empty_state
                      title="No merged events"
                      description="Run an interaction to populate event telemetry."
                    />
                  <% else %>
                    <div
                      :for={event <- @instance_events}
                      class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
                    >
                      <div class="flex items-center justify-between gap-2">
                        <time
                          class="text-[11px] font-mono text-js-text-subtle"
                          data-js-ts={event[:timestamp_ms]}
                          data-js-relative="true"
                        >
                          {format_event_timestamp(event[:timestamp_ms])}
                        </time>
                        <div class="flex items-center gap-1">
                          <.badge variant={
                            if(event[:source] == :agent_debug, do: :warning, else: :info)
                          }>
                            {event[:source] || :telemetry}
                          </.badge>
                          <.badge :if={(event[:chunk_count] || 1) > 1} variant={:default}>
                            {event[:chunk_count]} chunks
                          </.badge>
                        </div>
                      </div>
                      <div class="mt-1 text-xs text-js-text font-mono break-all">
                        {format_event_name(event)}
                      </div>
                      <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                        call: {event[:call_id] || "n/a"} / task: {event[:task_id] || "n/a"}
                      </div>
                      <button
                        type="button"
                        phx-click="toggle_event_row"
                        phx-value-id={event[:id]}
                        class="mt-2 text-xs text-js-info hover:text-js-text transition-colors"
                      >
                        <%= if MapSet.member?(@expanded_event_ids, event[:id]) do %>
                          Hide Raw
                        <% else %>
                          Show Raw
                        <% end %>
                      </button>
                      <pre
                        :if={MapSet.member?(@expanded_event_ids, event[:id])}
                        class="mt-2 text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"
                      ><%= inspect(event[:raw] || event, pretty: true, limit: 120, printable_limit: 20_000) %></pre>
                    </div>
                  <% end %>
                </div>
              </.card>
            <% :todos -> %>
              <.card class="min-h-0 h-full overflow-hidden p-0">
                <div class="px-3 py-2 border-b border-js-border">
                  <h3 class="text-sm font-medium text-js-text">TODOs</h3>
                  <p class="text-xs text-js-text-muted mt-1">
                    Strategy TODO list with fallback to tracked tasks.
                  </p>
                </div>
                <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
                  <%= if @runtime_todos == [] do %>
                    <.empty_state
                      title="No TODOs"
                      description="No strategy TODO state was found for this instance."
                    />
                  <% else %>
                    <div
                      :for={todo <- @runtime_todos}
                      class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
                    >
                      <div class="flex items-center justify-between gap-2">
                        <span class="text-xs text-js-text">{todo[:content]}</span>
                        <.badge variant={todo_badge_variant(todo[:status])}>
                          {todo[:status] || :pending}
                        </.badge>
                      </div>
                      <div
                        :if={todo[:active_form]}
                        class="mt-1 text-[11px] text-js-text-subtle font-mono"
                      >
                        active_form: {todo[:active_form]}
                      </div>
                    </div>
                  <% end %>
                </div>
              </.card>
            <% :thread_context -> %>
              <.card class="min-h-0 h-full overflow-hidden p-0">
                <div class="px-3 py-2 border-b border-js-border">
                  <h3 class="text-sm font-medium text-js-text">Thread Context</h3>
                  <p class="text-xs text-js-text-muted mt-1">
                    Context snapshot for the active thread and strategy state.
                  </p>
                </div>
                <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-3.5 flex-1 min-h-0">
                  <%= if @thread_context_sections == [] do %>
                    <.empty_state
                      title="No context available"
                      description="Context appears after the strategy reports runtime state."
                    />
                  <% else %>
                    <.detail_section
                      :for={section <- @thread_context_sections}
                      section={section}
                    />
                  <% end %>
                </div>
              </.card>
            <% :thread_events -> %>
              <.card class="min-h-0 h-full overflow-hidden p-0">
                <div class="px-3 py-2 border-b border-js-border flex items-center justify-between gap-2">
                  <div>
                    <h3 class="text-sm font-medium text-js-text">Thread Events</h3>
                    <p class="text-xs text-js-text-muted mt-1">
                      Event stream scoped to this thread when metadata includes thread IDs.
                    </p>
                  </div>
                  <.link
                    :if={@traces_path}
                    navigate={@traces_path}
                    class="text-xs text-js-info hover:text-js-text transition-colors"
                  >
                    Open Traces
                  </.link>
                </div>
                <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
                  <form phx-change="update_live_event_query" class="mb-2">
                    <input
                      type="text"
                      name="query"
                      value={@live_event_query}
                      placeholder="Search events"
                      class="w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text focus:outline-none focus:ring-2 focus:ring-js-ring"
                    />
                  </form>
                  <p :if={@thread_scope_id} class="text-xs text-js-text-subtle">
                    Thread ID: <span class="font-mono text-js-text">{@thread_scope_id}</span>
                  </p>
                  <%= if @thread_events == [] do %>
                    <.empty_state
                      title="No thread events"
                      description="Send a message and tool call activity will appear here."
                    />
                  <% else %>
                    <div
                      :for={event <- @thread_events}
                      class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
                    >
                      <div class="flex items-center justify-between gap-2">
                        <time
                          class="text-[11px] font-mono text-js-text-subtle"
                          data-js-ts={event[:timestamp_ms]}
                          data-js-relative="true"
                        >
                          {format_event_timestamp(event[:timestamp_ms])}
                        </time>
                        <.badge variant={
                          if(event[:source] == :agent_debug, do: :warning, else: :info)
                        }>
                          {event[:source] || :telemetry}
                        </.badge>
                      </div>
                      <div class="mt-1 text-xs text-js-text font-mono truncate">
                        {format_event_name(event)}
                      </div>
                    </div>
                  <% end %>
                </div>
              </.card>
            <% :instance -> %>
              <.settings_pane
                class="min-h-[20rem] lg:min-h-0 lg:h-full"
                agent={@agent}
                detail_tab={@detail_tab}
                detail_tabs={@detail_tabs}
                sections_by_tab={@sections_by_tab}
                system_prompt={@system_prompt}
                module_path={@module_path}
                instance_links={@instance_links}
                active_instance_id={@active_instance_id}
                active_instance_pid={@active_instance_pid}
                traces_path={@traces_path}
                instance_debug_enabled?={@instance_debug_enabled?}
                instance_debug_level={@instance_debug_level}
                instance_debug_error={@instance_debug_error}
                instance_observability_events={@instance_observability_events}
              />
            <% :sub_agents -> %>
              <.card class="min-h-0 h-full overflow-hidden p-0">
                <div class="px-3 py-2 border-b border-js-border">
                  <h3 class="text-sm font-medium text-js-text">Sub-Agents</h3>
                  <p class="text-xs text-js-text-muted mt-1">
                    Delegated child agent activity inferred from runtime traces.
                  </p>
                </div>
                <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
                  <%= if @subagents == [] do %>
                    <.empty_state
                      title="No sub-agent records"
                      description="No delegation metadata was found for this instance."
                    />
                  <% else %>
                    <div
                      :for={sub <- @subagents}
                      class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
                    >
                      <div class="flex items-center justify-between gap-2">
                        <div class="min-w-0">
                          <span class="text-xs text-js-text font-mono break-all">{sub.agent_id}</span>
                          <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                            parent: {sub.parent_agent_id}
                          </div>
                        </div>
                        <div class="flex items-center gap-2">
                          <.badge variant={
                            if(sub.status in ["error", :error], do: :error, else: :info)
                          }>
                            {sub.status || "running"}
                          </.badge>
                          <button
                            type="button"
                            phx-click="toggle_subagent_row"
                            phx-value-id={sub.agent_id}
                            class="text-xs text-js-info hover:text-js-text transition-colors"
                          >
                            <%= if @expanded_subagent_id == sub.agent_id do %>
                              Collapse
                            <% else %>
                              Expand
                            <% end %>
                          </button>
                        </div>
                      </div>

                      <div
                        :if={@expanded_subagent_id == sub.agent_id}
                        class="mt-3 border-t border-js-border pt-2.5 space-y-2"
                      >
                        <div class="inline-flex gap-1 rounded-md border border-js-border bg-js-bg px-1 py-1">
                          <button
                            :for={tab <- ["config", "messages", "middleware", "tools", "events"]}
                            type="button"
                            phx-click="select_subagent_detail_tab"
                            phx-value-tab={tab}
                            class={[
                              "rounded px-2 py-1 text-[11px] transition-colors",
                              if(@subagent_detail_tab == tab,
                                do: "bg-js-muted text-js-text",
                                else: "text-js-text-muted hover:text-js-text"
                              )
                            ]}
                          >
                            {String.capitalize(tab)}
                          </button>
                        </div>

                        <%= case @subagent_detail_tab do %>
                          <% "messages" -> %>
                            <pre class="text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"><%= inspect(sub[:messages] || [], pretty: true, limit: 120, printable_limit: 20_000) %></pre>
                          <% "middleware" -> %>
                            <pre class="text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"><%= inspect(sub[:middleware] || [], pretty: true, limit: 120, printable_limit: 20_000) %></pre>
                          <% "tools" -> %>
                            <pre class="text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"><%= inspect(sub[:tools] || [], pretty: true, limit: 120, printable_limit: 20_000) %></pre>
                          <% "events" -> %>
                            <%= if Map.get(@subagent_events, sub.agent_id, []) == [] do %>
                              <p class="text-xs text-js-text-subtle">
                                No trace events available for this sub-agent.
                              </p>
                            <% else %>
                              <div class="space-y-1">
                                <div
                                  :for={event <- Map.get(@subagent_events, sub.agent_id, [])}
                                  class="rounded border border-js-border bg-js-bg/70 px-2 py-1.5"
                                >
                                  <div class="flex items-center justify-between gap-2">
                                    <time
                                      class="text-[11px] font-mono text-js-text-subtle"
                                      data-js-ts={event[:timestamp_ms]}
                                      data-js-relative="true"
                                    >
                                      {format_event_timestamp(event[:timestamp_ms])}
                                    </time>
                                    <.badge variant={:default}>{event[:type] || "event"}</.badge>
                                  </div>
                                  <div class="mt-1 text-[11px] font-mono text-js-text break-all">
                                    {event[:event_name] || format_event_name(event)}
                                  </div>
                                </div>
                              </div>
                            <% end %>
                          <% _ -> %>
                            <div class="space-y-1 text-[11px] text-js-text-muted">
                              <div>
                                <span class="text-js-text-subtle">name:</span> {sub[:name] || "n/a"}
                              </div>
                              <div>
                                <span class="text-js-text-subtle">model:</span> {sub[:model] || "n/a"}
                              </div>
                              <div>
                                <span class="text-js-text-subtle">duration:</span> {sub[:duration_ms] ||
                                  0}ms
                              </div>
                              <div>
                                <span class="text-js-text-subtle">updated:</span>
                                <time data-js-ts={sub[:updated_at]} data-js-relative="true">
                                  {format_event_timestamp(sub[:updated_at])}
                                </time>
                              </div>
                              <div>
                                <span class="text-js-text-subtle">result:</span> {sub[:result] ||
                                  "n/a"}
                              </div>
                              <div :if={sub[:error]}>
                                <span class="text-js-text-subtle">error:</span> {inspect(sub[:error],
                                  limit: 40
                                )}
                              </div>
                              <div :if={is_map(sub[:token_usage])}>
                                <span class="text-js-text-subtle">token_usage:</span> {inspect(
                                  sub[:token_usage],
                                  limit: 20
                                )}
                              </div>
                            </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </.card>
            <% :tasks -> %>
              <.card class="min-h-0 h-full overflow-hidden p-0">
                <div class="px-3 py-2 border-b border-js-border">
                  <h3 class="text-sm font-medium text-js-text">Tasks</h3>
                  <p class="text-xs text-js-text-muted mt-1">
                    Task lifecycle inferred from scheduler/signal/directive events.
                  </p>
                </div>
                <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
                  <%= if @tasks == [] do %>
                    <.empty_state
                      title="No task records"
                      description="No task IDs were observed for this instance."
                    />
                  <% else %>
                    <div
                      :for={task <- @tasks}
                      class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
                    >
                      <div class="flex items-center justify-between gap-2">
                        <span class="text-xs text-js-text font-mono">{task.task_id}</span>
                        <.badge variant={task_badge_variant(task.task_status || task.status)}>
                          {task.task_status || task.status || "running"}
                        </.badge>
                      </div>
                      <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                        trace: {task.trace_id || "n/a"} / span: {task.span_id || "n/a"}
                      </div>
                    </div>
                  <% end %>
                </div>
              </.card>
            <% :tool_insights -> %>
              <.card class="min-h-0 h-full overflow-hidden p-0">
                <div class="px-3 py-2 border-b border-js-border">
                  <h3 class="text-sm font-medium text-js-text">Tool Insights</h3>
                  <p class="text-xs text-js-text-muted mt-1">
                    Call counts, failures, and p95 durations for observed tool runs.
                  </p>
                </div>
                <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
                  <%= if @tool_insights == [] do %>
                    <.empty_state
                      title="No tool runs"
                      description="Tool usage appears here after runtime tool invocations."
                    />
                  <% else %>
                    <div
                      :for={run <- @tool_insights}
                      class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
                    >
                      <div class="flex items-center justify-between gap-2">
                        <span class="text-xs text-js-text font-mono">
                          {run.tool_name || run.call_id}
                        </span>
                        <.badge variant={if(run.failure_count > 0, do: :warning, else: :success)}>
                          p95 {run.p95_duration_ms || 0}ms
                        </.badge>
                      </div>
                      <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                        calls: {run.call_count || 0} / failures: {run.failure_count || 0}
                      </div>
                      <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                        last: {run.last_status || "n/a"} / duration: {run.last_duration_ms || 0}ms
                      </div>
                      <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                        action: {run.action || "n/a"} / workflow: {run.workflow_id || "n/a"}
                      </div>
                      <.link
                        :if={
                          tool_trace_path(
                            @traces_path,
                            @active_instance_id,
                            run.call_id,
                            run.trace_id
                          )
                        }
                        navigate={
                          tool_trace_path(
                            @traces_path,
                            @active_instance_id,
                            run.call_id,
                            run.trace_id
                          )
                        }
                        class="mt-1 inline-flex text-[11px] text-js-info hover:text-js-text"
                      >
                        Open Trace
                      </.link>
                    </div>
                  <% end %>
                </div>
              </.card>
            <% :middleware -> %>
              <.card class="min-h-0 h-full overflow-hidden p-0">
                <div class="px-3 py-2 border-b border-js-border">
                  <h3 class="text-sm font-medium text-js-text">Middleware</h3>
                  <p class="text-xs text-js-text-muted mt-1">
                    Latest middleware chain snapshots and invocation timing.
                  </p>
                </div>
                <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-2.5 flex-1 min-h-0">
                  <%= if @middleware_snapshots == [] do %>
                    <.empty_state
                      title="No middleware snapshots"
                      description="Middleware data appears when runtime metadata includes chain details."
                    />
                  <% else %>
                    <div
                      :for={snapshot <- @middleware_snapshots}
                      class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2.5 py-2"
                    >
                      <div class="flex items-center justify-between gap-2">
                        <span class="text-xs text-js-text font-mono">
                          {snapshot.entity_id || "middleware"}
                        </span>
                        <.badge variant={:default}>{snapshot.last_duration_ms || 0}ms</.badge>
                      </div>
                      <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                        {Enum.join(snapshot.middleware_chain || [], " -> ")}
                      </div>
                      <div class="mt-1 text-[11px] text-js-text-subtle font-mono">
                        invoked:
                        <time
                          data-js-ts={snapshot.last_invoked_at || snapshot.updated_at}
                          data-js-relative="true"
                        >
                          {format_event_timestamp(snapshot.last_invoked_at || snapshot.updated_at)}
                        </time>
                      </div>
                      <pre
                        :if={
                          is_map(snapshot.config_snapshot) and map_size(snapshot.config_snapshot) > 0
                        }
                        class="mt-1 text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 whitespace-pre-wrap break-words overflow-x-auto"
                      ><%= inspect(snapshot.config_snapshot, pretty: true, limit: 60) %></pre>
                    </div>
                  <% end %>
                </div>
              </.card>
            <% _ -> %>
              <div class="min-h-0 h-full flex flex-col gap-2">
                <div
                  :if={not @chat_enabled? and @interaction_model.runner_supported?}
                  class="rounded-md border border-js-info/40 bg-js-info/10 px-3 py-2 text-xs text-js-info flex items-center justify-between gap-2"
                >
                  <span>
                    This instance does not expose chat. Use signal/action interaction instead.
                  </span>
                  <button
                    type="button"
                    phx-click="select_workbench_tab"
                    phx-value-panel="interact"
                    class="inline-flex rounded-md border border-js-info/50 px-2 py-1 text-[11px] hover:text-js-text"
                  >
                    Open Interact
                  </button>
                </div>
                <.chat_conversation_panel
                  class="min-h-0 h-full"
                  thread_name={@active_thread_name}
                  draft_message={@draft_message}
                  active_messages={@active_messages}
                  chat_pending?={@chat_pending?}
                  chat_enabled?={@chat_enabled?}
                  placeholder={@chat_config.placeholder}
                  empty_title={@chat_config.empty_title}
                  empty_description={@chat_config.empty_description}
                  model_label={@chat_config.model_label || @ui_model}
                  provider_options={@chat_provider_options}
                  provider_value={@chat_provider}
                  model_options={@chat_model_options}
                  model_value={@chat_model}
                  traces_path={@traces_path}
                />
              </div>
          <% end %>
        </div>

        <.summary_pane
          :if={@summary_visible?}
          class="min-h-[16rem] lg:min-h-0 lg:h-full"
          agent={@agent}
          module_path={@module_path}
          instance_links={@instance_links}
          active_instance_id={@active_instance_id}
          instance_debug_enabled?={@instance_debug_enabled?}
          instance_debug_level={@instance_debug_level}
          instance_debug_error={@instance_debug_error}
          traces_path={@traces_path}
          summary_meta={@summary_meta}
          instance_observability_events={@instance_observability_events}
          triage_links={@triage_links}
        />
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Agents" subtitle="Manage and interact with your AI agents">
        <:actions>
          <.button size={:sm} phx-click="refresh">Refresh</.button>
        </:actions>
      </.page_header>

      <div
        :if={not @jido_configured?}
        class="bg-js-warning/10 border border-js-warning/30 rounded-lg p-4"
      >
        <p class="text-sm text-js-warning">
          No Jido instance configured. Showing discovered agent modules only.
          Set
          <code class="bg-js-bg-elevated px-1 rounded">
            config :jido_studio, jido_instance: MyApp.Jido
          </code>
          to enable runtime agent management.
        </p>
      </div>

      <form phx-change="set_timezone" class="hidden" data-js-timezone-form>
        <input
          type="hidden"
          name="timezone"
          value={@user_timezone}
          data-js-timezone-input
        />
      </form>

      <.card>
        <div class="flex items-center justify-between gap-3 mb-3">
          <h3 class="text-sm font-medium text-js-text">Live Ops Scope</h3>
          <.badge variant={if(@live_ops_realtime?, do: :success, else: :warning)}>
            {if(@live_ops_realtime?, do: "event-driven", else: "polling fallback")}
          </.badge>
        </div>
        <form phx-change="update_scope_filters" class="grid grid-cols-1 md:grid-cols-3 gap-2">
          <label class="text-xs text-js-text-muted">
            Project ID
            <input
              type="text"
              name="scope[project_id]"
              value={@scope_filters.project_id || ""}
              placeholder="project scope"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
          <label class="text-xs text-js-text-muted">
            User ID
            <input
              type="text"
              name="scope[user_id]"
              value={@scope_filters.user_id || ""}
              placeholder="user scope"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
          <label class="text-xs text-js-text-muted">
            Agent ID
            <input
              type="text"
              name="scope[agent_id]"
              value={@scope_filters.agent_id || ""}
              placeholder="instance filter"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
        </form>

        <div class="mt-3 flex flex-wrap items-center gap-2">
          <button
            type="button"
            phx-click="toggle_auto_follow_instances"
            class={
              if(@auto_follow_instances?,
                do:
                  "inline-flex rounded-md border border-js-success/40 bg-js-success/10 px-2.5 py-1 text-xs text-js-success",
                else:
                  "inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text"
              )
            }
          >
            Auto-follow {if(@auto_follow_instances?, do: "on", else: "off")}
          </button>
          <.badge :if={@followed_instance_id} variant={:info}>
            Following: {short_instance_id(@followed_instance_id)}
          </.badge>
          <button
            :if={@followed_instance_id}
            type="button"
            phx-click="unfollow_instance"
            class="inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text"
          >
            Unfollow
          </button>
        </div>

        <form
          phx-change="update_auto_follow_target"
          class="mt-3 grid grid-cols-1 md:grid-cols-3 gap-2"
        >
          <label class="text-xs text-js-text-muted">
            Auto-follow Instance
            <input
              type="text"
              name="target[instance_id]"
              value={@auto_follow_target.instance_id || ""}
              placeholder="instance id"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
          <label class="text-xs text-js-text-muted">
            Auto-follow Project
            <input
              type="text"
              name="target[project_id]"
              value={@auto_follow_target.project_id || ""}
              placeholder="project id"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
          <label class="text-xs text-js-text-muted">
            Auto-follow User
            <input
              type="text"
              name="target[user_id]"
              value={@auto_follow_target.user_id || ""}
              placeholder="user id"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
        </form>
      </.card>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.stat_card label="Discovered Agents" value={to_string(length(@agents))} />
        <.stat_card label="Running" value={to_string(@running_count)} />
        <.stat_card label="Active Instances" value={to_string(length(@filtered_instances || []))} />
        <.stat_card
          label="Available"
          value={to_string(Enum.count(@agents, &(&1.status == :available)))}
        />
      </div>

      <.card>
        <div class="flex items-center justify-between gap-3 mb-3">
          <h3 class="text-sm font-medium text-js-text">Active Instances</h3>
          <.badge variant={if(@live_ops_presence?, do: :success, else: :warning)}>
            {if(@live_ops_presence?, do: "presence viewers", else: "viewer fallback: 0")}
          </.badge>
        </div>

        <form phx-change="update_instance_filters" class="grid grid-cols-1 md:grid-cols-4 gap-2 mb-3">
          <label class="text-xs text-js-text-muted">
            Status
            <select
              name="filters[status_filter]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="all" selected={@agent_filters.status_filter == "all"}>All</option>
              <option value="running" selected={@agent_filters.status_filter == "running"}>
                Running
              </option>
              <option value="idle" selected={@agent_filters.status_filter == "idle"}>Idle</option>
              <option value="interrupted" selected={@agent_filters.status_filter == "interrupted"}>
                Interrupted
              </option>
              <option value="error" selected={@agent_filters.status_filter == "error"}>Error</option>
              <option value="offline" selected={@agent_filters.status_filter == "offline"}>
                Offline
              </option>
            </select>
          </label>
          <label class="text-xs text-js-text-muted">
            Presence
            <select
              name="filters[presence_filter]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="all" selected={@agent_filters.presence_filter == "all"}>All</option>
              <option value="has_viewers" selected={@agent_filters.presence_filter == "has_viewers"}>
                Has Viewers
              </option>
              <option value="no_viewers" selected={@agent_filters.presence_filter == "no_viewers"}>
                No Viewers
              </option>
            </select>
          </label>
          <label class="text-xs text-js-text-muted">
            Search
            <input
              type="text"
              name="filters[search_query]"
              value={@agent_filters.search_query}
              placeholder="instance, agent, scope"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
          <label class="text-xs text-js-text-muted">
            Sort
            <select
              name="filters[sort_by]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="last_activity" selected={@agent_filters.sort_by == "last_activity"}>
                Last Activity
              </option>
              <option value="viewers" selected={@agent_filters.sort_by == "viewers"}>Viewers</option>
              <option value="uptime" selected={@agent_filters.sort_by == "uptime"}>Uptime</option>
              <option value="name" selected={@agent_filters.sort_by == "name"}>Name</option>
              <option value="status" selected={@agent_filters.sort_by == "status"}>Status</option>
            </select>
          </label>
        </form>

        <%= if @filtered_instances == [] do %>
          <.empty_state
            title="No active instances"
            description="No running instances match your scope and filter settings."
          />
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full">
              <thead>
                <tr class="bg-js-bg-surface border-b border-js-border">
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Instance
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Agent
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Status
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Last Activity
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Uptime
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Viewers
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Scope
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-js-border">
                <tr
                  :for={row <- @filtered_instances}
                  class="hover:bg-js-bg-elevated/40 transition-colors"
                >
                  <td class="px-3 py-2 text-xs text-js-text font-mono">
                    <span :if={@followed_instance_id == row.instance_id} class="text-js-success mr-1">
                      ●
                    </span>
                    {short_instance_id(row.instance_id)}
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text">
                    <div class="flex items-center gap-1.5">
                      <.link
                        :if={active_instance_path(@prefix, row)}
                        navigate={active_instance_path(@prefix, row)}
                        class="hover:text-js-primary transition-colors"
                      >
                        {humanize_agent_name(row.agent_name || row.agent_slug || "Agent")}
                      </.link>
                      <span :if={is_nil(active_instance_path(@prefix, row))}>
                        {humanize_agent_name(row.agent_name || row.agent_slug || "Agent")}
                      </span>
                      <.badge :if={internal_instance?(row)} variant={:warning}>
                        internal
                      </.badge>
                    </div>
                  </td>
                  <td class="px-3 py-2 text-xs">
                    <.badge variant={status_badge_variant(row.status)}>{row.status}</.badge>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-muted">
                    <time
                      data-js-ts={datetime_to_unix_ms(row.last_activity_at)}
                      data-js-relative={
                        if(datetime_to_unix_ms(row.last_activity_at), do: "true", else: "false")
                      }
                    >
                      {format_datetime(row.last_activity_at)}
                    </time>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-muted">
                    <span data-js-uptime-ms={row.uptime_ms || ""}>
                      {format_uptime(row.uptime_ms)}
                    </span>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text">{row.viewer_count || 0}</td>
                  <td class="px-3 py-2 text-xs text-js-text-muted font-mono">
                    {row.project_id || "n/a"} / {row.user_id || "n/a"}
                  </td>
                  <td class="px-3 py-2 text-xs">
                    <div class="flex items-center gap-1">
                      <button
                        :if={@followed_instance_id != row.instance_id}
                        type="button"
                        phx-click="follow_instance"
                        phx-value-id={row.instance_id}
                        class="inline-flex rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text"
                      >
                        Follow
                      </button>
                      <button
                        :if={@followed_instance_id == row.instance_id}
                        type="button"
                        phx-click="unfollow_instance"
                        class="inline-flex rounded-md border border-js-success/40 bg-js-success/10 px-2 py-1 text-[11px] text-js-success"
                      >
                        Following
                      </button>
                      <.link
                        :if={active_instance_path(@prefix, row)}
                        navigate={active_instance_path(@prefix, row)}
                        class="inline-flex rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text"
                      >
                        Open
                      </.link>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </.card>

      <%= if @product_agents == [] and @internal_agents == [] do %>
        <.card>
          <.empty_state
            title="No agents discovered"
            description="No agent modules were found. Make sure your application includes Jido agent definitions."
          />
        </.card>
      <% else %>
        <.card>
          <div class="flex items-center justify-between gap-2 mb-3">
            <h3 class="text-sm font-medium text-js-text">Product Agents</h3>
            <.badge variant={:default}>{length(@product_agents)}</.badge>
          </div>
          <.data_table rows={@product_agents} scroll_x={false}>
            <:col :let={agent} label="Name">
              <.link
                navigate={agent_module_path(@prefix, agent)}
                class="text-js-text font-medium hover:text-js-primary transition-colors"
              >
                {humanize_agent_name(agent.name)}
              </.link>
            </:col>
            <:col :let={agent} label="Description">
              <span class="text-xs text-js-text-muted truncate max-w-md block">
                {agent.description}
              </span>
            </:col>
            <:col :let={agent} label="Tags">
              <div class="flex flex-wrap gap-1">
                <.badge :for={tag <- agent.tags || []}>{tag}</.badge>
              </div>
            </:col>
            <:col :let={agent} label="Running Instances">
              <span class="text-xs text-js-text-subtle">
                {length(agent.running_instances || [])}
              </span>
            </:col>
          </.data_table>
        </.card>

        <.card :if={@internal_agents != []}>
          <div class="flex items-center justify-between gap-2 mb-3">
            <h3 class="text-sm font-medium text-js-text">Internal Agents</h3>
            <.badge variant={:warning}>{length(@internal_agents)}</.badge>
          </div>
          <.data_table rows={@internal_agents} scroll_x={false}>
            <:col :let={agent} label="Name">
              <.link
                navigate={agent_module_path(@prefix, agent)}
                class="text-js-text font-medium hover:text-js-primary transition-colors"
              >
                {humanize_agent_name(agent.name)}
              </.link>
            </:col>
            <:col :let={agent} label="Description">
              <span class="text-xs text-js-text-muted truncate max-w-md block">
                {agent.description}
              </span>
            </:col>
            <:col :let={agent} label="Tags">
              <div class="flex flex-wrap gap-1">
                <.badge :for={tag <- agent.tags || []} variant={:warning}>{tag}</.badge>
              </div>
            </:col>
            <:col :let={agent} label="Running Instances">
              <span class="text-xs text-js-text-subtle">
                {length(agent.running_instances || [])}
              </span>
            </:col>
          </.data_table>
        </.card>
      <% end %>
    </div>
    """
  end

  defp parse_detail_tab(nil, detail_tabs), do: default_detail_tab(detail_tabs)

  defp parse_detail_tab(tab, detail_tabs) when is_binary(tab) do
    case Enum.find(detail_tabs, fn item -> Atom.to_string(item.id) == tab end) do
      nil -> default_detail_tab(detail_tabs)
      item -> item.id
    end
  end

  defp parse_detail_tab(_tab, detail_tabs), do: default_detail_tab(detail_tabs)

  defp default_detail_tab([first | _]), do: first.id
  defp default_detail_tab(_), do: :overview

  defp strategy_model(module) when is_atom(module) do
    module
    |> strategy_opts()
    |> Keyword.get(:model, @default_model)
    |> to_string()
  end

  defp strategy_model(_), do: @default_model

  defp strategy_opts(module) do
    if function_exported?(module, :strategy_opts, 0) do
      module.strategy_opts()
    else
      []
    end
  rescue
    _ -> []
  end

  defp presenter_view_model(presenter, agent, runtime_status, opts) do
    if runtime_status do
      presenter.runtime(agent, runtime_status, opts)
    else
      presenter.static(agent)
    end
  rescue
    _ ->
      if runtime_status do
        Default.runtime(agent, runtime_status, opts)
      else
        Default.static(agent)
      end
  end

  defp instance_runtime_status(nil), do: nil

  defp instance_runtime_status(%{pid: pid}) when is_pid(pid) do
    case Jido.AgentServer.status(pid) do
      {:ok, status} -> status
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp instance_debug_enabled(%{pid: pid}) when is_pid(pid) do
    case Jido.AgentServer.state(pid) do
      {:ok, %{debug: enabled}} when is_boolean(enabled) -> enabled
      _ -> false
    end
  rescue
    _ -> false
  end

  defp instance_debug_enabled(_), do: false

  defp agent_module_path(prefix, agent), do: scoped_path("#{prefix}/agents/#{agent.slug}")

  defp agent_instance_path(prefix, agent, instance_id) do
    scoped_path("#{prefix}/agents/#{agent.slug}/#{URI.encode_www_form(instance_id)}")
  end

  defp instance_links(prefix, agent, running_instances, active_instance_id) do
    links =
      Enum.map(running_instances, fn instance ->
        %{id: instance.id, path: agent_instance_path(prefix, agent, instance.id)}
      end)

    if is_binary(active_instance_id) and not Enum.any?(links, &(&1.id == active_instance_id)) do
      links ++
        [%{id: active_instance_id, path: agent_instance_path(prefix, agent, active_instance_id)}]
    else
      links
    end
  end

  defp traces_path(prefix, agent, instance_id, agent_id) do
    query =
      [
        {"agent_slug", agent.slug},
        {"agent_module", inspect(agent.module)},
        {"instance_id", instance_id},
        {"agent_id", agent_id}
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> URI.encode_query()

    if query == "" do
      scoped_path("#{prefix}/traces")
    else
      scoped_path("#{prefix}/traces?#{query}")
    end
  end

  defp triage_links(prefix, instance_id, scope_filters) when is_binary(instance_id) do
    scope_params = scope_query_params(scope_filters)

    incident =
      Incidents.latest_for_agent(
        instance_id,
        Map.merge(%{agent_id: instance_id, range: "24h"}, scope_params)
      )

    latest_incident_path =
      if is_map(incident) and is_binary(incident[:incident_id]) do
        scoped_path(
          prefix <>
            "/traces?" <>
            URI.encode_query(Map.put(scope_params, "incident_id", incident[:incident_id]))
        )
      else
        nil
      end

    failures_params =
      scope_params
      |> Map.put("agent_id", instance_id)
      |> Map.put("status", "error")
      |> Map.put("error_only", "true")

    snapshot_params =
      scope_params
      |> Map.put("agent_id", instance_id)
      |> Map.put("range", "1h")

    %{
      latest_incident_path: latest_incident_path,
      failures_path: scoped_path(prefix <> "/actions?" <> URI.encode_query(failures_params)),
      snapshot_path: scoped_path(prefix <> "/signals?" <> URI.encode_query(snapshot_params))
    }
  rescue
    _ ->
      %{}
  end

  defp triage_links(_prefix, _instance_id, _scope_filters), do: %{}

  defp scope_query_params(scope_filters) when is_map(scope_filters) do
    %{}
    |> maybe_put_query("project_id", normalize_scope_value(scope_filters.project_id))
    |> maybe_put_query("user_id", normalize_scope_value(scope_filters.user_id))
  end

  defp scope_query_params(_), do: %{}

  defp maybe_put_query(params, _key, nil), do: params
  defp maybe_put_query(params, key, value), do: Map.put(params, key, value)

  defp active_instance_path(prefix, %{agent_slug: slug, instance_id: instance_id})
       when is_binary(prefix) and is_binary(slug) and is_binary(instance_id) do
    scoped_path("#{prefix}/agents/#{slug}/#{URI.encode_www_form(instance_id)}")
  end

  defp active_instance_path(_prefix, _row), do: nil

  defp scoped_path(path) do
    Scope.with_scope_query(path, Scope.current_node_param())
  end

  defp status_badge_variant(status) when status in ["running", :running], do: :success
  defp status_badge_variant(status) when status in ["idle", :idle], do: :info
  defp status_badge_variant(status) when status in ["error", :error], do: :error
  defp status_badge_variant(status) when status in ["interrupted", :interrupted], do: :warning
  defp status_badge_variant(_), do: :default

  defp datetime_to_unix_ms(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :millisecond)
  defp datetime_to_unix_ms(_), do: nil

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(_), do: "n/a"

  defp format_uptime(ms) when is_integer(ms) and ms >= 0 do
    total_seconds = div(ms, 1_000)
    hours = div(total_seconds, 3_600)
    minutes = div(rem(total_seconds, 3_600), 60)
    seconds = rem(total_seconds, 60)

    cond do
      hours > 0 ->
        "#{hours}h #{minutes}m"

      minutes > 0 ->
        "#{minutes}m #{seconds}s"

      true ->
        "#{seconds}s"
    end
  end

  defp format_uptime(_), do: "n/a"

  defp fetch_jido_instance(socket) do
    case resolve_jido_instance(socket.assigns[:jido_instance]) do
      instance when is_atom(instance) -> {:ok, instance}
      _ -> {:error, "No Jido instance configured for this Studio mount."}
    end
  end

  defp resolve_jido_instance(nil), do: Application.get_env(:jido_studio, :jido_instance)
  defp resolve_jido_instance(value), do: value

  defp build_instance_cards(presenter, agent, running_instances, instance_runtime_map, prefix) do
    Enum.map(running_instances, fn instance ->
      runtime = Map.get(instance_runtime_map, instance.id, %{})
      status = Map.get(runtime, :status)
      debug_enabled = Map.get(runtime, :debug_enabled, false)

      summary =
        presenter_instance_summary(
          presenter,
          agent,
          instance,
          status,
          debug_enabled: debug_enabled,
          instance_id: instance.id,
          pid: instance.pid
        )

      %{
        id: instance.id,
        path: agent_instance_path(prefix, agent, instance.id),
        traces_path: traces_path(prefix, agent, instance.id, instance.id),
        summary: summary
      }
    end)
  end

  defp instance_runtime_details(nil), do: %{status: nil, debug_enabled: false}

  defp instance_runtime_details(instance) do
    %{
      status: instance_runtime_status(instance),
      debug_enabled: instance_debug_enabled(instance)
    }
  end

  defp presenter_instance_summary(presenter, agent, instance, runtime_status, opts) do
    if function_exported?(presenter, :instance_summary, 4) do
      presenter.instance_summary(agent, instance, runtime_status, opts)
    else
      Default.instance_summary(agent, instance, runtime_status, opts)
    end
  rescue
    _ -> Default.instance_summary(agent, instance, runtime_status, opts)
  end

  defp presenter_start_form_schema(presenter, agent) do
    if function_exported?(presenter, :start_form_schema, 1) do
      presenter.start_form_schema(agent)
    else
      Default.start_form_schema(agent)
    end
  rescue
    _ -> Default.start_form_schema(agent)
  end

  defp presenter_chat_config(presenter, agent, runtime_status, opts) do
    config =
      if function_exported?(presenter, :chat_config, 3) do
        presenter.chat_config(agent, runtime_status, opts)
      else
        Default.chat_config(agent, runtime_status, opts)
      end

    normalize_chat_config(config, agent, runtime_status, opts)
  rescue
    _ ->
      Default.chat_config(agent, runtime_status, opts)
      |> normalize_chat_config(agent, runtime_status, opts)
  end

  defp normalize_chat_config(config, agent, runtime_status, opts) when is_map(config) do
    defaults = Default.chat_config(agent, runtime_status, opts)
    merged = Map.merge(defaults, config)

    %{
      enabled: merged.enabled == true,
      mode: :ask_sync,
      timeout_ms: normalize_chat_timeout(merged.timeout_ms),
      placeholder: to_string(merged.placeholder || defaults.placeholder),
      empty_title: to_string(merged.empty_title || defaults.empty_title),
      empty_description: to_string(merged.empty_description || defaults.empty_description),
      model_label: if(is_nil(merged.model_label), do: nil, else: to_string(merged.model_label)),
      streaming_enabled:
        (merged.streaming_enabled == true or defaults.streaming_enabled == true) and
          merged.enabled == true,
      stream_poll_ms: ChatRuntime.stream_poll_ms(stream_poll_ms: merged.stream_poll_ms)
    }
  end

  defp normalize_chat_config(_config, agent, runtime_status, opts) do
    presenter_chat_config(Default, agent, runtime_status, opts)
  end

  defp default_chat_config do
    %{
      enabled: false,
      mode: :ask_sync,
      timeout_ms: 30_000,
      placeholder: "Enter your message...",
      empty_title: "How can I help you today?",
      empty_description: "Start a message to begin chatting with this instance.",
      model_label: nil,
      streaming_enabled: false,
      stream_poll_ms: 120
    }
  end

  defp assign_chat_controls(socket, model_label) do
    {provider, model, model_options} = chat_controls_from_model(model_label)

    socket
    |> assign(:chat_provider_options, @chat_provider_options)
    |> assign(:chat_provider, provider)
    |> assign(:chat_model, model)
    |> assign(:chat_model_options, model_options)
  end

  defp chat_controls_from_model(model_label) do
    {provider, model} = split_model_label(model_label)
    normalize_chat_controls(provider, model)
  end

  defp normalize_chat_controls(provider, model) do
    provider = normalize_provider(provider)
    model_options = chat_model_options(provider)
    model = normalize_model(model, model_options)
    {provider, model, model_options}
  end

  defp normalize_provider(provider) when is_binary(provider) do
    normalized = provider |> String.trim() |> String.downcase()
    if normalized in @chat_provider_options, do: normalized, else: "anthropic"
  end

  defp normalize_provider(_), do: "anthropic"

  defp normalize_model(model, model_options) when is_binary(model) do
    candidate = String.trim(model)

    cond do
      model_options != [] and candidate in model_options ->
        candidate

      model_options != [] ->
        hd(model_options)

      candidate == "" ->
        ""

      true ->
        candidate
    end
  end

  defp normalize_model(_, model_options) when is_list(model_options) and model_options != [],
    do: hd(model_options)

  defp normalize_model(_, _), do: ""

  defp split_model_label(label) when is_binary(label) do
    case String.split(label, ":", parts: 2) do
      [provider, model] -> {provider, model}
      [model] -> {"anthropic", model}
      _ -> {"anthropic", "claude-sonnet-4-5"}
    end
  end

  defp split_model_label(_), do: {"anthropic", "claude-sonnet-4-5"}

  defp chat_model_options("anthropic"),
    do: ["claude-haiku-4-5", "claude-sonnet-4-5", "claude-opus-4-1"]

  defp chat_model_options("openai"), do: ["gpt-4.1-mini", "gpt-4.1", "o4-mini"]
  defp chat_model_options("groq"), do: ["llama-3.3-70b-versatile", "mixtral-8x7b-32768"]
  defp chat_model_options("ollama"), do: ["qwen2.5:7b", "llama3.1:8b", "mistral:7b"]
  defp chat_model_options("custom"), do: []
  defp chat_model_options(_), do: []

  defp normalize_chat_timeout(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0,
    do: timeout_ms

  defp normalize_chat_timeout(_), do: 30_000

  defp stream_since_entry_count(pid) when is_pid(pid) do
    case ChatRuntime.thread_entry_count(pid) do
      {:ok, count} -> count
      _ -> 0
    end
  end

  defp stream_since_entry_count(_), do: 0

  defp current_traces_path(socket) do
    case socket.assigns[:agent] do
      nil ->
        nil

      agent ->
        traces_path(
          socket.assigns.prefix,
          agent,
          socket.assigns[:active_instance_id],
          socket.assigns[:active_instance_id]
        )
    end
  end

  defp enrich_tool_events([], _instance_id, _traces_path), do: []

  defp enrich_tool_events(tool_events, instance_id, traces_path) when is_list(tool_events) do
    telemetry =
      if is_binary(instance_id) do
        TraceBuffer.events_for_instance(instance_id, 500)
      else
        []
      end

    telemetry_by_call_id =
      Enum.reduce(telemetry, %{}, fn event, acc ->
        call_id = event_metadata_value(event, :call_id)

        if is_binary(call_id) and call_id != "" do
          Map.update(acc, call_id, [event], fn existing -> [event | existing] end)
        else
          acc
        end
      end)

    Enum.map(tool_events, fn tool_event ->
      call_id = Map.get(tool_event, :call_id) || Map.get(tool_event, :id)
      related_events = Map.get(telemetry_by_call_id, call_id, [])
      telemetry_summary = summarize_tool_telemetry(related_events)
      trace_id = telemetry_summary.trace_id

      tool_event
      |> Map.put(:call_id, call_id)
      |> Map.put(:duration_ms, telemetry_summary.duration_ms)
      |> Map.put(:trace_id, trace_id)
      |> Map.put(:status, merge_tool_status(tool_event[:status], telemetry_summary.status))
      |> Map.put(:traces_path, tool_trace_path(traces_path, instance_id, call_id, trace_id))
    end)
  end

  defp summarize_tool_telemetry(events) when is_list(events) do
    start_event = Enum.find(events, &(&1.event_prefix == [:jido, :ai, :tool, :execute, :start]))
    stop_event = Enum.find(events, &(&1.event_prefix == [:jido, :ai, :tool, :execute, :stop]))

    exception_event =
      Enum.find(events, &(&1.event_prefix == [:jido, :ai, :tool, :execute, :exception]))

    duration_ms =
      cond do
        is_map(stop_event) ->
          stop_event
          |> Map.get(:measurements, %{})
          |> Map.get(:duration)
          |> duration_to_ms()

        is_map(exception_event) ->
          exception_event
          |> Map.get(:measurements, %{})
          |> Map.get(:duration)
          |> duration_to_ms()

        is_map(start_event) and is_map(stop_event) ->
          (stop_event[:timestamp_ms] || 0) - (start_event[:timestamp_ms] || 0)

        true ->
          nil
      end

    trace_id =
      (stop_event && stop_event[:trace_id]) ||
        (exception_event && exception_event[:trace_id]) ||
        (start_event && start_event[:trace_id])

    status =
      cond do
        is_map(exception_event) -> :error
        is_map(stop_event) -> :completed
        is_map(start_event) -> :running
        true -> nil
      end

    %{duration_ms: duration_ms, trace_id: trace_id, status: status}
  end

  defp summarize_tool_telemetry(_), do: %{duration_ms: nil, trace_id: nil, status: nil}

  defp duration_to_ms(value) when is_integer(value) and value >= 0 do
    System.convert_time_unit(value, :native, :millisecond)
  end

  defp duration_to_ms(_), do: nil

  defp merge_tool_status(:error, _), do: :error
  defp merge_tool_status(_, :error), do: :error
  defp merge_tool_status(current, nil), do: current || :running
  defp merge_tool_status(_current, telemetry_status), do: telemetry_status

  defp tool_trace_path(nil, _instance_id, _call_id, _trace_id), do: nil

  defp tool_trace_path(base_path, instance_id, call_id, trace_id) do
    params =
      [
        {"source", "telemetry"},
        {"instance_id", instance_id},
        {"call_id", call_id},
        {"trace_id", trace_id}
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

    case params do
      [] ->
        base_path

      _ ->
        separator = if String.contains?(base_path, "?"), do: "&", else: "?"
        base_path <> separator <> URI.encode_query(params)
    end
  end

  defp refresh_instance_observability(socket) do
    live_action = socket.assigns[:live_action]
    agent = socket.assigns[:agent]
    instance_id = socket.assigns[:active_instance_id]
    pid = socket.assigns[:active_instance_pid]

    cond do
      live_action != :show or is_nil(agent) or not is_binary(instance_id) or not is_pid(pid) ->
        socket
        |> assign(:runtime_status, nil)
        |> assign(:runtime_messages, [])
        |> assign(:runtime_todos, [])
        |> assign(:instance_event_stream, [])
        |> assign(:expanded_event_ids, MapSet.new())
        |> assign(:interaction_model, empty_interaction_model())
        |> assign(:runner_form, RunnerForm.new())
        |> assign(:runner_result, nil)
        |> assign(:runner_history, [])
        |> assign(:instance_observability_events, [])
        |> assign(:instance_debug_events, [])
        |> assign(:instance_telemetry_events, [])
        |> assign(:instance_debug_error, nil)
        |> assign(:instance_debug_enabled?, false)
        |> assign(:instance_debug_level, "off")
        |> assign(:subagents, [])
        |> assign(:tasks, [])
        |> assign(:delegation_graph, %{nodes: [], edges: []})
        |> assign(:tool_insights, [])
        |> assign(:middleware_snapshots, [])
        |> assign(:subagent_events, %{})
        |> assign(:expanded_subagent_id, nil)
        |> assign(:triage_links, %{})

      true ->
        preview =
          load_instance_observability(
            instance_id,
            pid,
            socket.assigns[:trace_preview_limit],
            socket.assigns[:trace_include_agent_debug?]
          )

        runtime_status = instance_runtime_status(%{pid: pid})
        debug_enabled = instance_debug_enabled(%{pid: pid})
        debug_level = infer_debug_level(debug_enabled, socket.assigns[:instance_debug_level])
        presenter = socket.assigns[:presenter] || Default
        scope = socket.assigns[:scope_filters] || %{}

        subagents =
          if Delegation.enabled?() do
            Delegation.list_subagents(instance_id, scope: scope, limit: 200)
          else
            []
          end

        tasks =
          if Delegation.enabled?() do
            Delegation.list_tasks(instance_id, scope: scope, limit: 300)
          else
            []
          end

        latest_trace_id =
          preview
          |> Map.get(:events, [])
          |> Enum.find_value(fn event -> event[:trace_id] end)

        runtime_messages = MessageSnapshot.thread_messages(runtime_status)
        runtime_todos = runtime_todos_for_display(runtime_status, tasks)

        event_stream =
          preview
          |> Map.get(:events, [])
          |> build_instance_event_stream(socket.assigns[:live_event_limit])

        delegation_graph =
          if Delegation.enabled?() and is_binary(latest_trace_id) do
            Delegation.delegation_graph(latest_trace_id, limit: 800)
          else
            %{nodes: [], edges: []}
          end

        tool_insights =
          if Delegation.enabled?() do
            Delegation.list_tool_runs(instance_id, limit: 120)
          else
            []
          end

        middleware_snapshots =
          if Delegation.enabled?() do
            Delegation.list_middleware_snapshots(instance_id, limit: 40)
          else
            []
          end

        interaction_model =
          if AgentInteractions.enabled?() do
            Introspection.build(agent.module, %{pid: pid}, events: Map.get(preview, :events, []))
          else
            empty_interaction_model()
          end

        view_model =
          presenter_view_model(
            presenter,
            agent,
            runtime_status,
            instance_id: instance_id,
            pid: pid,
            debug_enabled: debug_enabled,
            raw_state: runtime_status && runtime_status.raw_state,
            observability_preview: preview,
            traces_path: traces_path(socket.assigns.prefix, agent, instance_id, instance_id)
          )

        tabs =
          view_model
          |> Map.get(:tabs, [%{id: :overview, label: "Overview"}])
          |> ordered_detail_tabs()

        socket
        |> assign(:runtime_status, runtime_status)
        |> assign(:runtime_messages, runtime_messages)
        |> assign(:runtime_todos, runtime_todos)
        |> assign(:instance_event_stream, event_stream)
        |> assign(
          :expanded_event_ids,
          sanitize_expanded_event_ids(socket.assigns[:expanded_event_ids], event_stream)
        )
        |> assign(:instance_debug_enabled?, debug_enabled)
        |> assign(:instance_debug_level, debug_level)
        |> assign(:instance_observability_events, Map.get(preview, :events, []))
        |> assign(:instance_debug_events, Map.get(preview, :debug_events, []))
        |> assign(:instance_telemetry_events, Map.get(preview, :telemetry_events, []))
        |> assign(:instance_debug_error, Map.get(preview, :debug_error))
        |> assign(:subagents, subagents)
        |> assign(:tasks, tasks)
        |> assign(:delegation_graph, delegation_graph)
        |> assign(:tool_insights, tool_insights)
        |> assign(:middleware_snapshots, middleware_snapshots)
        |> assign(:interaction_model, interaction_model)
        |> assign(:runner_form, sync_runner_form(socket.assigns[:runner_form], interaction_model))
        |> assign(:detail_tabs, tabs)
        |> assign(:detail_tab, preserve_detail_tab(socket.assigns[:detail_tab], tabs))
        |> assign(:sections_by_tab, Map.get(view_model, :sections_by_tab, %{}))
        |> assign(:triage_links, triage_links(socket.assigns.prefix, instance_id, scope))
        |> assign(
          :system_prompt,
          Map.get(view_model, :system_prompt, "No system prompt configured.")
        )
        |> maybe_capture_thread_context_snapshot(runtime_status)
        |> maybe_load_subagent_events(socket.assigns[:expanded_subagent_id])
    end
  end

  defp load_workspace_for(socket, agent_slug, instance_id) do
    case ThreadsManager.load_workspace(agent_slug, instance_id,
           jido_instance: socket.assigns[:jido_instance]
         ) do
      {:ok, payload} ->
        interaction_history = payload[:interaction_history] || %{}

        socket
        |> assign(:chat_state, ensure_workspace_chat_state(payload.chat_state))
        |> assign(:draft_message, payload.draft_message || "")
        |> assign(:persisted_thread_contexts, payload.thread_contexts || %{})
        |> assign(:interaction_history, interaction_history)
        |> assign(:runner_history, Map.get(interaction_history, instance_id, []))
        |> assign(:workspace_source, payload.source || :fresh)

      {:error, _reason} ->
        socket
        |> assign(:chat_state, ChatSession.with_initial_thread("New Chat"))
        |> assign(:draft_message, "")
        |> assign(:persisted_thread_contexts, %{})
        |> assign(:interaction_history, %{})
        |> assign(:runner_history, [])
        |> assign(:workspace_source, :fresh)
    end
  end

  defp schedule_workspace_persist(socket, reason, delay_ms \\ 0) do
    has_workspace? =
      is_binary(socket.assigns[:active_instance_id]) and not is_nil(socket.assigns[:agent])

    cond do
      socket.assigns[:thread_persistence?] != true ->
        socket

      not has_workspace? ->
        socket

      not ThreadsStorage.persistence_enabled?() ->
        socket

      true ->
        cancel_workspace_persist_timer(socket.assigns[:persist_workspace_ref])

        if is_integer(delay_ms) and delay_ms > 0 do
          token = System.unique_integer([:positive, :monotonic])
          timer_ref = Process.send_after(self(), {:persist_workspace, token, reason}, delay_ms)
          assign(socket, :persist_workspace_ref, {timer_ref, token})
        else
          socket
          |> assign(:persist_workspace_ref, nil)
          |> persist_workspace(reason)
        end
    end
  end

  defp persist_workspace(socket, _reason) do
    if ThreadsStorage.persistence_enabled?() and is_binary(socket.assigns[:active_instance_id]) and
         not is_nil(socket.assigns[:agent]) do
      _ =
        ThreadsManager.save_workspace(
          socket.assigns.agent.slug,
          socket.assigns.active_instance_id,
          socket.assigns.chat_state,
          jido_instance: socket.assigns[:jido_instance],
          draft_message: socket.assigns[:draft_message] || "",
          thread_contexts: socket.assigns[:persisted_thread_contexts] || %{},
          interaction_history: socket.assigns[:interaction_history] || %{},
          instance_binding: %{
            agent_slug: socket.assigns.agent.slug,
            agent_module: inspect(socket.assigns.agent.module),
            instance_id: socket.assigns.active_instance_id
          }
        )

      socket
    else
      socket
    end
  end

  defp maybe_capture_thread_context_snapshot(socket, runtime_status) do
    mode = ThreadsStorage.persist_strategy_context_mode()
    active_thread_id = socket.assigns[:chat_state] && socket.assigns.chat_state.active_thread_id

    cond do
      mode == :off ->
        socket

      not is_binary(active_thread_id) ->
        socket

      true ->
        snapshot = build_thread_context_snapshot(runtime_status, mode)

        if is_map(snapshot) do
          contexts = socket.assigns[:persisted_thread_contexts] || %{}
          existing = Map.get(contexts, active_thread_id)

          if existing == snapshot do
            socket
          else
            socket
            |> assign(:persisted_thread_contexts, Map.put(contexts, active_thread_id, snapshot))
            |> schedule_workspace_persist(:thread_context, 500)
          end
        else
          socket
        end
    end
  end

  defp build_thread_context_snapshot(%{raw_state: raw_state, snapshot: snapshot}, mode)
       when is_map(raw_state) and is_map(snapshot) do
    strategy_state = raw_state[:__strategy__] || %{}
    details = snapshot_details(snapshot)

    summary = %{
      captured_at: now_ms(),
      source: :live,
      status: to_string(snapshot_status(snapshot)),
      strategy_thread_id: active_strategy_thread_id(%{raw_state: raw_state}),
      iteration: strategy_state[:iteration] || detail_value(details, :iteration, 0),
      conversation_count:
        length(strategy_state[:conversation] || detail_value(details, :conversation, [])),
      pending_tool_calls_count: length(strategy_state[:pending_tool_calls] || []),
      thinking_blocks_count: length(strategy_state[:thinking_trace] || []),
      termination_reason:
        strategy_state[:termination_reason] || detail_value(details, :termination_reason),
      model:
        get_in(strategy_state, [:config, :model]) ||
          detail_value(details, :model) ||
          get_in(raw_state, [:agent, :state, :model])
    }

    case mode do
      :full ->
        Map.put(summary, :strategy_state, ThreadsStorage.sanitize_term(strategy_state))

      _ ->
        summary
    end
  end

  defp build_thread_context_snapshot(_, _), do: nil

  defp snapshot_details(%{details: details}) when is_map(details), do: details
  defp snapshot_details(_), do: %{}

  defp snapshot_status(%{status: nil}), do: :unknown
  defp snapshot_status(%{status: status}), do: status
  defp snapshot_status(_), do: :unknown

  defp detail_value(details, key, default \\ nil)

  defp detail_value(details, key, default) when is_map(details) and is_atom(key) do
    Map.get(details, key, Map.get(details, Atom.to_string(key), default))
  end

  defp detail_value(_, _, default), do: default

  defp ensure_workspace_chat_state(%{threads: []} = _state),
    do: ChatSession.with_initial_thread("New Chat")

  defp ensure_workspace_chat_state(%{} = state) do
    %{
      threads: Map.get(state, :threads, []),
      active_thread_id: Map.get(state, :active_thread_id),
      messages_by_thread: Map.get(state, :messages_by_thread, %{})
    }
  end

  defp ensure_workspace_chat_state(_), do: ChatSession.with_initial_thread("New Chat")

  defp cancel_workspace_persist_timer({timer_ref, _token}) when is_reference(timer_ref) do
    _ = Process.cancel_timer(timer_ref)
    :ok
  end

  defp cancel_workspace_persist_timer(ref) when is_reference(ref) do
    _ = Process.cancel_timer(ref)
    :ok
  end

  defp cancel_workspace_persist_timer(_), do: :ok

  defp load_instance_observability(instance_id, pid, limit, include_agent_debug?) do
    Observability.trace_preview(instance_id, pid,
      limit: normalize_observability_limit(limit),
      include_agent_debug?: include_agent_debug? != false
    )
  rescue
    error ->
      %{
        events: [],
        telemetry_events: [],
        debug_events: [],
        debug_error: {:exception, Exception.message(error)}
      }
  end

  defp normalize_observability_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_observability_limit(_), do: Observability.trace_preview_limit()

  defp preserve_detail_tab(tab, tabs) do
    if Enum.any?(tabs, &(&1.id == tab)), do: tab, else: default_detail_tab(tabs)
  end

  defp setup_live_ops(socket) do
    enabled? = LiveOps.enabled?()
    presence? = LiveOps.presence_available?()
    realtime? = enabled? and presence?

    if connected?(socket) and enabled? do
      _ = LiveOps.subscribe_agent_list(socket.assigns[:scope_filters] || %{})
    end

    if connected?(socket) and not realtime? do
      :timer.send_interval(LiveOps.agent_list_poll_ms(), self(), :refresh_instance_observability)
    end

    socket
    |> assign(:live_ops_enabled?, enabled?)
    |> assign(:live_ops_presence?, presence?)
    |> assign(:live_ops_realtime?, realtime?)
  end

  defp maybe_subscribe_live_ops(socket, active_instance_id, scope_filters) do
    if connected?(socket) and socket.assigns[:live_ops_enabled?] and is_binary(active_instance_id) do
      _ = LiveOps.subscribe_agent(active_instance_id, scope_filters)
    end

    socket
  end
end
