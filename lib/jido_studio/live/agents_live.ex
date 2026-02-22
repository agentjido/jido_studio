defmodule JidoStudio.AgentsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Live.AgentsLive.Support

  alias JidoStudio.AgentInteractions
  alias JidoStudio.AgentRegistry
  alias JidoStudio.Agents.FilterForm, as: AgentsFilterForm
  alias JidoStudio.Agents.Runner
  alias JidoStudio.Agents.RunnerForm
  alias JidoStudio.Chat.Session, as: ChatSession
  alias JidoStudio.LiveOps
  alias JidoStudio.Live.AgentsLive.IndexState
  alias JidoStudio.Live.AgentsLive.ChatState
  alias JidoStudio.Live.AgentsLive.ObservabilityState
  alias JidoStudio.Live.AgentsLive.Render.IndexView
  alias JidoStudio.Live.AgentsLive.Render.InstanceView
  alias JidoStudio.Live.AgentsLive.ShowState
  alias JidoStudio.Live.AgentsLive.WorkspaceState
  alias JidoStudio.Observability
  alias JidoStudio.Presenters.Default
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
      |> assign(:chat_unavailable_reason, nil)
      |> assign(:chat_pending?, false)
      |> assign(:chat_pending_message_id, nil)
      |> assign(:chat_stream, nil)
      |> assign(:draft_message, "")
      |> assign(:workspace_source, :fresh)
      |> assign(:persisted_thread_contexts, %{})
      |> assign(:thread_persistence?, ThreadsStorage.persistence_enabled?())
      |> assign(:persist_workspace_ref, nil)
      |> assign(:workbench_tab, :chat)
      |> assign(:instance_section, :play)
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
    {:noreply, IndexState.refresh(socket)}
  end

  @impl true
  def handle_event("update_scope_filters", %{"scope" => scope_params}, socket) do
    {:noreply, IndexState.update_scope_filters(socket, scope_params)}
  end

  @impl true
  def handle_event("update_instance_filters", %{"filters" => params}, socket) do
    {:noreply, IndexState.update_instance_filters(socket, params)}
  end

  @impl true
  def handle_event("toggle_auto_follow_instances", _params, socket) do
    {:noreply, IndexState.toggle_auto_follow_instances(socket)}
  end

  @impl true
  def handle_event("update_auto_follow_target", %{"target" => params}, socket) do
    {:noreply, IndexState.update_auto_follow_target(socket, params)}
  end

  @impl true
  def handle_event("follow_instance", %{"id" => instance_id}, socket) do
    {:noreply, IndexState.follow_instance(socket, instance_id)}
  end

  @impl true
  def handle_event("unfollow_instance", _params, socket) do
    {:noreply, IndexState.unfollow_instance(socket)}
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
    requested_tab = parse_workbench_tab(panel)

    workbench_tab =
      resolve_default_workbench_tab(
        requested_tab,
        socket.assigns[:interaction_model] || empty_interaction_model(),
        socket.assigns[:chat_enabled?] == true
      )

    socket =
      socket
      |> assign(:workbench_tab, workbench_tab)
      |> assign(:instance_section, section_for_workbench_tab(workbench_tab))
      |> maybe_put_chat_redirect_flash(requested_tab, workbench_tab)

    if is_binary(socket.assigns.active_instance_id) and socket.assigns.agent do
      {:noreply,
       push_patch(socket,
         to:
           workbench_path(
             socket.assigns.prefix,
             socket.assigns.agent,
             socket.assigns.active_instance_id,
             workbench_tab,
             socket.assigns.detail_tab,
             socket.assigns[:instance_section]
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
  def handle_event("clear_workspace", _params, socket) do
    case clear_active_workspace(socket) do
      {:ok, cleared} ->
        {:noreply, put_flash(cleared, :info, "Cleared persisted workspace for this instance.")}

      {:error, :persistence_disabled, same_socket} ->
        {:noreply,
         put_flash(
           same_socket,
           :error,
           "Thread persistence is disabled for this runtime."
         )}

      {:error, :no_active_instance, same_socket} ->
        {:noreply, put_flash(same_socket, :error, "No active instance selected.")}

      {:error, reason, same_socket} ->
        {:noreply,
         put_flash(same_socket, :error, "Failed to clear workspace: #{inspect(reason)}")}
    end
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
    ChatState.handle_send_message(socket)
  end

  @impl true
  def handle_async(name, result, socket) do
    {:noreply, ChatState.handle_async(socket, name, result)}
  end

  @impl true
  def handle_info({:chat_stream_tick, pending_id, request_id}, socket) do
    {:noreply, ChatState.handle_stream_tick(socket, pending_id, request_id)}
  end

  @impl true
  def handle_info({:jido_studio_live_ops, :agent_list, payload}, socket) do
    {:noreply, IndexState.handle_agent_list_event(socket, payload)}
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
    {:noreply, IndexState.handle_presence_diff(socket, topic)}
  end

  @impl true
  def handle_info(:refresh_instance_observability, socket) do
    refreshed = refresh_instance_observability(socket)
    {:noreply, IndexState.after_observability_refresh(refreshed)}
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

  defp apply_action(socket, :index, params) do
    IndexState.apply(socket, params, chat_provider_options: @chat_provider_options)
  end

  defp apply_action(socket, :show, %{"slug" => slug} = params) do
    ShowState.apply_show(socket, slug, params,
      ensure_workspace_state: &ensure_workspace_state/3,
      maybe_subscribe_live_ops: &maybe_subscribe_live_ops/3,
      refresh_instance_observability: &refresh_instance_observability/1,
      maybe_track_followed_viewer: &maybe_track_followed_viewer/1
    )
  end

  defp ensure_workspace_state(socket, agent, active_instance_id) do
    WorkspaceState.ensure_workspace_state(socket, agent, active_instance_id,
      chat_provider_options: @chat_provider_options
    )
  end

  @impl true
  def render(%{agent: agent, live_action: action, active_instance_id: nil} = assigns)
      when not is_nil(agent) and action == :show do
    assigns =
      assigns
      |> assign(:module_path, agent_module_path(assigns.prefix, agent))
      |> assign(:traces_path, traces_path(assigns.prefix, agent, nil, nil))

    InstanceView.show_without_active_instance(assigns)
  end

  @impl true
  def render(
        %{agent: agent, live_action: action, active_instance_id: active_instance_id} = assigns
      )
      when not is_nil(agent) and action == :show and not is_nil(active_instance_id) do
    workbench_tab = assigns.workbench_tab || :chat

    instance_section =
      parse_instance_section(assigns.instance_section || section_for_workbench_tab(workbench_tab))

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
      |> assign(:instance_section, instance_section)
      |> assign(:section_tabs, workbench_tabs_for_section(instance_section))
      |> assign(
        :chat_tab_disabled?,
        not assigns.chat_enabled? and assigns.interaction_model.runner_supported? == true
      )
      # Keep a stable three-rail layout so Configure/Observe don't drop the right summary pane.
      |> assign(:workbench_grid_class, workbench_grid_class(true))
      |> assign(:threads_rail_class, workbench_threads_rail_class(true))
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
          assigns.active_instance_id,
          instance_section
        )
      )
      |> assign(:summary_meta, summary_meta(assigns.runtime_status, assigns.ui_model))

    InstanceView.show_with_active_instance(assigns)
  end

  def render(assigns) do
    IndexView.index(assigns)
  end

  defp parse_detail_tab(tab, detail_tabs), do: ShowState.parse_detail_tab(tab, detail_tabs)
  defp agent_module_path(prefix, agent), do: ShowState.agent_module_path(prefix, agent)

  defp agent_instance_path(prefix, agent, instance_id, section \\ :play),
    do: ShowState.agent_instance_path(prefix, agent, instance_id, section)

  defp instance_links(prefix, agent, running_instances, active_instance_id, section),
    do: ShowState.instance_links(prefix, agent, running_instances, active_instance_id, section)

  defp traces_path(prefix, agent, instance_id, agent_id),
    do: ShowState.traces_path(prefix, agent, instance_id, agent_id)

  defp fetch_jido_instance(socket), do: ShowState.fetch_jido_instance(socket)
  defp resolve_jido_instance(value), do: ShowState.resolve_jido_instance(value)

  defp default_chat_config, do: ShowState.default_chat_config()

  defp assign_chat_controls(socket, model_label),
    do: ShowState.assign_chat_controls(socket, model_label, @chat_provider_options)

  defp normalize_chat_controls(provider, model),
    do: ShowState.normalize_chat_controls(provider, model, @chat_provider_options)

  defp maybe_put_chat_redirect_flash(socket, :chat, :interact) do
    put_flash(socket, :info, "Chat is unavailable for this instance. Opened Interact instead.")
  end

  defp maybe_put_chat_redirect_flash(socket, _requested_tab, _resolved_tab), do: socket

  defp refresh_instance_observability(socket) do
    socket = ObservabilityState.refresh(socket)
    maybe_capture_thread_context_snapshot(socket, socket.assigns[:runtime_status])
  end

  defp schedule_workspace_persist(socket, reason, delay_ms \\ 0),
    do: WorkspaceState.schedule_workspace_persist(socket, reason, delay_ms)

  defp persist_workspace(socket, reason), do: WorkspaceState.persist_workspace(socket, reason)

  defp maybe_capture_thread_context_snapshot(socket, runtime_status),
    do: WorkspaceState.maybe_capture_thread_context_snapshot(socket, runtime_status)

  defp clear_active_workspace(socket), do: WorkspaceState.clear_active_workspace(socket)

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
