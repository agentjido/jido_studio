defmodule JidoStudio.ThreadsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Cluster.Scope
  alias JidoStudio.PathSegments
  alias JidoStudio.Threads

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(3_000, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Threads")
      |> assign(:query, "")
      |> assign(:threads, [])
      |> assign(:thread, nil)
      |> assign(:entries, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = normalize_optional_string(params["q"]) || ""

    threads =
      Threads.list_threads(
        query: query,
        jido_instance: socket.assigns[:jido_instance]
      )

    socket =
      socket
      |> assign(:query, query)
      |> assign(:threads, threads)

    case socket.assigns.live_action do
      :show ->
        agent_slug = decode_segment(params["agent_slug"])
        instance_id = decode_segment(params["instance_id"])
        thread_id = decode_segment(params["thread_id"])

        case Threads.get_thread(agent_slug, instance_id, thread_id,
               jido_instance: socket.assigns[:jido_instance]
             ) do
          {:ok, payload} ->
            {:noreply,
             socket
             |> assign(:thread, payload.thread)
             |> assign(:entries, payload.entries)}

          _ ->
            {:noreply,
             socket
             |> put_flash(:error, "Thread not found")
             |> assign(:thread, nil)
             |> assign(:entries, [])}
        end

      _ ->
        {:noreply, socket |> assign(:thread, nil) |> assign(:entries, [])}
    end
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    query = normalize_optional_string(query) || ""

    {:noreply,
     push_patch(socket,
       to:
         query_path(
           socket.assigns.prefix,
           query,
           socket.assigns.live_action,
           socket.assigns.thread
         )
     )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    threads =
      Threads.list_threads(
        query: socket.assigns.query,
        jido_instance: socket.assigns[:jido_instance]
      )

    {:noreply, assign(socket, :threads, threads)}
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Threads" subtitle="Inspect persisted thread and memory entries">
        <:actions>
          <.link
            navigate={list_path(@prefix, @query)}
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            Back to Threads
          </.link>
        </:actions>
      </.page_header>

      <.card :if={is_nil(@thread)}>
        <.empty_state
          title="Thread not available"
          description="The selected thread could not be loaded from storage."
        />
      </.card>

      <%= if @thread do %>
        <div class="grid grid-cols-1 lg:grid-cols-4 gap-4">
          <.card class="lg:col-span-1">
            <div class="space-y-2 text-xs text-js-text-muted">
              <div>
                <span class="text-js-text-subtle">Thread:</span> <code>{@thread.thread_id}</code>
              </div>
              <div><span class="text-js-text-subtle">Agent:</span> {@thread.agent_slug}</div>
              <div>
                <span class="text-js-text-subtle">Instance:</span> <code>{@thread.instance_id}</code>
              </div>
              <div><span class="text-js-text-subtle">Revision:</span> {@thread.rev}</div>
              <div><span class="text-js-text-subtle">Entries:</span> {@thread.entry_count}</div>
            </div>
          </.card>

          <.card class="lg:col-span-3 p-0 overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full">
                <thead>
                  <tr class="border-b border-js-border">
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Seq
                    </th>
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Type
                    </th>
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      At
                    </th>
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Payload
                    </th>
                    <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                      Refs
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-js-border">
                  <tr :for={entry <- @entries} class="hover:bg-js-bg-elevated/50">
                    <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">{entry.seq}</td>
                    <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">{entry.kind}</td>
                    <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                      {format_timestamp(entry.at)}
                    </td>
                    <td class="px-3 py-2 text-xs text-js-text-muted">
                      <div class="font-mono truncate max-w-md">{entry.payload_preview}</div>
                    </td>
                    <td class="px-3 py-2 text-xs text-js-text-muted">
                      <div class="flex items-center gap-2 flex-wrap">
                        <.link
                          :if={entry.trace_id}
                          navigate={trace_path(@prefix, entry.trace_id)}
                          class="text-js-info hover:text-js-text"
                        >
                          trace:{entry.trace_id}
                        </.link>
                        <span :if={entry.span_id} class="font-mono text-js-text-subtle">
                          span:{entry.span_id}
                        </span>
                        <span :if={entry.trace_id == nil and entry.span_id == nil}>—</span>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.card>
        </div>
      <% end %>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header
        title="Threads"
        subtitle="Browse thread and memory checkpoints from Studio persistence"
      >
        <:actions>
          <form phx-change="search" class="flex items-center gap-2">
            <input
              type="text"
              name="q"
              value={@query}
              placeholder="Search thread/agent/instance"
              class="w-64 rounded-md border border-js-border bg-js-bg-elevated px-3 py-1.5 text-xs text-js-text focus:outline-none focus:ring-2 focus:ring-js-ring"
            />
          </form>
        </:actions>
      </.page_header>

      <.card :if={@threads == []}>
        <.empty_state
          title="No persisted threads"
          description="Thread checkpoints appear after interacting with agent chat and persistence is enabled."
        />
      </.card>

      <.card :if={@threads != []} class="p-0 overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead>
              <tr class="border-b border-js-border">
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Thread ID
                </th>
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Agent
                </th>
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Instance
                </th>
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Last Updated
                </th>
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                  Entry Count
                </th>
                <th class="px-3 py-2 text-left text-xs uppercase tracking-wider text-js-text-muted">
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-js-border">
              <tr :for={thread <- @threads} class="hover:bg-js-bg-elevated/50">
                <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">{thread.thread_id}</td>
                <td class="px-3 py-2 text-xs text-js-text-muted">{thread.agent_slug}</td>
                <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">{thread.agent_id}</td>
                <td class="px-3 py-2 text-xs text-js-text-subtle font-mono">
                  {format_timestamp(thread.updated_at)}
                </td>
                <td class="px-3 py-2 text-xs text-js-text-subtle">{thread.entry_count}</td>
                <td class="px-3 py-2 text-right">
                  <.link
                    navigate={detail_path(@prefix, thread, @query)}
                    class="text-xs text-js-info hover:text-js-text"
                  >
                    View
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.card>
    </div>
    """
  end

  defp list_path(prefix, "") do
    Scope.with_scope_query(prefix <> "/threads", Scope.current_node_param())
  end

  defp list_path(prefix, query) do
    Scope.with_scope_query(
      prefix <> "/threads?" <> URI.encode_query(%{"q" => query}),
      Scope.current_node_param()
    )
  end

  defp detail_path(prefix, thread, query) do
    base =
      prefix <>
        "/threads/" <>
        PathSegments.encode(thread.agent_slug) <>
        "/" <>
        PathSegments.encode(thread.instance_id) <>
        "/" <>
        PathSegments.encode(thread.thread_id)

    if query == "" do
      Scope.with_scope_query(base, Scope.current_node_param())
    else
      Scope.with_scope_query(
        base <> "?" <> URI.encode_query(%{"q" => query}),
        Scope.current_node_param()
      )
    end
  end

  defp query_path(prefix, query, :show, thread) when is_map(thread) do
    detail_path(prefix, thread, query)
  end

  defp query_path(prefix, query, _action, _thread), do: list_path(prefix, query)

  defp trace_path(prefix, trace_id) do
    Scope.with_scope_query(
      prefix <> "/traces/" <> URI.encode_www_form(trace_id),
      Scope.current_node_param()
    )
  end

  defp decode_segment(value) when is_binary(value), do: PathSegments.decode(value)
  defp decode_segment(_), do: ""

  defp format_timestamp(ts) when is_integer(ts) and ts > 0 do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_timestamp(_), do: "—"

  defp normalize_optional_string(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_string(_), do: nil
end
