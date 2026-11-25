defmodule JidoStudio.HomeLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.{AgentReads, Mount}
  alias Phoenix.LiveView.AsyncResult

  @preview_limit 5

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Jido Studio", checked_at: nil)
     |> load_inventory()}
  end

  @impl true
  def handle_event("refresh", _params, %{assigns: %{inventory: %{loading: true}}} = socket) do
    {:noreply, socket}
  end

  def handle_event("refresh", _params, socket), do: {:noreply, load_inventory(socket)}

  @impl true
  def handle_async(:inventory, {:ok, {:ok, ids}}, socket) do
    summary = %{total: length(ids), preview: Enum.take(ids, @preview_limit)}
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

    {:noreply, assign(socket, inventory: AsyncResult.ok(summary), checked_at: checked_at)}
  end

  def handle_async(:inventory, _failure, %{assigns: %{inventory: inventory}} = socket) do
    {:noreply, assign(socket, :inventory, AsyncResult.failed(inventory, :runtime_unavailable))}
  end

  defp load_inventory(%{assigns: %{studio_runtime: %{jido: nil}}} = socket) do
    assign(socket, :inventory, AsyncResult.failed(AsyncResult.loading(), :not_configured))
  end

  defp load_inventory(socket) do
    runtime = socket.assigns.studio_runtime

    socket
    |> assign(:inventory, AsyncResult.loading())
    |> start_async(:inventory, fn -> AgentReads.list(runtime) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="studio-overview-page">
      <.page_header id="studio-overview" title="Overview">
        <:actions :if={@studio_runtime.jido}>
          <.button
            id="studio-overview-refresh"
            variant={:secondary}
            phx-click="refresh"
            disabled={@inventory.loading}
          >
            {if @inventory.failed == :runtime_unavailable, do: "Retry", else: "Refresh"}
          </.button>
        </:actions>
      </.page_header>

      <.card id="studio-overview-runtime" class="studio-overview-runtime">
        <div :if={@studio_runtime.jido} id="studio-overview-scope" class="studio-overview-scope">
          <code>{inspect(@studio_runtime.jido)}</code>
          <span>
            {if @studio_runtime.partition,
              do: "Partition #{@studio_runtime.partition}",
              else: "Unpartitioned"}
          </span>
        </div>
        <div class="studio-overview-check">
          <div id="studio-overview-runtime-status" role="status">
            <%= cond do %>
              <% @inventory.loading -> %>
                <p class="studio-read-loading"><span aria-hidden="true"></span> Checking runtime…</p>
              <% @inventory.ok? -> %>
                <.badge variant={:success}>
                  <.status_dot status={:online} /> Runtime reachable
                </.badge>
              <% @inventory.failed == :not_configured -> %>
                <.badge>No runtime configured</.badge>
              <% true -> %>
                <.badge variant={:warning}>Runtime unavailable</.badge>
            <% end %>
          </div>
          <p :if={@checked_at} class="studio-overview-checked-at">
            {if @inventory.ok?, do: "Checked at", else: "Last successful check"}
            <time datetime={DateTime.to_iso8601(@checked_at)}>
              {Calendar.strftime(@checked_at, "%b %d, %H:%M:%S UTC")}
            </time>
          </p>
        </div>
        <details :if={@inventory.failed == :not_configured} id="studio-overview-mount-instructions">
          <summary>Studio mount instructions</summary>
          <p>Start the Jido runtime under the host application's supervisor.</p>
          <p>Pass the registered runtime name to the Studio mount in the Phoenix router.</p>
          <pre><code>jido_studio "/studio", jido: MyApp.Jido</code></pre>
        </details>
      </.card>

      <.card
        :if={@inventory.ok?}
        id="studio-overview-instances"
        role="region"
        aria-labelledby="studio-overview-instances-title"
      >
        <div class="studio-card-header">
          <div>
            <h2 id="studio-overview-instances-title">Resident instances</h2>
            <p id="studio-overview-instance-count">{@inventory.result.total} in this partition</p>
          </div>
          <.link
            id="studio-overview-all-agents"
            class="studio-button studio-button-secondary studio-button-sm"
            href={Mount.path(@studio_path, "/agents", @studio_scope)}
          >
            View all agents
          </.link>
        </div>
        <.empty_state
          :if={@inventory.result.total == 0}
          title="No resident instances"
          description="Instances appear after the host starts them in this partition."
        />
        <ul
          :if={@inventory.result.total > 0}
          id="studio-overview-instance-rows"
          class="studio-overview-instance-list"
          role="list"
        >
          <li :for={id <- @inventory.result.preview}>
            <.link
              class="studio-instance-link"
              href={Mount.agent_path(@studio_path, id, @studio_scope)}
            >
              <code>{id}</code>
            </.link>
          </li>
        </ul>
        <p
          :if={@inventory.result.total > length(@inventory.result.preview)}
          class="studio-overview-more"
        >
          Showing {length(@inventory.result.preview)} of {@inventory.result.total}
        </p>
      </.card>
    </div>
    """
  end
end
