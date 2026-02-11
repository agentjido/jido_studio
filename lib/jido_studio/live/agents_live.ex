defmodule JidoStudio.AgentsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.AgentRegistry
  alias JidoStudio.Chat.Runtime, as: ChatRuntime
  alias JidoStudio.Chat.Session, as: ChatSession
  alias JidoStudio.Naming
  alias JidoStudio.Observability
  alias JidoStudio.PresenterResolver
  alias JidoStudio.Presenters.Default
  alias JidoStudio.TraceBuffer
  alias JidoStudio.Threads.Manager, as: ThreadsManager
  alias JidoStudio.Threads.Storage, as: ThreadsStorage

  @default_model "claude-sonnet-4-5"
  @chat_provider_options ["anthropic", "openai", "groq", "ollama", "custom"]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2000, self(), :refresh_instance_observability)

    jido_instance = resolve_jido_instance(socket.assigns[:jido_instance])
    agents = AgentRegistry.list_agents(jido_instance: jido_instance)
    running_count = AgentRegistry.running_count(jido_instance)
    start_form_schema = Default.start_form_schema(%{})

    socket =
      socket
      |> assign(:page_title, "Agents")
      |> assign(:jido_instance, jido_instance)
      |> assign(:agents, agents)
      |> assign(:running_count, running_count)
      |> assign(:jido_configured?, jido_instance != nil)
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
      |> assign(:instance_observability_events, [])
      |> assign(:instance_debug_events, [])
      |> assign(:instance_telemetry_events, [])
      |> assign(:instance_debug_error, nil)
      |> assign(:instance_debug_enabled?, false)
      |> assign(:start_form_schema, start_form_schema)
      |> assign(:start_form, default_start_form(start_form_schema))
      |> assign(:start_form_error, nil)
      |> assign_chat_controls(@default_model)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    jido_instance = socket.assigns[:jido_instance]
    agents = AgentRegistry.list_agents(jido_instance: jido_instance)
    running_count = AgentRegistry.running_count(jido_instance)

    {:noreply,
     socket
     |> assign(:agents, agents)
     |> assign(:running_count, running_count)}
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
  def handle_info(:refresh_instance_observability, socket) do
    {:noreply, refresh_instance_observability(socket)}
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

  defp apply_action(socket, :index, _params) do
    start_form_schema = Default.start_form_schema(%{})

    socket
    |> assign(:page_title, "Agents")
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
    |> assign_chat_controls(@default_model)
    |> assign(:start_form_schema, start_form_schema)
    |> assign(:start_form, default_start_form(start_form_schema))
    |> assign(:instance_observability_events, [])
    |> assign(:instance_debug_events, [])
    |> assign(:instance_telemetry_events, [])
    |> assign(:instance_debug_error, nil)
    |> assign(:instance_debug_enabled?, false)
  end

  defp apply_action(socket, :show, %{"slug" => slug} = params) do
    jido_instance = socket.assigns[:jido_instance]
    requested_instance_id = Map.get(params, "instance_id")
    workbench_tab = parse_workbench_tab(Map.get(params, "panel"), Map.get(params, "view"))

    case AgentRegistry.get_agent(slug, jido_instance: jido_instance) do
      nil ->
        socket
        |> put_flash(:error, "Agent not found")
        |> push_navigate(to: "#{socket.assigns.prefix}/agents")

      agent ->
        running_instances = agent.running_instances || []
        presenter = PresenterResolver.resolve(agent.module)

        instance_runtime_map =
          Map.new(running_instances, fn instance ->
            {instance.id, instance_runtime_details(instance)}
          end)

        selected_instance =
          case requested_instance_id do
            nil -> nil
            id -> Enum.find(running_instances, &(&1.id == id))
          end

        active_instance_id = requested_instance_id || (selected_instance && selected_instance.id)
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
        traces_path = traces_path(socket.assigns.prefix, agent, active_instance_id, active_instance_id)

        view_model =
          presenter_view_model(
            presenter,
            agent,
            runtime_status,
            instance_id: active_instance_id,
            pid: active_instance_pid,
            debug_enabled: selected_instance && instance_debug_enabled(selected_instance),
            raw_state: runtime_status && runtime_status.raw_state,
            observability_preview:
              selected_instance &&
                load_instance_observability(
                  selected_instance.id,
                  selected_instance.pid,
                  socket.assigns.trace_preview_limit,
                  socket.assigns.trace_include_agent_debug?
                ),
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

        tabs =
          view_model
          |> Map.get(:tabs, [%{id: :overview, label: "Overview"}])
          |> ordered_detail_tabs()

        socket
        |> assign(:page_title, Naming.humanize(agent.name))
        |> assign(:agent, agent)
        |> assign(:presenter, presenter)
        |> assign(:running_instances, running_instances)
        |> assign(:instance_cards, instance_cards)
        |> assign(:active_instance_id, active_instance_id)
        |> assign(:active_instance_pid, active_instance_pid)
        |> assign(:runtime_status, runtime_status)
        |> assign(
          :instance_debug_enabled?,
          if(selected_instance, do: instance_debug_enabled(selected_instance), else: false)
        )
        |> assign(:chat_config, chat_config)
        |> assign(:chat_enabled?, chat_enabled)
        |> assign(:workbench_tab, workbench_tab)
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
        |> refresh_instance_observability()
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
          <.link navigate={"#{@prefix}/agents"} class="hover:text-js-text">Agents</.link>
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
    thread_events = thread_events_for_display(assigns.instance_observability_events, thread_scope_id)

    assigns =
      assigns
      |> assign(:active_messages, ChatSession.active_messages(assigns.chat_state))
      |> assign(:active_thread_name, ChatSession.active_thread_name(assigns.chat_state))
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
        instance_links(assigns.prefix, agent, assigns.running_instances, assigns.active_instance_id)
      )
      |> assign(:summary_meta, summary_meta(assigns.runtime_status, assigns.ui_model))

    ~H"""
    <div
      class="p-3 lg:p-4 space-y-2 lg:flex-1 lg:min-h-0 lg:overflow-hidden lg:flex lg:flex-col"
      id="agent-workbench"
    >
      <div class="flex items-center justify-between border-b border-js-border pb-3 gap-3 shrink-0">
        <div class="flex items-center gap-2 text-sm text-js-text-muted">
          <.link navigate={"#{@prefix}/agents"} class="hover:text-js-text">Agents</.link>
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
            </div>
          </div>

          <%= case @workbench_tab do %>
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
                        <span class="text-[11px] font-mono text-js-text-subtle">
                          {format_event_timestamp(event[:timestamp_ms])}
                        </span>
                        <.badge variant={if(event[:source] == :agent_debug, do: :warning, else: :info)}>
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
                instance_debug_error={@instance_debug_error}
                instance_observability_events={@instance_observability_events}
              />
            <% _ -> %>
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
          instance_debug_error={@instance_debug_error}
          traces_path={@traces_path}
          summary_meta={@summary_meta}
          instance_observability_events={@instance_observability_events}
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

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.stat_card label="Discovered Agents" value={to_string(length(@agents))} />
        <.stat_card label="Running" value={to_string(@running_count)} />
        <.stat_card
          label="Available"
          value={to_string(Enum.count(@agents, &(&1.status == :available)))}
        />
      </div>

      <%= if @agents == [] do %>
        <.card>
          <.empty_state
            title="No agents discovered"
            description="No agent modules were found. Make sure your application includes Jido agent definitions."
          />
        </.card>
      <% else %>
        <.card>
          <.data_table rows={@agents} scroll_x={false}>
            <:col :let={agent} label="Name">
              <.link
                navigate={"#{@prefix}/agents/#{agent.slug}"}
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
      <% end %>
    </div>
    """
  end

  attr :agent, :map, required: true
  attr :module_path, :string, required: true
  attr :instance_links, :list, required: true
  attr :active_instance_id, :string, default: nil
  attr :traces_path, :string, default: nil
  attr :instance_debug_enabled?, :boolean, default: false
  attr :instance_debug_error, :any, default: nil
  attr :summary_meta, :list, default: []
  attr :instance_observability_events, :list, default: []
  attr :class, :string, default: nil

  defp summary_pane(assigns) do
    ~H"""
    <.card class={"p-0 overflow-hidden flex flex-col min-h-0 #{@class || ""}"}>
      <div class="px-3 py-3 border-b border-js-border">
        <h3 class="text-xl font-semibold text-js-text">{humanize_agent_name(@agent.name)}</h3>
        <div class="mt-1.5">
          <.badge>{@agent.name}</.badge>
        </div>

        <div :if={@instance_links != []} class="mt-2.5 space-y-1.5">
          <div class="text-xs uppercase tracking-wider text-js-text-subtle">Running Instances</div>
          <div class="flex flex-wrap gap-1">
            <.link navigate={@module_path}>
              <.badge variant={:default}>Module</.badge>
            </.link>
            <.link :for={instance <- @instance_links} navigate={instance.path}>
              <.badge variant={if(instance.id == @active_instance_id, do: :info, else: :default)}>
                {short_instance_id(instance.id)}
              </.badge>
            </.link>
          </div>
        </div>

        <div :if={@active_instance_id} class="mt-3 flex items-center justify-between gap-2">
          <div class="text-xs uppercase tracking-wider text-js-text-subtle">Debug Buffer</div>
          <button
            type="button"
            phx-click="toggle_instance_debug"
            class={[
              "inline-flex items-center rounded-md px-2.5 py-1 text-xs border transition-colors",
              if(@instance_debug_enabled?,
                do: "border-js-info/30 bg-js-info/15 text-js-info",
                else: "border-js-border text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
              )
            ]}
          >
            <%= if @instance_debug_enabled? do %>
              Disable Debug
            <% else %>
              Enable Debug
            <% end %>
          </button>
        </div>

        <p
          :if={not is_nil(@active_instance_id) and @instance_debug_error == :debug_not_enabled}
          class="mt-2 text-xs text-js-text-subtle"
        >
          Debug buffer is currently disabled for this instance.
        </p>
      </div>

      <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-3 flex-1 min-h-0">
        <div>
          <h4 class="text-xs uppercase tracking-wider text-js-text-subtle mb-2">Overview</h4>
          <div class="flex flex-wrap gap-1.5">
            <.badge
              :for={{label, value, variant} <- @summary_meta}
              variant={variant}
            >
              {label}: {value}
            </.badge>
          </div>
        </div>

        <div>
          <div class="flex items-center justify-between gap-2 mb-2">
            <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">Recent Events</h4>
            <.link
              :if={@traces_path}
              navigate={@traces_path}
              class="text-xs text-js-info hover:text-js-text transition-colors"
            >
              View all
            </.link>
          </div>
          <%= if @instance_observability_events == [] do %>
            <p class="text-xs text-js-text-subtle">No events captured yet for this instance.</p>
          <% else %>
            <div class="space-y-1.5">
              <div
                :for={event <- Enum.take(@instance_observability_events, 3)}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2 py-1.5"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-[11px] font-mono text-js-text-subtle">
                    {format_event_timestamp(event[:timestamp_ms])}
                  </span>
                  <.badge variant={if(event[:source] == :agent_debug, do: :warning, else: :info)}>
                    {event[:source] || :telemetry}
                  </.badge>
                </div>
                <div class="mt-1 text-xs text-js-text-muted font-mono truncate">
                  {format_event_name(event)}
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </.card>
    """
  end

  attr :agent, :map, required: true
  attr :detail_tab, :atom, required: true
  attr :detail_tabs, :list, required: true
  attr :sections_by_tab, :map, required: true
  attr :system_prompt, :string, required: true
  attr :module_path, :string, required: true
  attr :instance_links, :list, required: true
  attr :active_instance_id, :string, default: nil
  attr :active_instance_pid, :any, default: nil
  attr :traces_path, :string, default: nil
  attr :instance_debug_enabled?, :boolean, default: false
  attr :instance_debug_error, :any, default: nil
  attr :instance_observability_events, :list, default: []
  attr :class, :string, default: nil

  defp settings_pane(assigns) do
    ~H"""
    <.card class={"p-0 overflow-hidden flex flex-col min-h-0 #{@class || ""}"}>
      <div class="px-3 py-3 border-b border-js-border">
        <h3 class="text-xl font-semibold text-js-text">{humanize_agent_name(@agent.name)}</h3>
        <div class="mt-1.5">
          <.badge>{@agent.name}</.badge>
        </div>

        <div :if={@instance_links != []} class="mt-2.5 space-y-1.5">
          <div class="text-xs uppercase tracking-wider text-js-text-subtle">Running Instances</div>
          <div class="flex flex-wrap gap-1">
            <.link navigate={@module_path}>
              <.badge variant={if(is_nil(@active_instance_id), do: :info, else: :default)}>
                Module
              </.badge>
            </.link>
            <.link :for={instance <- @instance_links} navigate={instance.path}>
              <.badge variant={if(instance.id == @active_instance_id, do: :info, else: :default)}>
                {short_instance_id(instance.id)}
              </.badge>
            </.link>
          </div>
        </div>

        <div :if={@active_instance_id} class="mt-3 flex items-center justify-between gap-2">
          <div class="text-xs uppercase tracking-wider text-js-text-subtle">Debug Buffer</div>
          <button
            type="button"
            phx-click="toggle_instance_debug"
            class={[
              "inline-flex items-center rounded-md px-2.5 py-1 text-xs border transition-colors",
              if(@instance_debug_enabled?,
                do: "border-js-info/30 bg-js-info/15 text-js-info",
                else: "border-js-border text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
              )
            ]}
          >
            <%= if @instance_debug_enabled? do %>
              Disable Debug
            <% else %>
              Enable Debug
            <% end %>
          </button>
        </div>

        <p
          :if={not is_nil(@active_instance_id) and @instance_debug_error == :debug_not_enabled}
          class="mt-2 text-xs text-js-text-subtle"
        >
          Debug buffer is currently disabled for this instance.
        </p>
      </div>

      <div class="px-2 py-2 border-b border-js-border flex flex-wrap items-center gap-1">
        <button
          :for={tab <- @detail_tabs}
          type="button"
          phx-click="select_detail_tab"
          phx-value-tab={tab.id}
          class={[
            "px-3 py-1.5 rounded-md text-xs whitespace-nowrap transition-colors",
            if(@detail_tab == tab.id,
              do: "bg-js-muted text-js-text",
              else: "text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            )
          ]}
        >
          {tab.label}
        </button>
      </div>

      <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-3.5 flex-1 min-h-0">
        <.detail_section
          :for={section <- Map.get(@sections_by_tab, @detail_tab, [])}
          section={section}
        />

        <div :if={@active_instance_id}>
          <div class="flex items-center justify-between gap-2 mb-2">
            <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">Recent Events</h4>
            <.link
              :if={@traces_path}
              navigate={@traces_path}
              class="text-xs text-js-info hover:text-js-text transition-colors"
            >
              View all
            </.link>
          </div>
          <%= if @instance_observability_events == [] do %>
            <p class="text-xs text-js-text-subtle">No events captured yet for this instance.</p>
          <% else %>
            <div class="space-y-1.5">
              <div
                :for={event <- Enum.take(@instance_observability_events, 10)}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2 py-1.5"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-[11px] font-mono text-js-text-subtle">
                    {format_event_timestamp(event[:timestamp_ms])}
                  </span>
                  <.badge variant={if(event[:source] == :agent_debug, do: :warning, else: :info)}>
                    {event[:source] || :telemetry}
                  </.badge>
                </div>
                <div class="mt-1 text-xs text-js-text-muted font-mono truncate">
                  {format_event_name(event)}
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <div class="mt-6">
          <h4 class="text-xs uppercase tracking-wider text-js-text-subtle mb-2">System Prompt</h4>
          <pre class="text-xs text-js-text-muted bg-js-bg-elevated border border-js-border rounded-md p-3 whitespace-pre-wrap break-words overflow-x-hidden"><%= @system_prompt %></pre>
        </div>
      </div>
    </.card>
    """
  end

  attr :section, :map, required: true

  defp detail_section(assigns) do
    ~H"""
    <div>
      <h4 class="text-xs uppercase tracking-wider text-js-text-subtle mb-2">{@section.title}</h4>
      <%= case @section.kind do %>
        <% :badge -> %>
          <.badge variant={Map.get(@section, :variant, :default)}>{@section.data}</.badge>
        <% :badges -> %>
          <div class="flex flex-wrap gap-1">
            <.badge :for={item <- List.wrap(@section.data)}>{item}</.badge>
          </div>
        <% :kv -> %>
          <div class="space-y-1">
            <div :for={{key, value} <- section_rows(@section.data)} class="text-xs text-js-text-muted">
              <span class="text-js-text-subtle">{key}:</span> {value}
            </div>
          </div>
        <% :code -> %>
          <pre class="text-xs text-js-text-muted bg-js-bg-elevated border border-js-border rounded-md p-3 whitespace-pre-wrap break-words overflow-x-auto"><%= @section.data %></pre>
        <% _ -> %>
          <p class="text-sm text-js-text-muted">{@section.data}</p>
      <% end %>
    </div>
    """
  end

  attr :show, :boolean, required: true
  attr :start_form, :map, required: true
  attr :start_form_schema, :list, required: true
  attr :start_form_error, :string, default: nil
  attr :starting_instance?, :boolean, default: false

  defp start_instance_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_start_modal"
      phx-key="escape"
    >
      <button
        type="button"
        class="absolute inset-0 bg-black/60 backdrop-blur-sm"
        phx-click="close_start_modal"
        aria-label="Close modal"
      />

      <div class="relative w-full max-w-lg rounded-xl bg-js-card border border-js-border p-6 shadow-2xl">
        <button
          type="button"
          phx-click="close_start_modal"
          class="absolute top-4 right-4 text-js-text-muted hover:text-js-text transition-colors"
          aria-label="close"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
              clip-rule="evenodd"
            />
          </svg>
        </button>

        <div class="space-y-4">
          <div>
            <h3 id="start-instance-modal-title" class="text-lg font-semibold text-js-text">
              Start Instance
            </h3>
            <p class="text-sm text-js-text-muted mt-1">
              Configure optional startup fields for this agent instance.
            </p>
          </div>

          <div
            :if={@start_form_error}
            class="rounded-md border border-js-error/40 bg-js-error/10 p-3 text-sm text-js-error"
          >
            {@start_form_error}
          </div>

          <form
            phx-change="update_start_form"
            phx-submit="start_instance_with_options"
            class="space-y-4"
          >
            <div :for={field <- @start_form_schema} class="space-y-1">
              <%= case field.type do %>
                <% :checkbox -> %>
                  <div class="space-y-2">
                    <label class="text-xs uppercase tracking-wider text-js-text-subtle">
                      Options
                    </label>
                    <div class="flex items-center gap-2">
                      <input type="hidden" name={"start[#{field.name}]"} value="false" />
                      <input
                        id={start_field_id(field.name)}
                        type="checkbox"
                        name={"start[#{field.name}]"}
                        value="true"
                        checked={Map.get(@start_form, field.name, "false") == "true"}
                        class="h-4 w-4 rounded border-js-border bg-js-bg-elevated text-js-primary focus:ring-js-ring"
                      />
                      <label for={start_field_id(field.name)} class="text-sm text-js-text-muted">
                        {field.label}
                      </label>
                    </div>
                  </div>
                <% :textarea_json -> %>
                  <label
                    for={start_field_id(field.name)}
                    class="text-xs uppercase tracking-wider text-js-text-subtle"
                  >
                    {field.label}
                  </label>
                  <textarea
                    id={start_field_id(field.name)}
                    name={"start[#{field.name}]"}
                    rows={Map.get(field, :rows, 6)}
                    placeholder={Map.get(field, :placeholder, "")}
                    class="w-full rounded-md border border-js-border bg-js-bg-elevated p-2 text-sm text-js-text font-mono focus:outline-none focus:ring-2 focus:ring-js-ring"
                  ><%= Map.get(@start_form, field.name, "") %></textarea>
                <% _ -> %>
                  <label
                    for={start_field_id(field.name)}
                    class="text-xs uppercase tracking-wider text-js-text-subtle"
                  >
                    {field.label}
                  </label>
                  <input
                    id={start_field_id(field.name)}
                    type="text"
                    name={"start[#{field.name}]"}
                    value={Map.get(@start_form, field.name, "")}
                    placeholder={Map.get(field, :placeholder, "")}
                    class="w-full rounded-md border border-js-border bg-js-bg-elevated p-2 text-sm text-js-text focus:outline-none focus:ring-2 focus:ring-js-ring"
                  />
              <% end %>
              <p :if={Map.get(field, :help)} class="text-xs text-js-text-subtle">
                {field.help}
              </p>
            </div>

            <div class="flex items-center justify-end gap-2 pt-2">
              <.button
                type="button"
                variant={:ghost}
                phx-click="close_start_modal"
                disabled={@starting_instance?}
              >
                Cancel
              </.button>
              <.button type="submit" disabled={@starting_instance?}>
                <%= if @starting_instance? do %>
                  Starting...
                <% else %>
                  Start Instance
                <% end %>
              </.button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp section_rows(data) when is_map(data) do
    Enum.map(data, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp section_rows(data) when is_list(data), do: data
  defp section_rows(_), do: []

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

  defp agent_module_path(prefix, agent), do: "#{prefix}/agents/#{agent.slug}"

  defp agent_instance_path(prefix, agent, instance_id) do
    "#{prefix}/agents/#{agent.slug}/#{URI.encode_www_form(instance_id)}"
  end

  defp instance_links(prefix, agent, running_instances, active_instance_id) do
    links =
      Enum.map(running_instances, fn instance ->
        %{id: instance.id, path: agent_instance_path(prefix, agent, instance.id)}
      end)

    if is_binary(active_instance_id) and not Enum.any?(links, &(&1.id == active_instance_id)) do
      links ++ [%{id: active_instance_id, path: agent_instance_path(prefix, agent, active_instance_id)}]
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
      "#{prefix}/traces"
    else
      "#{prefix}/traces?#{query}"
    end
  end

  defp short_instance_id(id) when is_binary(id) do
    if String.length(id) <= 12, do: id, else: String.slice(id, 0, 12)
  end

  defp short_instance_id(_), do: "instance"

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

  defp event_metadata_value(event, key) when is_map(event) do
    metadata = Map.get(event, :metadata, %{})
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp event_metadata_value(_event, _key), do: nil

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
        |> assign(:instance_observability_events, [])
        |> assign(:instance_debug_events, [])
        |> assign(:instance_telemetry_events, [])
        |> assign(:instance_debug_error, nil)
        |> assign(:instance_debug_enabled?, false)

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
        presenter = socket.assigns[:presenter] || Default

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
        |> assign(:instance_debug_enabled?, debug_enabled)
        |> assign(:instance_observability_events, Map.get(preview, :events, []))
        |> assign(:instance_debug_events, Map.get(preview, :debug_events, []))
        |> assign(:instance_telemetry_events, Map.get(preview, :telemetry_events, []))
        |> assign(:instance_debug_error, Map.get(preview, :debug_error))
        |> assign(:detail_tabs, tabs)
        |> assign(:detail_tab, preserve_detail_tab(socket.assigns[:detail_tab], tabs))
        |> assign(:sections_by_tab, Map.get(view_model, :sections_by_tab, %{}))
        |> assign(
          :system_prompt,
          Map.get(view_model, :system_prompt, "No system prompt configured.")
        )
        |> maybe_capture_thread_context_snapshot(runtime_status)
    end
  end

  defp load_workspace_for(socket, agent_slug, instance_id) do
    case ThreadsManager.load_workspace(agent_slug, instance_id,
           jido_instance: socket.assigns[:jido_instance]
         ) do
      {:ok, payload} ->
        socket
        |> assign(:chat_state, ensure_workspace_chat_state(payload.chat_state))
        |> assign(:draft_message, payload.draft_message || "")
        |> assign(:persisted_thread_contexts, payload.thread_contexts || %{})
        |> assign(:workspace_source, payload.source || :fresh)

      {:error, _reason} ->
        socket
        |> assign(:chat_state, ChatSession.with_initial_thread("New Chat"))
        |> assign(:draft_message, "")
        |> assign(:persisted_thread_contexts, %{})
        |> assign(:workspace_source, :fresh)
    end
  end

  defp schedule_workspace_persist(socket, reason, delay_ms \\ 0) do
    has_workspace? = is_binary(socket.assigns[:active_instance_id]) and not is_nil(socket.assigns[:agent])

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

  defp ensure_workspace_chat_state(%{threads: []} = _state), do: ChatSession.with_initial_thread("New Chat")

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

  defp format_event_name(event) when is_map(event) do
    cond do
      is_binary(event[:event_name]) ->
        event[:event_name]

      is_list(event[:event_prefix]) ->
        Enum.join(event[:event_prefix], ".")

      true ->
        "event"
    end
  end

  defp format_event_name(_), do: "event"

  defp format_event_timestamp(ts) when is_integer(ts) do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp format_event_timestamp(_), do: "--:--:--"

  defp workbench_tab_button_class(active?) do
    base =
      "inline-flex h-7 items-center justify-center whitespace-nowrap rounded-md border px-3 text-xs font-medium transition-colors"

    active_class = "border-js-border bg-js-card text-js-text shadow-sm"

    inactive_class =
      "border-transparent text-js-text-muted hover:text-js-text hover:bg-js-bg"

    if active?, do: "#{base} #{active_class}", else: "#{base} #{inactive_class}"
  end

  defp workbench_grid_class(true) do
    "grid grid-cols-1 gap-2 md:grid-cols-[180px_minmax(0,1fr)] md:grid-rows-[minmax(0,1fr)_minmax(0,1fr)] lg:min-h-0 lg:grid-cols-[200px_minmax(0,1fr)] lg:grid-rows-[minmax(0,1fr)_minmax(0,1fr)] xl:grid-cols-[200px_minmax(0,1fr)_300px] xl:grid-rows-[minmax(0,1fr)]"
  end

  defp workbench_grid_class(false) do
    "grid grid-cols-1 gap-2 md:grid-cols-[180px_minmax(0,1fr)] lg:grid-cols-[200px_minmax(0,1fr)] lg:min-h-0"
  end

  defp workbench_threads_rail_class(true), do: "md:row-span-2 xl:row-span-1"
  defp workbench_threads_rail_class(false), do: nil

  defp parse_workbench_tab(panel, legacy_view \\ nil)

  defp parse_workbench_tab(panel, _legacy_view) when panel in [:chat, :thread_context, :thread_events, :instance],
    do: panel

  defp parse_workbench_tab("chat", _legacy_view), do: :chat
  defp parse_workbench_tab("thread_context", _legacy_view), do: :thread_context
  defp parse_workbench_tab("context", _legacy_view), do: :thread_context
  defp parse_workbench_tab("thread_events", _legacy_view), do: :thread_events
  defp parse_workbench_tab("events", _legacy_view), do: :thread_events
  defp parse_workbench_tab("instance", _legacy_view), do: :instance
  defp parse_workbench_tab(_, "inspect"), do: :instance
  defp parse_workbench_tab(_, :inspect), do: :instance
  defp parse_workbench_tab(_, _), do: :chat

  defp workbench_path(prefix, agent, instance_id, panel, tab) do
    base = agent_instance_path(prefix, agent, instance_id)
    panel = parse_workbench_tab(panel)
    panel_value = panel_query_value(panel)
    tab_value = tab_query_value(tab)

    params =
      [{"panel", panel_value}] ++
        if(panel == :instance and is_binary(tab_value), do: [{"tab", tab_value}], else: [])

    query =
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> URI.encode_query()

    if query == "", do: base, else: "#{base}?#{query}"
  end

  defp panel_query_value(:chat), do: "chat"
  defp panel_query_value(:thread_context), do: "thread_context"
  defp panel_query_value(:thread_events), do: "thread_events"
  defp panel_query_value(:instance), do: "instance"
  defp panel_query_value(_), do: "chat"

  defp tab_query_value(tab) when is_atom(tab), do: Atom.to_string(tab)
  defp tab_query_value(tab) when is_binary(tab) and tab != "", do: tab
  defp tab_query_value(_), do: nil

  defp thread_context_sections(sections_by_tab, persisted_contexts, active_thread_id, instance_online?)
       when is_map(sections_by_tab) do
    context = Map.get(sections_by_tab, :context, [])
    reasoning = Map.get(sections_by_tab, :reasoning, [])
    overview = Map.get(sections_by_tab, :overview, [])
    persisted = persisted_thread_context_sections(persisted_contexts, active_thread_id, instance_online?)

    sections = context ++ reasoning ++ overview ++ persisted

    if sections == [], do: [], else: sections
  end

  defp thread_context_sections(_, persisted_contexts, active_thread_id, instance_online?) do
    persisted_thread_context_sections(persisted_contexts, active_thread_id, instance_online?)
  end

  defp persisted_thread_context_sections(contexts, active_thread_id, instance_online?) do
    with true <- is_map(contexts),
         true <- is_binary(active_thread_id),
         %{} = snapshot <- Map.get(contexts, active_thread_id) do
      summary_rows =
        [
          {"Source", if(instance_online?, do: "Persisted snapshot (live available)", else: "Persisted snapshot (instance offline)")},
          {"Captured At", format_event_timestamp(Map.get(snapshot, :captured_at))},
          {"Status", to_string(Map.get(snapshot, :status, "unknown"))},
          {"Strategy Thread", to_string(Map.get(snapshot, :strategy_thread_id, "n/a"))},
          {"Iteration", to_string(Map.get(snapshot, :iteration, 0))},
          {"Conversation", to_string(Map.get(snapshot, :conversation_count, 0))},
          {"Pending Tool Calls", to_string(Map.get(snapshot, :pending_tool_calls_count, 0))},
          {"Thinking Blocks", to_string(Map.get(snapshot, :thinking_blocks_count, 0))},
          {"Termination", to_string(Map.get(snapshot, :termination_reason, "n/a"))},
          {"Model", to_string(Map.get(snapshot, :model, "n/a"))}
        ]

      sections = [
        %{title: "Persisted Context Snapshot", kind: :kv, data: summary_rows, variant: :warning}
      ]

      case Map.get(snapshot, :strategy_state) do
        %{} = strategy_state ->
          sections ++
            [
              %{
                title: "Persisted Strategy State",
                kind: :code,
                data: inspect(strategy_state, pretty: true, limit: 120, printable_limit: 20_000),
                variant: :default
              }
            ]

        _ ->
          sections
      end
    else
      _ -> []
    end
  end

  defp active_strategy_thread_id(%{raw_state: raw_state}) when is_map(raw_state) do
    raw_state
    |> Map.get(:__strategy__, %{})
    |> Map.get(:thread, %{})
    |> Map.get(:id)
  end

  defp active_strategy_thread_id(_), do: nil

  defp thread_events_for_display(events, thread_id) when is_list(events) do
    filtered =
      if is_binary(thread_id) and thread_id != "" do
        Enum.filter(events, fn event ->
          case event_thread_id(event) do
            nil -> false
            value -> value == thread_id
          end
        end)
      else
        []
      end

    selected =
      cond do
        filtered != [] -> filtered
        true -> events
      end

    selected
    |> Enum.take(60)
  end

  defp thread_events_for_display(_, _), do: []

  defp event_thread_id(event) when is_map(event) do
    metadata = Map.get(event, :metadata, %{})
    Map.get(metadata, :thread_id) || Map.get(metadata, "thread_id")
  end

  defp event_thread_id(_), do: nil

  defp ordered_detail_tabs(tabs) when is_list(tabs) do
    desired = [:overview, :reasoning, :context, :weather, :model, :memory, :tracing]

    sorted =
      tabs
      |> Enum.sort_by(fn tab ->
        case Enum.find_index(desired, &(&1 == tab.id)) do
          nil -> 1_000
          idx -> idx
        end
      end)

    if sorted == [], do: [%{id: :overview, label: "Overview"}], else: sorted
  end

  defp ordered_detail_tabs(_), do: [%{id: :overview, label: "Overview"}]

  defp summary_meta(runtime_status, model_label) do
    details = runtime_status && runtime_status.snapshot && runtime_status.snapshot.details || %{}
    status = runtime_status && runtime_status.snapshot && runtime_status.snapshot.status

    [
      {"Status", summary_status_label(status), summary_status_variant(status)},
      {"Model", to_string(model_label || "n/a"), :info},
      {"Iteration", to_string(details[:iteration] || 0), :default},
      {"Tool Calls", to_string(length(details[:tool_calls] || [])), :default},
      {"Turns", to_string(length(details[:conversation] || [])), :default}
    ]
  end

  defp summary_status_label(status) do
    status = if is_nil(status), do: :offline, else: status

    status
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp summary_status_variant(:running), do: :success
  defp summary_status_variant(:success), do: :success
  defp summary_status_variant(:error), do: :error
  defp summary_status_variant(_), do: :default

  defp default_start_form(schema) do
    Enum.reduce(schema, %{}, fn field, acc ->
      Map.put(acc, field.name, default_field_value(field))
    end)
  end

  defp normalize_start_form(form, schema) do
    defaults = default_start_form(schema)

    Enum.reduce(schema, defaults, fn field, acc ->
      key = field.name
      raw = Map.get(form, key)
      Map.put(acc, key, normalize_field_value(field, raw))
    end)
  end

  defp default_field_value(%{type: :checkbox} = field) do
    if Map.get(field, :default, "false") in ["true", "on", "1"], do: "true", else: "false"
  end

  defp default_field_value(field), do: Map.get(field, :default, "")

  defp normalize_field_value(%{type: :checkbox}, raw) do
    if raw in ["true", "on", "1"], do: "true", else: "false"
  end

  defp normalize_field_value(_field, raw), do: to_string(raw || "") |> String.trim()

  defp build_start_opts(form) do
    instance_id = form["instance_id"] |> to_string() |> String.trim()
    debug? = form["debug"] == "true"

    with {:ok, initial_state} <- parse_initial_state(form["initial_state_json"]) do
      opts = []
      opts = if instance_id == "", do: opts, else: [{:id, instance_id} | opts]
      opts = if debug?, do: [{:debug, true} | opts], else: opts
      opts = if initial_state == %{}, do: opts, else: [{:initial_state, initial_state} | opts]
      {:ok, Enum.reverse(opts)}
    end
  end

  defp parse_initial_state(nil), do: {:ok, %{}}
  defp parse_initial_state(""), do: {:ok, %{}}

  defp parse_initial_state(raw_json) when is_binary(raw_json) do
    json = String.trim(raw_json)

    if json == "" do
      {:ok, %{}}
    else
      case Jason.decode(json) do
        {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
        {:ok, _other} -> {:error, "Initial state JSON must decode to an object/map."}
        {:error, error} -> {:error, "Invalid initial state JSON: #{Exception.message(error)}"}
      end
    end
  end

  defp parse_initial_state(_), do: {:error, "Initial state must be valid JSON."}

  defp resolve_instance_id(_jido_instance, pid, _opts) when is_pid(pid) do
    with {:ok, state} <- Jido.AgentServer.state(pid),
         id when is_binary(id) <- state.id do
      {:ok, id}
    else
      _ -> {:error, "Started instance but failed to resolve instance ID."}
    end
  rescue
    _ -> {:error, "Started instance but failed to resolve instance ID."}
  end

  defp format_start_error(reason) when is_binary(reason), do: reason
  defp format_start_error(reason), do: "Failed to start agent instance: #{inspect(reason)}"

  defp start_field_id(name) when is_binary(name) do
    "start-" <>
      (name
       |> String.downcase()
       |> String.replace(~r/[^a-z0-9]+/, "-")
       |> String.trim("-"))
  end

  defp now_ms, do: System.system_time(:millisecond)

  defp humanize_agent_name(name), do: Naming.humanize(name)
end
