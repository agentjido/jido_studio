defmodule JidoStudio.SettingsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components
  alias JidoStudio.Threads.Storage, as: ThreadsStorage

  @impl true
  def mount(_params, _session, socket) do
    observability = Application.get_env(:jido, :observability, [])

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:trace_buffer_size, Application.get_env(:jido_studio, :trace_buffer_size, 5000))
      |> assign(:trace_preview_limit, Application.get_env(:jido_studio, :trace_preview_limit, 30))
      |> assign(:trace_page_limit, Application.get_env(:jido_studio, :trace_page_limit, 300))
      |> assign(
        :trace_include_agent_debug,
        Application.get_env(:jido_studio, :trace_include_agent_debug, true)
      )
      |> assign(:trace_event_catalog_size, length(JidoStudio.TraceBuffer.event_catalog()))
      |> assign(:observability_debug_events, Keyword.get(observability, :debug_events, :off))
      |> assign(:observability_redact_sensitive, Keyword.get(observability, :redact_sensitive, false))
      |> assign(:pubsub, Application.get_env(:jido_studio, :pubsub, "Not configured"))
      |> assign(:thread_persistence, ThreadsStorage.persistence_enabled?())
      |> assign(:thread_storage_mode, ThreadsStorage.thread_storage_mode())
      |> assign(:thread_storage, inspect(Application.get_env(:jido_studio, :thread_storage, nil)))
      |> assign(:thread_retention_days, ThreadsStorage.thread_retention_days())
      |> assign(:persist_strategy_context, ThreadsStorage.persist_strategy_context_mode())
      |> assign(:auto_start_runtime, ThreadsStorage.auto_start_runtime?())

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Settings" subtitle="Studio configuration and runtime info" />

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.stat_card label="Studio Version" value={"v#{JidoStudio.version()}"} />
        <.stat_card label="Trace Buffer Size" value={to_string(@trace_buffer_size)} />
        <.stat_card label="Trace Event Catalog" value={to_string(@trace_event_catalog_size)} />
        <.stat_card label="Trace Page Limit" value={to_string(@trace_page_limit)} />
        <.stat_card label="Thread Persistence" value={if(@thread_persistence, do: "On", else: "Off")} />
        <.stat_card label="Thread Storage Mode" value={to_string(@thread_storage_mode)} />
      </div>

      <.card>
        <h3 class="text-sm font-medium text-js-text-muted mb-4 uppercase tracking-wider">
          Runtime Configuration
        </h3>
        <div class="space-y-3">
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">PubSub Module</span>
            <span class="text-sm text-js-text font-mono">{inspect(@pubsub)}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Trace Buffer Size</span>
            <span class="text-sm text-js-text font-mono">{@trace_buffer_size}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Trace Preview Limit</span>
            <span class="text-sm text-js-text font-mono">{@trace_preview_limit}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Trace Page Limit</span>
            <span class="text-sm text-js-text font-mono">{@trace_page_limit}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Include Agent Debug Stream</span>
            <span class="text-sm text-js-text font-mono">{to_string(@trace_include_agent_debug)}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Thread Persistence</span>
            <span class="text-sm text-js-text font-mono">{to_string(@thread_persistence)}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Thread Storage Mode</span>
            <span class="text-sm text-js-text font-mono">{to_string(@thread_storage_mode)}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Thread Storage</span>
            <span class="text-sm text-js-text font-mono">{@thread_storage}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Thread Retention (days)</span>
            <span class="text-sm text-js-text font-mono">{@thread_retention_days}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Persist Strategy Context</span>
            <span class="text-sm text-js-text font-mono">{to_string(@persist_strategy_context)}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Auto Start Runtime</span>
            <span class="text-sm text-js-text font-mono">{to_string(@auto_start_runtime)}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Jido Observe debug_events</span>
            <span class="text-sm text-js-text font-mono">{inspect(@observability_debug_events)}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Jido Observe redact_sensitive</span>
            <span class="text-sm text-js-text font-mono">
              {to_string(@observability_redact_sensitive)}
            </span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Tracked Event Prefixes</span>
            <span class="text-sm text-js-text font-mono">{@trace_event_catalog_size}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Elixir Version</span>
            <span class="text-sm text-js-text font-mono">{System.version()}</span>
          </div>
          <div class="flex justify-between items-center py-2">
            <span class="text-sm text-js-text-muted">OTP Version</span>
            <span class="text-sm text-js-text font-mono">
              {:erlang.system_info(:otp_release) |> to_string()}
            </span>
          </div>
        </div>
      </.card>
    </div>
    """
  end
end
