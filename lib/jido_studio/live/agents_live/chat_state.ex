defmodule JidoStudio.Live.AgentsLive.ChatState do
  @moduledoc false

  require Phoenix.LiveView

  import Phoenix.Component, only: [assign: 3]

  alias JidoStudio.Chat.Runtime, as: ChatRuntime
  alias JidoStudio.Chat.Session, as: ChatSession
  alias JidoStudio.Live.AgentsLive.ObservabilityState
  alias JidoStudio.Live.AgentsLive.ShowState
  alias JidoStudio.Live.AgentsLive.Support
  alias JidoStudio.Live.AgentsLive.WorkspaceState

  def handle_send_message(socket) do
    message = String.trim(socket.assigns.draft_message || "")

    cond do
      message == "" ->
        {:noreply, socket}

      socket.assigns.chat_pending? ->
        {:noreply, socket}

      not socket.assigns.chat_enabled? ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           Support.chat_unavailable_message(socket.assigns[:chat_unavailable_reason])
         )}

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
        since_entry_count = ShowState.stream_since_entry_count(pid)
        traces_path = ShowState.current_traces_path(socket)

        socket =
          socket
          |> assign(:chat_state, chat_state)
          |> assign(:draft_message, "")
          |> assign(:chat_pending?, true)
          |> assign(:chat_pending_message_id, pending_id)
          |> WorkspaceState.schedule_workspace_persist(:send_message)

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

                socket =
                  assign(socket, :chat_stream, %{
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
                  })

                {:noreply,
                 Phoenix.LiveView.start_async(
                   socket,
                   {:chat_turn_async, pending_id, request_id},
                   fn ->
                     ChatRuntime.await_request(agent_module, request, timeout_ms: timeout_ms)
                   end
                 )}

              {:error, reason} ->
                error_message = ChatRuntime.to_user_message(reason, timeout_ms: timeout_ms)

                socket =
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
                  |> WorkspaceState.schedule_workspace_persist(:chat_error)

                {:noreply, socket}
            end

          true ->
            {:noreply,
             Phoenix.LiveView.start_async(socket, {:chat_turn_sync, pending_id}, fn ->
               ChatRuntime.ask(agent_module, pid, message, timeout_ms: timeout_ms)
             end)}
        end
    end
  end

  def handle_async(socket, {:chat_turn_sync, pending_id}, {:ok, {:ok, reply}}) do
    resolve_chat_reply(socket, pending_id, reply)
  end

  def handle_async(socket, {:chat_turn_async, pending_id, request_id}, {:ok, {:ok, reply}}) do
    if chat_stream_match?(socket, pending_id, request_id) do
      resolve_chat_reply(socket, pending_id, reply)
    else
      socket
    end
  end

  def handle_async(socket, {:chat_turn_sync, pending_id}, {:ok, {:error, reason}}) do
    resolve_chat_error(socket, pending_id, reason)
  end

  def handle_async(socket, {:chat_turn_async, pending_id, request_id}, {:ok, {:error, reason}}) do
    if chat_stream_match?(socket, pending_id, request_id) do
      resolve_chat_error(socket, pending_id, reason)
    else
      socket
    end
  end

  def handle_async(socket, {:chat_turn_sync, pending_id}, {:exit, reason}) do
    resolve_chat_error(socket, pending_id, reason)
  end

  def handle_async(socket, {:chat_turn_async, pending_id, request_id}, {:exit, reason}) do
    if chat_stream_match?(socket, pending_id, request_id) do
      resolve_chat_error(socket, pending_id, reason)
    else
      socket
    end
  end

  def handle_async(socket, {:chat_turn_sync, pending_id}, {:ok, other}) do
    resolve_chat_error(socket, pending_id, {:unexpected_result, other})
  end

  def handle_async(socket, {:chat_turn_async, pending_id, request_id}, {:ok, other}) do
    if chat_stream_match?(socket, pending_id, request_id) do
      resolve_chat_error(socket, pending_id, {:unexpected_result, other})
    else
      socket
    end
  end

  def handle_async(socket, _name, _result), do: socket

  def handle_stream_tick(socket, pending_id, request_id) do
    if chat_stream_match?(socket, pending_id, request_id) do
      stream = socket.assigns.chat_stream

      socket =
        case ChatRuntime.stream_snapshot(stream.pid,
               since_entry_count: stream.since_entry_count
             ) do
          {:ok, snapshot} ->
            partial_text = snapshot.streaming_text || ""

            tool_events =
              ObservabilityState.enrich_tool_events(
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

      socket
    else
      socket
    end
  end

  defp resolve_chat_reply(socket, pending_id, reply) do
    socket
    |> assign(
      :chat_state,
      ChatSession.resolve_assistant_reply(socket.assigns.chat_state, pending_id, reply)
    )
    |> clear_chat_pending()
    |> WorkspaceState.schedule_workspace_persist(:chat_reply)
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
    |> WorkspaceState.schedule_workspace_persist(:chat_error)
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
      |> WorkspaceState.schedule_workspace_persist(:stream_partial, 400)
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
    |> WorkspaceState.schedule_workspace_persist(:stream_tool_events, 400)
  end

  defp chat_stream_match?(socket, pending_id, request_id) do
    stream = socket.assigns[:chat_stream]

    is_map(stream) and socket.assigns.chat_pending? and stream.pending_id == pending_id and
      stream.request_id == request_id
  end
end
