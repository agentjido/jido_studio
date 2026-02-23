defmodule JidoStudio.SettingsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components
  import JidoStudio.Setup.Components

  alias JidoStudio.GuidedTour
  alias JidoStudio.Setup
  alias JidoStudio.Setup.Helpers
  alias JidoStudio.Setup.Profiles
  alias JidoStudio.Threads.Storage, as: ThreadsStorage

  @impl true
  def mount(_params, _session, socket) do
    observability = Application.get_env(:jido, :observability, [])
    storage_info = Helpers.thread_storage_details(socket.assigns[:jido_instance])

    setup_assistant =
      Setup.build(
        scope: socket.assigns[:cluster_scope],
        jido_instance: socket.assigns[:jido_instance],
        prefix: socket.assigns[:prefix],
        runtime_key: socket.assigns[:runtime_key],
        node_param: socket.assigns[:cluster_node_param]
      )

    selected_profile_key = setup_assistant.active_profile_key
    setup_profile = Profiles.find_profile(selected_profile_key)

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:trace_buffer_size, Application.get_env(:jido_studio, :trace_buffer_size, 5000))
      |> assign(
        :trace_preview_limit,
        Application.get_env(:jido_studio, :trace_preview_limit, 200)
      )
      |> assign(:trace_page_limit, Application.get_env(:jido_studio, :trace_page_limit, 300))
      |> assign(
        :trace_include_agent_debug,
        Application.get_env(:jido_studio, :trace_include_agent_debug, true)
      )
      |> assign(:trace_event_catalog_size, length(JidoStudio.TraceBuffer.event_catalog()))
      |> assign(:observability_debug_events, Keyword.get(observability, :debug_events, :off))
      |> assign(
        :observability_redact_sensitive,
        Keyword.get(observability, :redact_sensitive, false)
      )
      |> assign(:pubsub, Application.get_env(:jido_studio, :pubsub, "Not configured"))
      |> assign(:thread_persistence, ThreadsStorage.persistence_enabled?())
      |> assign(:thread_storage_mode, ThreadsStorage.thread_storage_mode())
      |> assign(:thread_storage, inspect(Application.get_env(:jido_studio, :thread_storage, nil)))
      |> assign(:thread_storage_adapter, storage_info.adapter)
      |> assign(:thread_storage_path, storage_info.path)
      |> assign(:thread_retention_days, ThreadsStorage.thread_retention_days())
      |> assign(:persist_strategy_context, ThreadsStorage.persist_strategy_context_mode())
      |> assign(:auto_start_runtime, ThreadsStorage.auto_start_runtime?())
      |> assign(:live_ops_enabled, JidoStudio.LiveOps.enabled?())
      |> assign(:live_ops_presence, JidoStudio.LiveOps.presence_available?())
      |> assign(:live_ops_scope_keys, JidoStudio.LiveOps.scope_keys())
      |> assign(:trace_hide_internal_default, JidoStudio.TraceFilter.hide_internal_default?())
      |> assign(:trace_max_span_rows, JidoStudio.TraceFilter.max_span_rows())
      |> assign(:evals_enabled, JidoStudio.Evals.enabled?())
      |> assign(:persistence_adapter, inspect(JidoStudio.Persistence.adapter()))
      |> assign(
        :persistence_opts,
        JidoStudio.Persistence.resolve_adapter()
        |> case do
          {:ok, {_adapter, opts}} -> inspect(opts)
          _ -> "[]"
        end
      )
      |> assign(:setup_assistant, setup_assistant)
      |> assign(:setup_profile, setup_profile)
      |> assign(:selected_setup_profile, selected_profile_key)
      |> assign(:setup_check_statuses, Setup.check_statuses(setup_assistant))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, refresh_setup(socket)}
  end

  @impl true
  def handle_event("retest_setup", _params, socket) do
    {:noreply,
     socket
     |> refresh_setup()
     |> put_flash(:info, "Setup checks refreshed.")}
  end

  @impl true
  def handle_event("select_setup_profile", %{"value" => profile_key}, socket) do
    profile =
      Helpers.select_profile(
        profile_key,
        runtime: socket.assigns[:runtime_key],
        node: socket.assigns[:cluster_node_param],
        source: "settings"
      )

    {:noreply,
     socket
     |> assign(:selected_setup_profile, profile.key)
     |> assign(:setup_profile, profile)}
  end

  @impl true
  def handle_event("tour_metric", params, socket) do
    {:noreply, GuidedTour.track_metric(socket, params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Settings" subtitle="How is Studio configured for this runtime?">
        <:actions>
          <.badge variant={:default}>runtime:{@runtime_key || "default"}</.badge>
          <.badge variant={:info}>node:{@cluster_node_param || "all"}</.badge>
        </:actions>
      </.page_header>

      <.tour_metric_bridge />

      <.card class="py-3">
        <p class="text-xs text-js-text-muted">
          What this page is for: verify setup state and runtime configuration before debugging or incident response.
        </p>
      </.card>

      <.card data-tour-id="settings-setup-assistant">
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2 class="text-sm font-semibold text-js-text">Setup Assistant</h2>
            <p class="mt-1 text-xs text-js-text-muted">
              Re-test setup status and profile guidance without leaving Settings.
            </p>
          </div>
          <div class="flex items-center gap-2">
            <.badge variant={if(@setup_assistant.core_ready?, do: :success, else: :warning)}>
              {if(@setup_assistant.core_ready?, do: "Core Ready", else: "Needs Setup")}
            </.badge>
            <button
              type="button"
              phx-click="retest_setup"
              class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Re-test
            </button>
          </div>
        </div>

        <div class="mt-3 flex flex-wrap items-center gap-2">
          <.badge variant={:default}>
            Recommended Improvements {length(@setup_assistant.recommended_improvements)}
          </.badge>
          <.badge variant={:info}>
            Active Profile: {Profiles.find_profile(@setup_assistant.active_profile_key).label}
          </.badge>
        </div>

        <.checks_list checks={@setup_assistant.checks} />

        <.profile_guidance
          setup_assistant={@setup_assistant}
          setup_profile={@setup_profile}
          heading="Setup Profile Guidance"
        />
      </.card>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.stat_card label="Studio Version" value={"v#{JidoStudio.version()}"} />
        <.stat_card label="Trace Buffer Size" value={to_string(@trace_buffer_size)} />
        <.stat_card label="Trace Event Catalog" value={to_string(@trace_event_catalog_size)} />
        <.stat_card label="Trace Page Limit" value={to_string(@trace_page_limit)} />
        <.stat_card label="Thread Persistence" value={if(@thread_persistence, do: "On", else: "Off")} />
        <.stat_card label="Thread Storage Mode" value={to_string(@thread_storage_mode)} />
        <.stat_card label="Thread Storage Adapter" value={@thread_storage_adapter} />
        <.stat_card label="Persistence Adapter" value={@persistence_adapter} />
        <.stat_card label="Live Ops" value={if(@live_ops_enabled, do: "On", else: "Off")} />
        <.stat_card label="Evals" value={if(@evals_enabled, do: "On", else: "Off")} />
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
            <span class="text-sm text-js-text-muted">Trace Hide Internal Default</span>
            <span class="text-sm text-js-text font-mono">
              {to_string(@trace_hide_internal_default)}
            </span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Trace Max Span Rows</span>
            <span class="text-sm text-js-text font-mono">{@trace_max_span_rows}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Include Agent Debug Stream</span>
            <span class="text-sm text-js-text font-mono">
              {to_string(@trace_include_agent_debug)}
            </span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Live Ops Enabled</span>
            <span class="text-sm text-js-text font-mono">{to_string(@live_ops_enabled)}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Presence Available</span>
            <span class="text-sm text-js-text font-mono">{to_string(@live_ops_presence)}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Live Ops Scope Keys</span>
            <span class="text-sm text-js-text font-mono">{inspect(@live_ops_scope_keys)}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Evals Enabled</span>
            <span class="text-sm text-js-text font-mono">{to_string(@evals_enabled)}</span>
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
            <span class="text-sm text-js-text-muted">Resolved Thread Storage Adapter</span>
            <span class="text-sm text-js-text font-mono">{@thread_storage_adapter}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Resolved Thread Storage Path</span>
            <span class="text-sm text-js-text font-mono">{@thread_storage_path}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Persistence Adapter</span>
            <span class="text-sm text-js-text font-mono">{@persistence_adapter}</span>
          </div>
          <div class="flex justify-between items-center py-2 border-b border-js-border">
            <span class="text-sm text-js-text-muted">Persistence Adapter Opts</span>
            <span class="text-sm text-js-text font-mono">{@persistence_opts}</span>
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

  defp refresh_setup(socket) do
    setup_assistant =
      Setup.build(
        scope: socket.assigns[:cluster_scope],
        jido_instance: socket.assigns[:jido_instance],
        prefix: socket.assigns[:prefix],
        runtime_key: socket.assigns[:runtime_key],
        node_param: socket.assigns[:cluster_node_param]
      )

    selected_key =
      socket.assigns[:selected_setup_profile]
      |> Helpers.normalize_profile_key(setup_assistant.active_profile_key)

    setup_assistant = Map.put(setup_assistant, :active_profile_key, selected_key)
    setup_profile = Profiles.find_profile(selected_key)
    statuses = Setup.check_statuses(setup_assistant)

    socket
    |> maybe_emit_setup_telemetry(setup_assistant)
    |> assign(:setup_assistant, setup_assistant)
    |> assign(:setup_profile, setup_profile)
    |> assign(:setup_check_statuses, statuses)
  end

  defp maybe_emit_setup_telemetry(socket, setup_assistant) do
    previous = socket.assigns[:setup_check_statuses] || %{}

    :ok =
      Helpers.emit_step_telemetry(
        previous,
        setup_assistant.checks,
        runtime: socket.assigns[:runtime_key],
        node: socket.assigns[:cluster_node_param],
        source: "settings"
      )

    socket
  end
end
