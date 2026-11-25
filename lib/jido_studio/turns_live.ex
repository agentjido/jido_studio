defmodule JidoStudio.TurnsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.{AgentReads, Mount}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Turn history", instance_id: nil)}
  end

  @impl true
  def handle_params(%{"agent_id" => segment} = params, _uri, socket) do
    id = Mount.decode_agent_id(segment)

    socket =
      if id == socket.assigns.instance_id do
        socket
      else
        socket |> assign(:instance_id, id) |> load_turns()
      end

    {:noreply, assign(socket, :selected_turn_id, params["turn"])}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load_turns(socket)}

  defp load_turns(socket) do
    %{studio_runtime: runtime, instance_id: id} = socket.assigns

    assign_async(
      socket,
      :turns,
      fn ->
        with {:ok, turns} <- AgentReads.turns(runtime, id), do: {:ok, %{turns: turns}}
      end,
      reset: true
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="studio-agent-turns" class="studio-agent-page">
      <nav aria-label="Agent breadcrumb">
        <.link
          class="studio-instance-link"
          href={Mount.agent_path(@studio_path, @instance_id, @studio_scope)}
        >
          <span aria-hidden="true">←</span> {@instance_id}
        </.link>
      </nav>

      <.page_header title="Turn history">
        <:actions>
          <.button
            id="studio-refresh-turns"
            variant={:secondary}
            phx-click="refresh"
            disabled={@turns.loading != nil}
          >
            Refresh
          </.button>
        </:actions>
      </.page_header>

      <.async_result :let={turns} assign={@turns}>
        <:loading>
          <p class="studio-read-loading" role="status">
            <span aria-hidden="true"></span> Loading turn history…
          </p>
        </:loading>
        <:failed :let={reason}>
          <.notice title="Turn history unavailable" tone={:warning}>
            <span role="status">{failure_message(reason)}</span>
          </.notice>
        </:failed>

        <div class={[@selected_turn_id && "studio-instance-panels"]}>
          <.card id="studio-turn-list" class="studio-agent-turn-list">
            <div class="studio-card-header">
              <div>
                <h2>Recent turns</h2>
                <p>Up to 50 settled turns for this running instance, from Studio's local buffer.</p>
              </div>
            </div>

            <.empty_state :if={turns == []} title="No turns recorded" />
            <.data_table :if={turns != []} id="studio-turn-rows" rows={turns} label="Recent turns">
              <:col :let={turn} label="Signal and turn ID" row_header>
                <.link
                  class="studio-instance-link studio-table-identity"
                  aria-current={if turn.id == @selected_turn_id, do: "true"}
                  patch={
                    Mount.turns_path(
                      @studio_path,
                      @instance_id,
                      Map.put(@studio_scope, "turn", turn.id)
                    )
                  }
                >
                  <span>{Map.get(turn, :signal_type, "Signal unavailable")}</span>
                  <code>{turn.id}</code>
                </.link>
              </:col>
              <:col :let={turn} label="Outcome">
                <.outcome turn={turn} />
              </:col>
              <:col :let={turn} label="Settled at">
                <.settled_at time={turn.settled_at} />
              </:col>
            </.data_table>
          </.card>

          <%= if @selected_turn_id do %>
            <%= if turn = Enum.find(turns, &(&1.id == @selected_turn_id)) do %>
              <.turn_details turn={turn} />
            <% else %>
              <.notice title="Selected turn unavailable" tone={:info}>
                This turn is outside the recent history for this instance.
              </.notice>
            <% end %>
          <% end %>
        </div>
      </.async_result>
    </div>
    """
  end

  attr :turn, :map, required: true

  defp turn_details(assigns) do
    ~H"""
    <.card id="studio-history-turn" role="region" aria-labelledby="studio-history-turn-title">
      <h2 id="studio-history-turn-title">Turn details</h2>
      <dl class="studio-agent-facts">
        <div>
          <dt>Turn ID</dt><dd><code>{@turn.id}</code></dd>
        </div>
        <div>
          <dt>Outcome</dt><dd><.outcome turn={@turn} /></dd>
        </div>
        <div>
          <dt>Settled at</dt><dd><.settled_at time={@turn.settled_at} /></dd>
        </div>
        <div>
          <dt>Stage</dt><dd>{label(@turn[:stage])}</dd>
        </div>
        <div>
          <dt>State committed</dt><dd>{commit_label(@turn[:committed?])}</dd>
        </div>
        <div>
          <dt>Signal type</dt><dd><code>{@turn[:signal_type] || "Unavailable"}</code></dd>
        </div>
        <div>
          <dt>Signal ID</dt><dd><code>{@turn[:signal_id] || "Unavailable"}</code></dd>
        </div>
        <div>
          <dt>Trace ID</dt><dd><code>{@turn[:trace_id] || "Unavailable"}</code></dd>
        </div>
        <div>
          <dt>Turn span ID</dt><dd><code>{@turn[:span_id] || "Unavailable"}</code></dd>
        </div>
      </dl>
    </.card>
    """
  end

  attr :turn, :map, required: true

  defp outcome(assigns) do
    {label, tone} = outcome_label(assigns.turn)
    assigns = assign(assigns, label: label, tone: tone)

    ~H"""
    <.badge variant={@tone}>{@label}</.badge>
    """
  end

  attr :time, DateTime, required: true

  defp settled_at(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@time)}>{Calendar.strftime(@time, "%b %d, %H:%M:%S UTC")}</time>
    """
  end

  defp outcome_label(%{status: :ok, committed?: true}), do: {"Committed", :success}
  defp outcome_label(%{status: :ok}), do: {"Succeeded", :success}
  defp outcome_label(%{status: :error}), do: {"Failed", :error}
  defp outcome_label(turn), do: {label(turn[:status]), :neutral}

  defp commit_label(true), do: "Yes"
  defp commit_label(false), do: "No"
  defp commit_label(nil), do: "Unavailable"

  defp label(atom) when is_atom(atom) and not is_nil(atom) do
    atom |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp label(_value), do: "Unavailable"

  defp failure_message(:not_configured),
    do: "The host must connect a Jido runtime to this Studio mount."

  defp failure_message(:runtime_unavailable),
    do: "Studio could not reach the configured Jido runtime."

  defp failure_message(:not_found), do: "This instance is no longer resident in this partition."
  defp failure_message(_reason), do: "Studio could not load the recent turns."
end
