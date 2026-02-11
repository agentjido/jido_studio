defmodule JidoStudio.Components.ChatComponents do
  @moduledoc false
  use Phoenix.Component

  alias Phoenix.HTML

  attr :threads, :list, required: true
  attr :active_thread_id, :string, default: nil
  attr :messages_by_thread, :map, required: true
  attr :chat_pending?, :boolean, default: false
  attr :class, :string, default: nil

  def chat_threads_rail(assigns) do
    ~H"""
    <section class={[
      "bg-js-card border border-js-border rounded-lg overflow-hidden flex flex-col min-h-0",
      @class
    ]}>
      <div class="flex items-center justify-between px-3 py-2 border-b border-js-border">
        <h3 class="text-sm font-medium text-js-text">Threads</h3>
        <button
          type="button"
          phx-click="new_thread"
          disabled={@chat_pending?}
          class="inline-flex items-center gap-1 rounded-md bg-js-primary px-2.5 py-1 text-xs font-medium text-js-primary-foreground hover:brightness-110 disabled:opacity-50 disabled:pointer-events-none"
        >
          <Lucideicons.plus class="w-3.5 h-3.5" /> New Chat
        </button>
      </div>

      <div class="p-2 space-y-1 flex-1 min-h-0 overflow-y-auto js-scroll js-scroll-single-gutter">
        <%= if @threads == [] do %>
          <div class="rounded-md border border-dashed border-js-border p-3 text-xs text-js-text-subtle">
            No threads yet.
          </div>
        <% else %>
          <button
            :for={thread <- @threads}
            type="button"
            phx-click="select_thread"
            phx-value-id={thread.id}
            class={[
              "w-full text-left rounded-md border px-2.5 py-2 transition-colors",
              if(thread.id == @active_thread_id,
                do: "border-js-primary bg-js-bg-elevated text-js-text",
                else:
                  "border-js-border/40 text-js-text-muted hover:border-js-border hover:text-js-text"
              )
            ]}
          >
            <div class="flex items-center justify-between gap-2">
              <div class="text-sm font-medium truncate">{thread_display_title(thread)}</div>
              <span
                :if={show_thread_short_id?(thread)}
                class="text-[11px] text-js-text-subtle whitespace-nowrap"
              >
                {thread_short_id(Map.get(thread, :id))}
              </span>
            </div>
            <div class="mt-0.5 text-xs text-js-text-subtle flex items-center justify-between gap-2">
              <span class="truncate">{thread_updated_label(thread)}</span>
              <span class="whitespace-nowrap">
                {Map.get(thread, :message_count, length(Map.get(@messages_by_thread, thread.id, [])))} messages
              </span>
            </div>
          </button>
        <% end %>
      </div>
    </section>
    """
  end

  attr :thread_name, :string, required: true
  attr :active_messages, :list, required: true
  attr :draft_message, :string, required: true
  attr :chat_pending?, :boolean, default: false
  attr :chat_enabled?, :boolean, default: true
  attr :placeholder, :string, default: "Enter your message..."
  attr :empty_title, :string, default: "How can I help you today?"
  attr :empty_description, :string, default: "Start a message to begin."
  attr :model_label, :string, default: nil
  attr :provider_options, :list, default: []
  attr :provider_value, :string, default: "anthropic"
  attr :model_options, :list, default: []
  attr :model_value, :string, default: nil
  attr :traces_path, :string, default: nil
  attr :class, :string, default: nil

  def chat_conversation_panel(assigns) do
    ~H"""
    <section class={[
      "bg-js-card border border-js-border rounded-lg overflow-hidden flex flex-col min-h-0",
      @class
    ]}>
      <div class="px-3 py-2 border-b border-js-border flex items-center justify-between gap-2">
        <h3 class="text-sm font-medium text-js-text truncate">{@thread_name}</h3>
        <span
          :if={@chat_pending?}
          class="inline-flex items-center rounded-full bg-js-info/15 px-2 py-0.5 text-xs text-js-info"
        >
          Waiting
        </span>
      </div>

      <div class="px-3 py-3 bg-js-bg overflow-y-auto js-scroll flex-1 min-h-0">
        <%= if @active_messages == [] do %>
          <div class="h-full min-h-[18rem] flex items-center justify-center text-center">
            <div>
              <div class="w-10 h-10 rounded-full bg-js-bg-elevated mx-auto mb-3 flex items-center justify-center">
                <Lucideicons.message_circle class="w-5 h-5 text-js-text-muted" />
              </div>
              <p class="text-base font-medium text-js-text">{@empty_title}</p>
              <p class="text-sm text-js-text-muted mt-1 max-w-sm">{@empty_description}</p>
            </div>
          </div>
        <% else %>
          <div class="space-y-2.5">
            <div
              :for={msg <- @active_messages}
              class={["flex", if(msg.role == :user, do: "justify-end", else: "justify-start")]}
            >
              <div class={[
                "max-w-2xl rounded-lg border px-3 py-2 text-sm",
                message_bubble_classes(msg)
              ]}>
                <div
                  :if={is_list(msg[:tool_events]) and msg[:tool_events] != []}
                  class="space-y-2 mb-2"
                >
                  <.tool_event_card
                    :for={tool_event <- msg.tool_events}
                    tool_event={tool_event}
                    fallback_traces_path={@traces_path}
                  />
                </div>
                <div class="js-chat-markdown break-words">{render_markdown(msg.content)}</div>
                <p
                  :if={msg[:state] in [:pending, :error]}
                  class="mt-1 text-[11px] uppercase tracking-wider"
                >
                  {message_state_label(msg[:state])}
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <div class="border-t border-js-border p-3 bg-js-card">
        <form
          phx-change="update_draft"
          phx-submit="send_message"
          class="js-composer-shell flex flex-col gap-2 rounded-lg border border-js-border bg-js-bg-surface p-2"
        >
          <div class="js-composer-input-wrap rounded-md border border-js-border bg-js-bg-elevated px-2 py-1">
            <textarea
              name="message"
              rows="1"
              data-js-chat-input
              data-max-rows="8"
              disabled={not @chat_enabled? or @chat_pending?}
              class="js-composer-input block w-full border-0 bg-transparent p-0 text-sm leading-6 text-js-text outline-none"
              style="resize: none;"
              placeholder={@placeholder}
            ><%= @draft_message %></textarea>
          </div>

          <div class="js-composer-controls flex flex-wrap items-center gap-2">
            <div class="js-composer-controls-left inline-flex flex-wrap items-center gap-1.5">
              <label class="js-composer-select-wrap inline-flex h-10 items-center gap-1.5 rounded-md border border-js-border bg-js-bg-elevated px-2">
                <Lucideicons.bot class="w-3.5 h-3.5 text-js-text-subtle shrink-0" />
                <select
                  name="provider"
                  value={@provider_value}
                  disabled={@chat_pending?}
                  class="js-composer-select border-0 bg-transparent text-sm text-js-text outline-none"
                >
                  <option :for={provider <- @provider_options} value={provider}>
                    {provider_label(provider)}
                  </option>
                </select>
              </label>

              <label class="js-composer-select-wrap js-composer-select-wrap-model inline-flex h-10 min-w-[96px] items-center rounded-md border border-js-border bg-js-bg-elevated px-2">
                <select
                  name="model"
                  value={@model_value}
                  disabled={@chat_pending?}
                  class="js-composer-select w-full border-0 bg-transparent text-sm text-js-text outline-none"
                >
                  <option
                    :for={model <- model_select_options(@model_options, @model_value)}
                    value={model}
                  >
                    {model}
                  </option>
                </select>
              </label>

              <span class="js-composer-ui-pill inline-flex items-center rounded-full px-2 py-1 text-xs">
                UI-only
              </span>
            </div>

            <div class="js-composer-meta min-w-[11rem] flex-1 truncate text-xs text-js-text-muted">
              <span :if={@model_label}>Strategy: {@model_label}</span>
              <span :if={not @chat_enabled?}>Chat unavailable for this instance.</span>
              <span :if={@chat_enabled? and @chat_pending?}>Waiting for response...</span>
              <span :if={@chat_enabled? and not @chat_pending?}>Cmd/Ctrl+Enter to send</span>
            </div>

            <button
              type="submit"
              aria-label="Send message"
              disabled={not @chat_enabled? or @chat_pending?}
              class="js-composer-send inline-flex h-10 w-10 items-center justify-center rounded-md border border-js-primary bg-js-primary text-js-primary-foreground disabled:pointer-events-none disabled:opacity-50"
            >
              <Lucideicons.arrow_up class="w-4 h-4" />
            </button>
          </div>
        </form>
      </div>
    </section>
    """
  end

  attr :tool_event, :map, required: true
  attr :fallback_traces_path, :string, default: nil

  defp tool_event_card(assigns) do
    tool_event = assigns.tool_event || %{}
    traces_path = Map.get(tool_event, :traces_path) || assigns.fallback_traces_path
    call_id = Map.get(tool_event, :call_id) || Map.get(tool_event, :id)

    assigns =
      assigns
      |> assign(:tool_name, Map.get(tool_event, :name, "tool"))
      |> assign(:status, tool_event_status(tool_event))
      |> assign(:duration_label, tool_duration_label(Map.get(tool_event, :duration_ms)))
      |> assign(:args_text, pretty_data(Map.get(tool_event, :arguments, %{})))
      |> assign(:result_text, pretty_data(Map.get(tool_event, :result)))
      |> assign(:has_result?, has_tool_result?(Map.get(tool_event, :result)))
      |> assign(:traces_path, traces_path)
      |> assign(:call_id, call_id)
      |> assign(:tool_dom_id, tool_card_dom_id(call_id, Map.get(tool_event, :name)))

    ~H"""
    <details id={@tool_dom_id} open class="rounded-md border border-js-border/70 bg-js-bg px-2.5 py-2">
      <summary class="flex cursor-pointer list-none items-center justify-between gap-2">
        <span class="inline-flex items-center gap-1.5 text-xs text-js-text">
          <Lucideicons.wrench class="w-3.5 h-3.5 text-js-info" />
          <span class="font-medium">{@tool_name}</span>
        </span>
        <span class="inline-flex items-center gap-1.5">
          <span class={tool_status_classes(@status)}>{@status}</span>
          <span :if={@duration_label} class="text-[11px] text-js-text-subtle">{@duration_label}</span>
        </span>
      </summary>

      <div class="mt-2 space-y-2">
        <div>
          <p class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-1">Tool Arguments</p>
          <pre class="rounded-md border border-js-border bg-js-bg-elevated p-2 text-[11px] text-js-text-muted overflow-x-auto"><%= @args_text %></pre>
        </div>

        <div>
          <p class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-1">Tool Result</p>
          <%= if @has_result? do %>
            <pre class="rounded-md border border-js-border bg-js-bg-elevated p-2 text-[11px] text-js-text-muted overflow-x-auto"><%= @result_text %></pre>
          <% else %>
            <p class="text-xs text-js-text-subtle">Waiting for tool result...</p>
          <% end %>
        </div>

        <div :if={@traces_path} class="pt-1">
          <.link
            navigate={tool_trace_link(@traces_path, @call_id)}
            class="inline-flex items-center gap-1 text-xs text-js-info hover:text-js-text transition-colors"
          >
            <Lucideicons.activity class="w-3.5 h-3.5" /> View trace
          </.link>
        </div>
      </div>
    </details>
    """
  end

  defp message_bubble_classes(%{role: :user}) do
    "border-js-primary bg-js-primary text-js-primary-foreground"
  end

  defp message_bubble_classes(%{state: :error}) do
    "border-js-error/30 bg-js-error/15 text-js-error"
  end

  defp message_bubble_classes(%{state: :pending}) do
    "border-js-border border-dashed bg-js-bg-elevated text-js-text-muted"
  end

  defp message_bubble_classes(_msg) do
    "border-js-border bg-js-bg-elevated text-js-text"
  end

  defp message_state_label(:pending), do: "Pending"
  defp message_state_label(:error), do: "Error"
  defp message_state_label(_), do: ""

  defp tool_event_status(tool_event) do
    case Map.get(tool_event, :status) do
      :completed -> "Completed"
      :error -> "Error"
      :running -> "Running"
      value when is_binary(value) and value != "" -> String.capitalize(value)
      _ -> "Running"
    end
  end

  defp tool_status_variant("Completed"), do: :success
  defp tool_status_variant("Error"), do: :error
  defp tool_status_variant("Running"), do: :info
  defp tool_status_variant(_), do: :default

  defp tool_status_classes(status) do
    variant = tool_status_variant(status)

    base = "inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-medium"

    variant_class =
      case variant do
        :success -> "bg-js-success/15 text-js-success"
        :error -> "bg-js-error/15 text-js-error"
        :info -> "bg-js-info/15 text-js-info"
        _ -> "bg-js-muted text-js-text-subtle"
      end

    "#{base} #{variant_class}"
  end

  defp tool_duration_label(ms) when is_integer(ms) and ms >= 0, do: "#{ms}ms"
  defp tool_duration_label(_), do: nil

  defp has_tool_result?(nil), do: false
  defp has_tool_result?(value) when is_binary(value), do: String.trim(value) != ""
  defp has_tool_result?(_), do: true

  defp pretty_data(nil), do: "(none)"

  defp pretty_data(value) do
    value
    |> maybe_decode_json()
    |> encode_pretty()
  end

  defp maybe_decode_json(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      value
    else
      case Jason.decode(trimmed) do
        {:ok, decoded} -> decoded
        _ -> value
      end
    end
  end

  defp maybe_decode_json(value), do: value

  defp encode_pretty(value) when is_map(value) or is_list(value) do
    case Jason.encode(value, pretty: true) do
      {:ok, json} -> json
      _ -> inspect(value, pretty: true, limit: :infinity)
    end
  end

  defp encode_pretty(value) when is_binary(value), do: value
  defp encode_pretty(value), do: inspect(value, pretty: true, limit: :infinity)

  defp tool_trace_link(base_path, nil), do: base_path

  defp tool_trace_link(base_path, call_id) do
    if String.contains?(base_path, "call_id=") do
      base_path
    else
      separator = if String.contains?(base_path, "?"), do: "&", else: "?"
      base_path <> separator <> URI.encode_query(%{"call_id" => call_id, "source" => "telemetry"})
    end
  end

  defp tool_card_dom_id(call_id, tool_name) do
    suffix =
      cond do
        is_binary(call_id) and String.trim(call_id) != "" ->
          call_id

        is_binary(tool_name) and String.trim(tool_name) != "" ->
          tool_name

        true ->
          "tool"
      end
      |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")

    "tool-event-#{suffix}"
  end

  defp thread_display_title(thread) do
    title = thread |> Map.get(:title, "") |> to_string() |> String.trim()

    cond do
      title == "" -> "Thread #{thread_short_id(Map.get(thread, :id))}"
      title == "New Chat" -> "Thread #{thread_short_id(Map.get(thread, :id))}"
      true -> title
    end
  end

  defp show_thread_short_id?(thread) do
    not String.starts_with?(thread_display_title(thread), "Thread ")
  end

  defp thread_short_id(id) when is_binary(id) do
    cleaned =
      id
      |> String.replace_prefix("thread_", "")
      |> String.replace(~r/[^a-zA-Z0-9]/, "")

    len = String.length(cleaned)

    cond do
      len == 0 -> "00000"
      len <= 5 -> cleaned
      true -> String.slice(cleaned, len - 5, 5)
    end
  end

  defp thread_short_id(_), do: "00000"

  defp thread_updated_label(thread) do
    case Map.get(thread, :updated_at) do
      timestamp when is_integer(timestamp) and timestamp > 0 ->
        case DateTime.from_unix(timestamp, :millisecond) do
          {:ok, datetime} -> Calendar.strftime(datetime, "%b %-d at %-I:%M:%S %p")
          _ -> "Just now"
        end

      _ ->
        "Just now"
    end
  end

  defp provider_label("anthropic"), do: "Anthropic"
  defp provider_label("openai"), do: "OpenAI"
  defp provider_label("groq"), do: "Groq"
  defp provider_label("ollama"), do: "Ollama"
  defp provider_label("custom"), do: "Custom"
  defp provider_label(other), do: other |> to_string() |> String.capitalize()

  defp model_select_options(options, model_value) do
    options = List.wrap(options)

    cond do
      is_binary(model_value) and String.trim(model_value) != "" and model_value not in options ->
        options ++ [model_value]

      true ->
        options
    end
  end

  defp render_markdown(content) when is_binary(content) do
    content = String.trim(content)

    if content == "" do
      HTML.raw("")
    else
      content
      |> markdown_to_html()
      |> HTML.raw()
    end
  end

  defp render_markdown(content), do: content |> to_string() |> render_markdown()

  defp markdown_to_html(markdown) do
    MDEx.to_html!(markdown,
      extension: [strikethrough: true, table: true, tasklist: true, autolink: true]
    )
  rescue
    _ ->
      escaped = markdown |> HTML.html_escape() |> HTML.safe_to_string()
      "<p>#{escaped}</p>"
  end
end
