defmodule JidoStudio.WorkflowsLive do
  @moduledoc false
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Workflows")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Workflows")
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    assign(socket, :page_title, "Workflow: #{id}")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-2xl font-bold text-js-text mb-4">{@page_title}</h1>
      <p class="text-gray-400">Workflow visualization coming soon.</p>
    </div>
    """
  end
end
