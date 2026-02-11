defmodule JidoStudio.SignalsLive do
  @moduledoc false
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Signals")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-2xl font-bold text-js-text mb-4">{@page_title}</h1>
      <p class="text-gray-400">Signal monitoring coming soon.</p>
    </div>
    """
  end
end
