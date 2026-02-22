defmodule JidoStudio.Live.AgentsLive.WorkspaceState do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias JidoStudio.Chat.Session, as: ChatSession
  alias JidoStudio.Live.AgentsLive.ShowState
  alias JidoStudio.Live.AgentsLive.Support
  alias JidoStudio.Threads.Manager, as: ThreadsManager
  alias JidoStudio.Threads.Storage, as: ThreadsStorage

  def ensure_workspace_state(socket, agent, active_instance_id, opts \\ []) do
    chat_provider_options = Keyword.get(opts, :chat_provider_options, ["anthropic"])

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
        |> assign(:ui_model, ShowState.strategy_model(agent.module))
        |> ShowState.assign_chat_controls(
          ShowState.strategy_model(agent.module),
          chat_provider_options
        )

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
          |> assign(:ui_model, ShowState.strategy_model(agent.module))
          |> ShowState.assign_chat_controls(
            ShowState.strategy_model(agent.module),
            chat_provider_options
          )
          |> load_workspace_for(agent.slug, instance_id)
        end
    end
  end

  def schedule_workspace_persist(socket, reason, delay_ms \\ 0) do
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

  def persist_workspace(socket, _reason) do
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

  def maybe_capture_thread_context_snapshot(socket, runtime_status) do
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

  def load_workspace_for(socket, agent_slug, instance_id) do
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

  def ensure_workspace_chat_state(%{threads: []} = _state),
    do: ChatSession.with_initial_thread("New Chat")

  def ensure_workspace_chat_state(%{} = state) do
    %{
      threads: Map.get(state, :threads, []),
      active_thread_id: Map.get(state, :active_thread_id),
      messages_by_thread: Map.get(state, :messages_by_thread, %{})
    }
  end

  def ensure_workspace_chat_state(_), do: ChatSession.with_initial_thread("New Chat")

  def cancel_workspace_persist_timer({timer_ref, _token}) when is_reference(timer_ref) do
    _ = Process.cancel_timer(timer_ref)
    :ok
  end

  def cancel_workspace_persist_timer(ref) when is_reference(ref) do
    _ = Process.cancel_timer(ref)
    :ok
  end

  def cancel_workspace_persist_timer(_), do: :ok

  def build_thread_context_snapshot(%{raw_state: raw_state, snapshot: snapshot}, mode)
      when is_map(raw_state) and is_map(snapshot) do
    strategy_state = raw_state[:__strategy__] || %{}
    details = snapshot_details(snapshot)

    summary = %{
      captured_at: Support.now_ms(),
      source: :live,
      status: to_string(snapshot_status(snapshot)),
      strategy_thread_id: Support.active_strategy_thread_id(%{raw_state: raw_state}),
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

  def build_thread_context_snapshot(_, _), do: nil

  def snapshot_details(%{details: details}) when is_map(details), do: details
  def snapshot_details(_), do: %{}

  def snapshot_status(%{status: nil}), do: :unknown
  def snapshot_status(%{status: status}), do: status
  def snapshot_status(_), do: :unknown

  def detail_value(details, key, default \\ nil)

  def detail_value(details, key, default) when is_map(details) and is_atom(key) do
    Map.get(details, key, Map.get(details, Atom.to_string(key), default))
  end

  def detail_value(_, _, default), do: default
end
