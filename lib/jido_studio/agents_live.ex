defmodule JidoStudio.AgentsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.{Access, AgentReads, Mount, SignalActions, SignalComponents}
  alias Phoenix.LiveView.AsyncResult

  @impl true
  def mount(_params, _session, %{assigns: %{live_action: :agents}} = socket) do
    {:ok,
     socket
     |> assign(:page_title, "Agents")
     |> assign_new(:studio_agents_action, fn -> nil end)
     |> assign_new(:studio_agents_definition, fn -> nil end)
     |> stream_configure(:instances, dom_id: &instance_dom_id/1)
     |> stream(:instances, [])
     |> load(:instances)}
  end

  def mount(%{"agent_id" => "instance", "id" => id}, _session, socket)
      when is_binary(id) and byte_size(id) > 0 do
    {:ok, assign(socket, :legacy_instance_id, id)}
  end

  def mount(%{"agent_id" => segment}, _session, socket) do
    id = Mount.decode_agent_id(segment)

    {:ok,
     socket
     |> assign(page_title: id, instance_id: id, signal_turn: nil)
     |> assign_new(:studio_definition_path, fn -> nil end)
     |> load_detail()}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{legacy_instance_id: id}} = socket) do
    %{studio_path: mount, studio_scope: scope} = socket.assigns
    {:noreply, redirect(socket, to: Mount.agent_path(mount, id, scope))}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("reload", _params, %{assigns: %{live_action: :agents}} = socket) do
    {:noreply, load(socket, :instances)}
  end

  def handle_event("reload", params, %{assigns: %{instance_id: id}} = socket)
      when is_binary(id) do
    socket =
      case params["panel"] do
        "status" -> load(socket, :status)
        "snapshot" -> load(socket, :snapshot)
        nil -> load_detail(socket)
        _ -> socket
      end

    {:noreply, socket}
  end

  def handle_event("reload", _params, socket), do: {:noreply, socket}

  def handle_event("send_signal", %{"type" => type}, socket) do
    %{studio_runtime: runtime} = socket.assigns

    with true <- Access.allowed?(socket, :action),
         %{
           instance_id: id,
           snapshot: %AsyncResult{ok?: true, result: snapshot},
           signal_turn: turn
         } <-
           socket.assigns,
         false <- match?(%AsyncResult{loading: true}, turn),
         %{type: ^type} = action <- Enum.find(snapshot.signal_buttons, &(&1.type == type)) do
      {:noreply,
       socket
       |> assign(:signal_turn, AsyncResult.loading())
       |> start_async(:signal_turn, fn -> SignalActions.dispatch(runtime, id, action) end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("send_signal", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:instances, {:ok, {:ok, ids}}, socket) do
    {:noreply,
     socket
     |> stream(:instances, ids, reset: true)
     |> assign(:instances, AsyncResult.ok(length(ids)))}
  end

  def handle_async(:signal_turn, {:ok, {:ok, turn}}, socket) do
    {:noreply, socket |> assign(:signal_turn, AsyncResult.ok(turn)) |> load_detail()}
  end

  def handle_async(panel, {:ok, {:ok, result}}, socket) do
    {:noreply, assign(socket, panel, AsyncResult.ok(result))}
  end

  def handle_async(panel, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, panel, AsyncResult.failed(socket.assigns[panel], reason))}
  end

  def handle_async(panel, {:exit, _reason}, socket) do
    handle_async(panel, {:ok, {:error, :read_failed}}, socket)
  end

  defp load_detail(socket), do: socket |> load(:status) |> load(:snapshot)

  defp load(socket, panel) do
    runtime = socket.assigns.studio_runtime
    id = socket.assigns[:instance_id]

    actions =
      if Access.allowed?(socket, :action),
        do: socket.assigns[:studio_signal_actions] || [],
        else: []

    case socket.assigns[panel] do
      %AsyncResult{loading: true} ->
        socket

      _ ->
        socket
        |> assign(panel, AsyncResult.loading())
        |> start_async(panel, fn -> read(panel, runtime, id, actions) end)
    end
  end

  defp read(:instances, runtime, _id, _actions), do: AgentReads.list(runtime)
  defp read(:status, runtime, id, _actions), do: AgentReads.status(runtime, id)
  defp read(:snapshot, runtime, id, actions), do: AgentReads.snapshot(runtime, id, actions)

  @impl true
  def render(%{live_action: :agents} = assigns) do
    ~H"""
    <div id="studio-agents" class="studio-agent-page">
      <.page_header
        title="Agents"
        subtitle="Inspect resident instances in this Jido runtime."
      >
        <:actions>
          <.link
            :if={@studio_agents_definition}
            id="studio-agents-definition"
            class="studio-button studio-button-secondary studio-button-md"
            href={@studio_agents_definition.path}
          >
            {@studio_agents_definition.label}
          </.link>
          <.form
            :if={@studio_agents_action}
            for={%{}}
            id="studio-agents-host-action"
            action={@studio_agents_action.path}
            method="post"
          >
            <.button type="submit">{@studio_agents_action.label}</.button>
          </.form>
          <.button
            id="studio-refresh-agents"
            variant={:secondary}
            phx-click="reload"
            disabled={@instances.loading}
          >
            Refresh
          </.button>
        </:actions>
      </.page_header>

      <%= if message = Phoenix.Flash.get(@flash, :studio_agents_error) do %>
        <.notice title="Could not complete the action" tone={:warning}>
          <span role="status">{message}</span>
        </.notice>
      <% end %>

      <.read_panel id="studio-agent-list" title="Instances" panel="instances" result={@instances}>
        <:description :if={@instances.ok?}>
          {instance_count(@instances.result)} in this partition
        </:description>
        <:content :let={count}>
          <.empty_state
            :if={count == 0}
            title="No resident instances"
            description="Instances appear here after the host starts them in this partition."
          />
          <.data_table
            :if={count > 0}
            id="studio-agent-rows"
            rows={@streams.instances}
            label="Resident instances"
          >
            <:col :let={id} label="Instance ID" row_header>
              <.link
                class="studio-instance-link"
                href={Mount.agent_path(@studio_path, id, @studio_scope)}
              >
                {id}
              </.link>
            </:col>
            <:col label="Residency">
              <.badge variant={:success}><.status_dot status={:online} /> Resident</.badge>
            </:col>
          </.data_table>
        </:content>
      </.read_panel>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id="studio-agent-instance" class="studio-agent-page">
      <nav aria-label="Agent breadcrumb">
        <.link
          class="studio-instance-link"
          href={Mount.path(@studio_path, "/agents", @studio_scope)}
        >
          <span aria-hidden="true">←</span> All agents
        </.link>
      </nav>

      <.page_header
        title={@instance_id}
        subtitle="Agent instance"
      >
        <:actions>
          <.link
            id="studio-turn-history-link"
            class="studio-button studio-button-secondary studio-button-md"
            href={Mount.turns_path(@studio_path, @instance_id, @studio_scope)}
          >
            Turn history
          </.link>
          <.link
            :if={@studio_definition_path}
            id="studio-definition-link"
            class="studio-button studio-button-secondary studio-button-md"
            href={@studio_definition_path}
          >
            Definition mockup
          </.link>
          <.button
            id="studio-refresh-instance"
            variant={:secondary}
            phx-click="reload"
            disabled={@status.loading || @snapshot.loading || (@signal_turn && @signal_turn.loading)}
          >
            Refresh
          </.button>
        </:actions>
      </.page_header>

      <div class="studio-instance-panels">
        <.read_panel id="studio-agent-status" title="Runtime status" panel="status" result={@status}>
          <:content :let={status}>
            <.runtime_status status={status} />
          </:content>
        </.read_panel>

        <.read_panel
          id="studio-agent-snapshot"
          title="Committed snapshot"
          panel="snapshot"
          result={@snapshot}
        >
          <:content :let={snapshot}>
            <.committed_snapshot snapshot={snapshot} />
          </:content>
        </.read_panel>
      </div>

      <SignalComponents.controls
        :if={@snapshot.ok? && @snapshot.result.signal_buttons != []}
        buttons={@snapshot.result.signal_buttons}
        busy={@signal_turn && @signal_turn.loading}
      />
      <SignalComponents.turn_result :if={@signal_turn} result={@signal_turn} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :panel, :string, required: true
  attr :result, AsyncResult, required: true
  slot :description
  slot :content, required: true

  defp read_panel(assigns) do
    ~H"""
    <.card id={@id} role="region" aria-labelledby={@id <> "-title"}>
      <div class="studio-card-header">
        <div>
          <h2 id={@id <> "-title"}>{@title}</h2>
          <p :if={@description != []}>{render_slot(@description)}</p>
        </div>
      </div>
      <.async_result :let={result} assign={@result}>
        <:loading>
          <p class="studio-read-loading" role="status">
            <span aria-hidden="true"></span> Loading {String.downcase(@title)}…
          </p>
        </:loading>
        <:failed :let={reason}>
          <.notice title={@title <> " unavailable"} tone={:warning}>
            <span role="status">{failure_message(reason)}</span>
            <:actions :if={reason != :not_configured}>
              <.button
                id={@id <> "-retry"}
                variant={:secondary}
                size={:sm}
                phx-click="reload"
                phx-value-panel={@panel}
              >
                Retry <span class="studio-sr-only">{String.downcase(@title)}</span>
              </.button>
            </:actions>
          </.notice>
        </:failed>
        {render_slot(@content, result)}
      </.async_result>
    </.card>
    """
  end

  attr :status, :map, required: true

  defp runtime_status(assigns) do
    ~H"""
    <dl class="studio-agent-facts">
      <div>
        <dt>Work state</dt>
        <dd>
          <.badge variant={work_tone(@status.work_state)}>{label(@status.work_state)}</.badge>
        </dd>
      </div>
      <div>
        <dt>Residency</dt><dd>{label(@status.residency)}</dd>
      </div>
      <div>
        <dt>Ready</dt><dd>{if @status.ready?, do: "Yes", else: "No"}</dd>
      </div>
      <div>
        <dt>Durability</dt><dd>{label(@status.durability)}</dd>
      </div>
      <div>
        <dt>Queue depth</dt><dd>{@status.queue_depth}</dd>
      </div>
      <div>
        <dt>Namespace</dt><dd><code>{@status.namespace}</code></dd>
      </div>
      <div :if={@status.activation_id}>
        <dt>Activation ID</dt><dd><code>{@status.activation_id}</code></dd>
      </div>
      <div :if={@status.active_turn_id}>
        <dt>Active turn ID</dt><dd><code>{@status.active_turn_id}</code></dd>
      </div>
    </dl>
    """
  end

  attr :snapshot, :map, required: true

  defp committed_snapshot(assigns) do
    ~H"""
    <div class="studio-agent-definition">
      <h3>{@snapshot.name}</h3>
      <p :if={@snapshot.description}>{@snapshot.description}</p>
    </div>
    <dl class="studio-agent-facts">
      <div :if={@snapshot.module}>
        <dt>Definition module</dt><dd><code>{inspect(@snapshot.module)}</code></dd>
      </div>
      <div>
        <dt>Definition version</dt><dd>{@snapshot.version}</dd>
      </div>
      <div>
        <dt>Agent revision</dt><dd>{@snapshot.revision}</dd>
      </div>
      <div :if={@snapshot.persistence_revision}>
        <dt>Persistence revision</dt><dd>{@snapshot.persistence_revision}</dd>
      </div>
      <div>
        <dt>State fields</dt><dd>{@snapshot.field_count}</dd>
      </div>
      <div :if={@snapshot.activation_id}>
        <dt>Activation ID</dt><dd><code>{@snapshot.activation_id}</code></dd>
      </div>
    </dl>
    """
  end

  defp instance_dom_id(id), do: "studio-instance-" <> Base.url_encode64(id, padding: false)
  defp instance_count(1), do: "1 instance"
  defp instance_count(count), do: "#{count} instances"
  defp label(value), do: value |> Atom.to_string() |> String.capitalize()
  defp work_tone(:running), do: :success
  defp work_tone(:waiting), do: :warning
  defp work_tone(:faulted), do: :error
  defp work_tone(_work_state), do: :neutral

  defp failure_message(:not_configured),
    do: "The host must connect a Jido runtime to this Studio mount."

  defp failure_message(:runtime_unavailable),
    do: "Studio could not reach the configured Jido runtime."

  defp failure_message(:not_found), do: "This instance is no longer resident in this partition."
  defp failure_message(:not_ready), do: "The instance is still starting."
  defp failure_message(:timeout), do: "The instance took too long to respond."
  defp failure_message(_reason), do: "Studio could not complete this read."
end
