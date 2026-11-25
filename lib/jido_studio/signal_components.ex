defmodule JidoStudio.SignalComponents do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components

  alias Phoenix.LiveView.AsyncResult

  attr :buttons, :list, required: true
  attr :busy, :boolean, default: false

  def controls(assigns) do
    ~H"""
    <.card id="studio-agent-signal-actions">
      <div class="studio-card-header">
        <h2>Signals</h2>
      </div>
      <div :for={button <- @buttons} class="studio-signal-action">
        <div class="studio-actions">
          <.button phx-click="send_signal" phx-value-type={button.type} disabled={@busy}>
            {button.label}
          </.button>
          <code>{button.type}</code>
        </div>
        <details class="studio-signal-schema">
          <summary>Signal payload</summary>
          <dl class="studio-agent-facts">
            <div :for={{field, schema} <- Map.get(button.schema, :properties, %{})}>
              <dt><code>{field}</code></dt>
              <dd>
                {Map.get(schema, :type)}
                <span :if={Map.has_key?(schema, :default)}>
                  · Default {inspect(schema.default)}
                </span>
              </dd>
            </div>
          </dl>
          <pre>{inspect(button.payload, pretty: true)}</pre>
        </details>
      </div>
    </.card>
    """
  end

  attr :result, AsyncResult, required: true

  def turn_result(assigns) do
    ~H"""
    <.async_result :let={turn} assign={@result}>
      <:loading>
        <.card id="studio-agent-turn">
          <h2>Turn</h2>
          <p class="studio-read-loading" role="status">
            <span aria-hidden="true"></span> Waiting for Jido…
          </p>
        </.card>
      </:loading>
      <:failed :let={reason}>
        <.notice title="Turn result unavailable" tone={:warning}>
          <span role="status">{failure_message(reason)}</span>
        </.notice>
      </:failed>

      <div class="studio-instance-panels" aria-live="polite">
        <.card id="studio-agent-turn">
          <h2>Turn</h2>
          <dl class="studio-agent-facts">
            <div>
              <dt>Outcome</dt>
              <dd>
                <.badge variant={turn_tone(turn.status)}>{label(turn.status)}</.badge>
              </dd>
            </div>
            <div>
              <dt>Turn ID</dt><dd><code>{turn.id}</code></dd>
            </div>
            <div>
              <dt>Signal ID</dt><dd><code>{turn.signal_id}</code></dd>
            </div>
            <div>
              <dt>Signal type</dt><dd><code>{turn.signal_type}</code></dd>
            </div>
            <div>
              <dt>Agent revision</dt><dd>{turn.revision}</dd>
            </div>
            <div :if={turn.reply}>
              <dt>Reply type</dt><dd><code>{turn.reply.type}</code></dd>
            </div>
            <div :for={{field, value} <- reply_fields(turn.reply)}>
              <dt>{label(field)}</dt><dd>{inspect(value)}</dd>
            </div>
          </dl>
        </.card>
        <.card id="studio-agent-trace">
          <h2>Trace</h2>
          <dl class="studio-agent-facts">
            <div>
              <dt>Trace ID</dt><dd><code>{turn.trace_id}</code></dd>
            </div>
            <div :if={turn.events != []}>
              <dt>Turn span ID</dt><dd><code>{hd(turn.events).span_id}</code></dd>
            </div>
          </dl>
          <p :if={turn.events == []} class="studio-trace-empty">
            No matching telemetry events were captured.
          </p>
          <ol :if={turn.events != []} class="studio-trace-events" aria-label="Trace events">
            <li :for={event <- turn.events}>
              <span>
                <strong>{event_label(event.name)}</strong>
                <code :if={event.action}>{event.action}</code>
              </span>
              <span :if={event.duration}>{milliseconds(event.duration)} ms</span>
            </li>
          </ol>
        </.card>
      </div>
    </.async_result>
    """
  end

  defp reply_fields(nil), do: []
  defp reply_fields(reply), do: Enum.sort(reply.data)

  defp label(atom),
    do: atom |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp turn_tone(:committed), do: :success
  defp turn_tone(:waiting), do: :info
  defp turn_tone(_status), do: :error

  defp event_label([:jido, :agent_server, :turn, :start]), do: "Turn started"
  defp event_label([:jido, :action, :start]), do: "Action started"
  defp event_label([:jido, :action, :stop]), do: "Action finished"
  defp event_label([:jido, :action, :exception]), do: "Action raised an exception"
  defp event_label([:jido, :agent_server, :commit]), do: "State committed"
  defp event_label([:jido, :agent_server, :turn, :stop]), do: "Turn finished"
  defp event_label([:jido, :agent_server, :turn, :settled]), do: "Turn settled"

  defp milliseconds(duration) do
    (System.convert_time_unit(duration, :native, :microsecond) / 1_000)
    |> :erlang.float_to_binary(decimals: 2)
  end

  defp failure_message(:signal_unavailable),
    do: "The instance cannot accept this signal right now."

  defp failure_message(:turn_rejected), do: "Jido rejected the signal before it accepted a turn."

  defp failure_message(_reason),
    do: "Studio did not receive a turn result. Check the instance before you send again."
end
