defmodule JidoStudio.MessagingRoomsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Messaging

  @refresh_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Messaging Rooms")
      |> assign(:rooms, [])
      |> assign(:status, :ok)
      |> assign(:error, nil)
      |> refresh_rooms()

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, refresh_rooms(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, refresh_rooms(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header
        title="Messaging Rooms"
        subtitle="Current room topology from jido_messaging runtime."
      >
        <:actions>
          <button
            type="button"
            phx-click="refresh"
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            Refresh
          </button>
        </:actions>
      </.page_header>

      <%= case @status do %>
        <% :ok -> %>
          <%= if @rooms == [] do %>
            <.empty_state
              title="No rooms found"
              description="No active rooms are currently reported by the messaging provider."
            />
          <% else %>
            <.card class="p-0 overflow-hidden">
              <.data_table rows={@rooms}>
                <:col :let={room} label="Name">
                  <div class="font-medium text-js-text">{room.name}</div>
                  <div class="text-xs text-js-text-subtle font-mono">{room.id}</div>
                </:col>
                <:col :let={room} label="Members">
                  <span class="text-js-text">{room.member_count || "n/a"}</span>
                </:col>
                <:col :let={room} label="Status">
                  <.badge variant={:default}>{room.status || "unknown"}</.badge>
                </:col>
                <:col :let={room} label="Topic">
                  <span class="text-js-text-muted">{room.topic || "-"}</span>
                </:col>
              </.data_table>
            </.card>
          <% end %>
        <% :unavailable -> %>
          <.empty_state
            title="Messaging runtime unavailable"
            description="jido_messaging is installed but no compatible room provider was found."
          />
        <% :error -> %>
          <.card>
            <h3 class="text-sm font-medium text-js-error">Unable to load rooms</h3>
            <p class="text-xs text-js-text-muted mt-2 break-words">{@error}</p>
          </.card>
      <% end %>
    </div>
    """
  end

  defp refresh_rooms(socket) do
    case Messaging.list_rooms() do
      {:ok, rooms} ->
        socket
        |> assign(:rooms, rooms)
        |> assign(:status, :ok)
        |> assign(:error, nil)

      {:error, :unavailable} ->
        socket
        |> assign(:rooms, [])
        |> assign(:status, :unavailable)
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:rooms, [])
        |> assign(:status, :error)
        |> assign(:error, inspect(reason))
    end
  end
end
