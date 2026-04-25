defmodule JidoStudio.HomeLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components
  import JidoStudio.Setup.Components

  alias JidoStudio.AgentRegistry
  alias JidoStudio.Beginner
  alias JidoStudio.Cluster.Collect
  alias JidoStudio.GuidedTour
  alias JidoStudio.Live.HomeLive.State, as: HomeState
  alias JidoStudio.Naming
  alias JidoStudio.Observability.Incidents
  alias JidoStudio.PathSegments
  alias JidoStudio.ProductMetrics
  alias JidoStudio.Setup
  alias JidoStudio.Setup.Helpers
  alias JidoStudio.Setup.Profiles
  alias JidoStudio.ScopeQuery
  alias JidoStudio.Threads.Storage, as: ThreadsStorage
  alias JidoStudio.Tracing

  @refresh_ms 4_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Home")
      |> assign(:summary, %{})
      |> assign(:attention_items, [])
      |> assign(:top_agents, [])
      |> assign(:recent_activity, [])
      |> assign(:recent_failures, [])
      |> assign(:starter_agent, nil)
      |> assign(:starter_reason, nil)
      |> assign(:starter_launch_path, nil)
      |> assign(:starter_running?, false)
      |> assign(
        :setup_assistant,
        %{
          checks: [],
          core_ready?: false,
          recommended_improvements: [],
          active_profile_key: Profiles.default_profile_key(),
          profiles: Profiles.profiles()
        }
      )
      |> assign(:setup_profile, Profiles.find_profile(Profiles.default_profile_key()))
      |> assign(:selected_setup_profile, nil)
      |> assign(:setup_check_statuses, %{})
      |> assign(:next_step_links_metrics, nil)
      |> assign(:first_interaction_success_emitted?, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, refresh_home(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, refresh_home(socket)}
  end

  @impl true
  def handle_event("retest_setup", _params, socket) do
    {:noreply,
     socket
     |> refresh_home()
     |> put_flash(:info, "Setup checks refreshed.")}
  end

  @impl true
  def handle_event("select_setup_profile", %{"value" => profile_key}, socket) do
    profile =
      Helpers.select_profile(
        profile_key,
        runtime: socket.assigns[:runtime_key],
        node: socket.assigns[:cluster_node_param],
        source: "home"
      )

    {:noreply,
     socket
     |> assign(:selected_setup_profile, profile.key)
     |> assign(:setup_profile, profile)}
  end

  @impl true
  def handle_event("open_attention_item", %{"path" => path} = params, socket)
      when is_binary(path) do
    warning_kind = params["kind"] || "attention_item"

    :ok =
      ProductMetrics.triage_warning_opened(socket,
        source: "home_attention",
        warning_kind: warning_kind
      )

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_event("tour_metric", params, socket) do
    {:noreply, GuidedTour.track_metric(socket, params)}
  end

  @impl true
  def handle_event("open_starter_agent", %{"path" => path} = params, socket)
      when is_binary(path) do
    :ok =
      ProductMetrics.onboarding_starter_opened(socket,
        source: "home_starter_card",
        mode: normalize_starter_mode(params["mode"], "home_card"),
        starter_slug: normalize_optional_string(params["starter_slug"]),
        starter_module: normalize_optional_string(params["starter_module"])
      )

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6 space-y-4">
      <.page_header
        title="Home"
        subtitle="Are your agents healthy right now?"
        data-tour-id="home-health-summary"
      >
        <:actions>
          <.badge variant={:default}>
            runtime:{runtime_scope_label(@runtime_key, @jido_instance)}
          </.badge>
          <.badge variant={:info}>node:{@cluster_node_param || "all"}</.badge>
        </:actions>
      </.page_header>

      <.tour_metric_bridge />

      <.card class="py-3">
        <p class="text-xs text-js-text-muted">
          What this page is for: review fleet health, resolve attention items, and jump to the next action in one click.
        </p>
      </.card>

      <div
        data-js-home-setup
        data-js-home-setup-complete={to_string(@setup_assistant.core_ready?)}
        class="space-y-3"
      >
        <div data-js-home-setup-grid class="grid grid-cols-1 xl:grid-cols-2 gap-4">
          <.card data-tour-id="home-attention-list">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-semibold text-js-text">Attention Needed</h2>
              <.badge :if={@attention_items != []} variant={:warning}>
                {length(@attention_items)}
              </.badge>
            </div>

            <div :if={@attention_items == []} class="mt-4">
              <.empty_state
                title="No active alerts"
                description="No incident spikes or recent error-heavy traces were detected."
              />
            </div>

            <div :if={@attention_items != []} class="mt-3 space-y-2">
              <div
                :for={item <- @attention_items}
                class="rounded-md border border-js-border bg-js-bg-elevated px-3 py-2"
              >
                <div class="flex items-center justify-between gap-2">
                  <div class="text-xs text-js-text font-medium">{item.title}</div>
                  <button
                    :if={item[:path]}
                    type="button"
                    phx-click="open_attention_item"
                    phx-value-path={item.path}
                    phx-value-kind={item[:kind] || "attention_item"}
                    class="text-[11px] text-js-info hover:text-js-text"
                  >
                    Open
                  </button>
                </div>
                <p class="mt-1 text-xs text-js-text-muted">{item.description}</p>
              </div>
            </div>

            <div class="mt-4 flex flex-wrap gap-2">
              <.link
                navigate={page_path(@prefix, "/agents", @runtime_key, @cluster_node_param)}
                class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
              >
                Open Agents
              </.link>
              <.link
                navigate={page_path(@prefix, "/activity", @runtime_key, @cluster_node_param)}
                class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
              >
                Open Activity
              </.link>
              <.link
                navigate={page_path(@prefix, "/diagnostics", @runtime_key, @cluster_node_param)}
                class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
              >
                Open Diagnostics
              </.link>
            </div>
          </.card>

          <.card data-js-home-setup-card data-tour-id="home-setup-assistant" class="h-full">
            <div class="flex items-start justify-between gap-3">
              <div>
                <h2 class="text-sm font-semibold text-js-text">Setup Assistant</h2>
                <p class="mt-1 text-xs text-js-text-muted">
                  Validate runtime, persistence, realtime flow, and a smoke-check path.
                </p>
              </div>
              <div class="flex items-center gap-2">
                <.badge variant={if(@setup_assistant.core_ready?, do: :success, else: :warning)}>
                  {if(@setup_assistant.core_ready?, do: "Core Ready", else: "Needs Setup")}
                </.badge>
                <button
                  :if={@setup_assistant.core_ready?}
                  type="button"
                  data-js-home-setup-hide
                  class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                >
                  Hide
                </button>
              </div>
            </div>

            <div class="mt-3 flex flex-wrap items-center gap-2">
              <.badge variant={if(@setup_assistant.core_ready?, do: :success, else: :warning)}>
                {if(@setup_assistant.core_ready?, do: "Core Ready", else: "Core Setup Needed")}
              </.badge>
              <.badge variant={:default}>
                Recommended Improvements {length(@setup_assistant.recommended_improvements)}
              </.badge>
              <.badge variant={:info}>
                Active Profile: {Profiles.find_profile(@setup_assistant.active_profile_key).label}
              </.badge>
            </div>

            <div
              :if={@setup_assistant.recommended_improvements != []}
              class="mt-3 rounded-md border border-js-warning/40 bg-js-warning/10 px-3 py-2"
            >
              <p class="text-xs font-medium text-js-warning">Recommended Improvements</p>
              <p
                :for={improvement <- @setup_assistant.recommended_improvements}
                class="mt-1 text-[11px] text-js-warning"
              >
                {improvement.label}: {improvement.recommendation}
              </p>
            </div>

            <.checks_list checks={@setup_assistant.checks} />

            <.profile_guidance
              setup_assistant={@setup_assistant}
              setup_profile={@setup_profile}
              heading="Setup Profiles"
            />
          </.card>
        </div>

        <div
          data-js-home-setup-regressed
          class="hidden rounded-lg border border-js-warning/40 bg-js-warning/10 px-4 py-3"
        >
          <p class="text-xs text-js-warning">
            Setup status regressed since you hid the checklist. Review the updated actions below.
          </p>
        </div>

        <div
          data-js-home-setup-show
          class="hidden rounded-lg border border-js-border bg-js-card px-4 py-3 flex items-center justify-between gap-3"
        >
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <h2 class="text-sm font-semibold text-js-text">Setup Assistant</h2>
              <.badge variant={:success}>Core Ready</.badge>
            </div>
            <p class="mt-1 text-xs text-js-text-muted truncate">
              Setup checklist is hidden. Re-open it whenever you need to review setup health.
            </p>
          </div>
          <button
            type="button"
            data-js-home-setup-show-btn
            class="inline-flex items-center rounded-md border border-js-border px-2.5 py-1 text-[11px] text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated whitespace-nowrap"
          >
            Show Setup
          </button>
        </div>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <.stat_card label="Agents Online" value={to_string(@summary.online_agents || 0)} />
        <.stat_card label="Agents Available" value={to_string(@summary.available_agents || 0)} />
        <.stat_card label="Active Incidents" value={to_string(@summary.active_incidents || 0)} />
        <.stat_card label="Cluster Nodes" value={to_string(@summary.node_count || 1)} />
        <.stat_card
          label="Workspace Persistence"
          value={if(@summary.thread_persistence?, do: "On", else: "Off")}
        />
        <.stat_card
          label="Thread Storage"
          value={@summary.thread_storage_adapter || "n/a"}
        />
      </div>

      <div class="grid grid-cols-1 xl:grid-cols-2 gap-4 items-start">
        <.card>
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold text-js-text">Top Agents</h2>
            <span class="text-[11px] text-js-text-subtle">Click to play</span>
          </div>
          <div :if={@top_agents == []} class="mt-4">
            <.empty_state
              title="No active agents"
              description="Start an agent instance to see fleet rankings and activity."
            />
          </div>
          <div :if={@top_agents != []} class="mt-3 space-y-2">
            <.link
              :for={agent <- @top_agents}
              navigate={agent_launch_path(@prefix, agent, @runtime_key, @cluster_node_param)}
              class="group flex items-center justify-between rounded-md border border-js-border bg-js-bg-elevated px-3 py-2 hover:border-js-primary/50 hover:bg-js-bg-elevated/80 transition-colors"
            >
              <div class="min-w-0">
                <div class="text-xs text-js-text">{display_agent_name(agent)}</div>
                <div class="text-[11px] text-js-text-subtle font-mono truncate">
                  {agent_launch_hint(agent)}
                </div>
              </div>
              <div class="flex items-center gap-2">
                <.badge variant={:default}>{length(agent.running_instances || [])} running</.badge>
                <span class="text-[11px] text-js-info group-hover:text-js-text">
                  {if((agent.running_instances || []) == [], do: "Inspect", else: "Play")} →
                </span>
              </div>
            </.link>
          </div>
        </.card>

        <.card>
          <h2 class="text-sm font-semibold text-js-text">Recent Activity</h2>

          <div :if={@recent_activity == []} class="mt-4">
            <.empty_state
              title="No recent trace activity"
              description="Trace data appears here once agents execute actions or workflows."
            />
          </div>

          <div :if={@recent_activity != []} class="mt-3 divide-y divide-js-border">
            <div :for={item <- @recent_activity} class="py-2 flex items-center justify-between gap-3">
              <div class="min-w-0">
                <div class="text-xs text-js-text truncate">{item.title}</div>
                <div class="text-[11px] text-js-text-subtle font-mono truncate">
                  {item.subtitle}
                </div>
              </div>
              <div class="text-[11px] text-js-text-subtle font-mono whitespace-nowrap">
                {item.when}
              </div>
            </div>
          </div>
        </.card>
      </div>

      <div class="grid grid-cols-1 xl:grid-cols-2 gap-4 items-start">
        <div data-js-home-example class="space-y-2">
          <.card
            data-js-home-example-card
            data-tour-id="home-example-agent"
            class="border-js-info/35 bg-gradient-to-r from-js-info/12 via-js-card to-js-card p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="text-[11px] uppercase tracking-wider text-js-info">Example</p>
                <h2 class="mt-1 text-base font-semibold text-js-text">Starter Agent</h2>
                <p class="mt-1 text-xs text-js-text-muted max-w-2xl">
                  Start with one deterministic interaction path, then move into deeper diagnostics.
                </p>
              </div>

              <button
                type="button"
                data-js-home-example-hide
                class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
              >
                Hide
              </button>
            </div>

            <div class="mt-3 grid grid-cols-1 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-3">
              <div class="rounded-md border border-js-border/70 bg-js-bg-elevated/40 p-3">
                <p class="text-[11px] uppercase tracking-wide text-js-text-subtle">Example Status</p>
                <div class="mt-2 flex items-center gap-2">
                  <.badge variant={if @starter_running?, do: :success, else: :default}>
                    {if @starter_running?, do: "Running", else: "Available"}
                  </.badge>
                  <span class="text-xs text-js-text">{display_agent_name(@starter_agent)}</span>
                </div>
                <p class="mt-2 text-xs text-js-text-muted">
                  {starter_status_hint(@starter_running?, @starter_reason)}
                </p>
              </div>

              <div class="rounded-md border border-js-border/70 bg-js-bg-elevated/40 p-3">
                <p class="text-[11px] uppercase tracking-wide text-js-text-subtle">
                  Try These First Runs
                </p>
                <%= if starter_beginner?(@starter_agent) do %>
                  <p class="mt-2 text-xs text-js-text-muted font-mono">
                    Signal `beginner.add` with: <code>{"{\"a\": 25, \"b\": 4}"}</code>
                  </p>
                  <p class="mt-1 text-xs text-js-text-muted font-mono">
                    Signal `beginner.tip` with:
                    <code>{"{\"amount\": 42.5, \"rate_percent\": 20}"}</code>
                  </p>
                  <p class="mt-1 text-xs text-js-text-muted font-mono">
                    Signal `beginner.ping` with: <code>{"{\"message\": \"hello\"}"}</code>
                  </p>
                <% else %>
                  <p class="mt-2 text-xs text-js-text-muted">
                    Open the starter module, review available signal/action schemas, and run one simple
                    interaction first.
                  </p>
                  <p class="mt-1 text-xs text-js-text-muted">
                    Keep scope (`runtime` and `node`) fixed while you validate the first run.
                  </p>
                <% end %>
              </div>
            </div>

            <div class="mt-3 flex flex-wrap items-center gap-2">
              <button
                type="button"
                phx-click="open_starter_agent"
                phx-value-path={
                  @starter_launch_path ||
                    page_path(@prefix, "/agents", @runtime_key, @cluster_node_param)
                }
                phx-value-mode="home_card"
                phx-value-starter_slug={if(@starter_agent, do: @starter_agent.slug, else: "")}
                phx-value-starter_module={
                  if(@starter_agent && is_atom(@starter_agent.module),
                    do: inspect(@starter_agent.module),
                    else: ""
                  )
                }
                class="inline-flex items-center rounded-md bg-js-primary px-3 py-1.5 text-xs font-medium text-js-primary-foreground hover:brightness-110"
              >
                Open Starter Agent
              </button>
              <.link
                navigate={page_path(@prefix, "/agents", @runtime_key, @cluster_node_param)}
                class="inline-flex items-center rounded-md border border-js-border px-3 py-1.5 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
              >
                Browse All Agents
              </.link>
            </div>
          </.card>

          <div
            data-js-home-example-show
            class="hidden rounded-md border border-dashed border-js-border px-3 py-2 text-xs text-js-text-muted flex items-center justify-between gap-2"
          >
            <span>Starter guide hidden.</span>
            <button
              type="button"
              data-js-home-example-show-btn
              class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Show Example
            </button>
          </div>
        </div>

        <.card>
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold text-js-text">Recent Failures</h2>
            <.badge :if={@recent_failures != []} variant={:error}>
              {length(@recent_failures)}
            </.badge>
          </div>

          <div :if={@recent_failures == []} class="mt-4">
            <.empty_state
              title="No recent failures"
              description="Failures will appear here when incidents are indexed in the selected scope."
            />
          </div>

          <div :if={@recent_failures != []} class="mt-3 divide-y divide-js-border">
            <div
              :for={incident <- @recent_failures}
              class="py-2 flex items-start justify-between gap-3"
            >
              <div class="min-w-0">
                <div class="text-xs text-js-text truncate">{incident.title}</div>
                <div class="text-[11px] text-js-text-subtle font-mono truncate">
                  {incident.subtitle}
                </div>
              </div>
              <div class="text-[11px] text-js-text-subtle font-mono whitespace-nowrap">
                {incident.when}
              </div>
            </div>
          </div>
        </.card>
      </div>
    </div>
    """
  end

  defp refresh_home(socket) do
    scope = socket.assigns.cluster_scope
    jido_instance = socket.assigns[:jido_instance]
    runtime_key = socket.assigns[:runtime_key]
    storage_info = Helpers.thread_storage_details(jido_instance)
    thread_persistence? = ThreadsStorage.persistence_enabled?()

    agents = AgentRegistry.list_agents(jido_instance: jido_instance, scope: scope)
    incidents = cluster_incidents(scope)
    traces = cluster_traces(scope)

    setup_assistant =
      Setup.build(
        scope: scope,
        jido_instance: jido_instance,
        prefix: socket.assigns.prefix,
        runtime_key: runtime_key,
        node_param: socket.assigns.cluster_node_param,
        agents: agents
      )

    state =
      HomeState.build(
        scope: scope,
        prefix: socket.assigns.prefix,
        runtime_key: runtime_key,
        node_param: socket.assigns.cluster_node_param,
        agents: agents,
        incidents: incidents,
        traces: traces,
        storage_info: storage_info,
        thread_persistence?: thread_persistence?,
        setup_assistant: setup_assistant,
        selected_setup_profile: socket.assigns[:selected_setup_profile]
      )

    starter_launch_path =
      starter_launch_path(
        socket.assigns.prefix,
        state.starter_agent,
        runtime_key,
        socket.assigns.cluster_node_param
      )

    socket
    |> maybe_emit_setup_telemetry(state.setup_assistant)
    |> maybe_emit_next_step_links_telemetry(state.next_step_metrics)
    |> assign(:summary, state.summary)
    |> assign(:top_agents, state.top_agents)
    |> assign(:starter_agent, state.starter_agent)
    |> assign(:starter_reason, state.starter_reason)
    |> assign(:starter_launch_path, starter_launch_path)
    |> assign(:starter_running?, state.starter_running?)
    |> assign(:setup_assistant, state.setup_assistant)
    |> assign(:setup_profile, state.setup_profile)
    |> assign(:setup_check_statuses, state.setup_statuses)
    |> assign(:attention_items, state.attention_items)
    |> assign(:recent_activity, state.recent_activity)
    |> assign(:recent_failures, state.recent_failures)
  end

  defp cluster_incidents(scope) do
    scope
    |> Collect.list(Incidents, :list_incidents, [%{range: "24h"}, 40])
    |> Enum.uniq_by(&(&1[:incident_id] || &1[:id]))
    |> Enum.sort_by(&(&1[:last_event_at] || 0), :desc)
  end

  defp cluster_traces(scope) do
    scope
    |> Collect.list(Tracing, :list_traces, [[filters: %{range: "24h"}, limit: 30]])
    |> Enum.uniq_by(&(&1[:trace_id] || &1[:id]))
    |> Enum.sort_by(&(&1[:last_event_at] || &1[:started_at] || 0), :desc)
  end

  defp page_path(prefix, suffix, runtime_key, node_param) do
    ScopeQuery.with_scope_query(prefix <> suffix, runtime_key, node_param)
  end

  defp agent_launch_path(prefix, %{slug: slug} = agent, runtime_key, node_param)
       when is_binary(slug) do
    case first_running_instance_id(Map.get(agent, :running_instances, [])) do
      nil ->
        ScopeQuery.with_scope_query("#{prefix}/agents/#{slug}", runtime_key, node_param)

      instance_id ->
        ScopeQuery.with_scope_query(
          "#{prefix}/agents/#{slug}/#{PathSegments.encode(instance_id)}",
          runtime_key,
          node_param
        )
    end
  end

  defp agent_launch_path(prefix, _agent, runtime_key, node_param) do
    ScopeQuery.with_scope_query("#{prefix}/agents", runtime_key, node_param)
  end

  defp agent_launch_hint(agent) when is_map(agent) do
    case first_running_instance_id(Map.get(agent, :running_instances, [])) do
      nil -> "Open module details"
      instance_id -> "Open running instance: #{instance_id}"
    end
  end

  defp agent_launch_hint(_agent), do: "Open agent"

  defp display_agent_name(%{name: name}) when is_binary(name), do: Naming.humanize(name)

  defp display_agent_name(%{slug: slug}) when is_binary(slug), do: Naming.humanize(slug)
  defp display_agent_name(_), do: "Agent"

  defp starter_launch_path(prefix, nil, runtime_key, node_param) do
    ScopeQuery.with_scope_query("#{prefix}/agents", runtime_key, node_param)
  end

  defp starter_launch_path(prefix, %{slug: slug} = agent, runtime_key, node_param)
       when is_binary(slug) do
    case first_running_instance_id(Map.get(agent, :running_instances, [])) do
      nil ->
        ScopeQuery.with_scope_query("#{prefix}/agents/#{slug}?start=1", runtime_key, node_param)

      _instance_id ->
        agent_launch_path(prefix, agent, runtime_key, node_param)
    end
  end

  defp starter_launch_path(prefix, _agent, runtime_key, node_param),
    do: ScopeQuery.with_scope_query("#{prefix}/agents", runtime_key, node_param)

  defp starter_status_hint(true, reason) when is_binary(reason) and reason != "" do
    "A starter instance is already running. Open it and continue the onboarding flow. #{reason}"
  end

  defp starter_status_hint(true, _reason) do
    "A starter instance is already running. Open it and continue the onboarding flow."
  end

  defp starter_status_hint(false, reason) when is_binary(reason) and reason != "" do
    "#{reason} Open the module and confirm Start Instance when ready."
  end

  defp starter_status_hint(false, _reason) do
    "Open the starter module and confirm Start Instance when ready."
  end

  defp starter_beginner?(%{module: module}) when is_atom(module), do: module == Beginner.module()
  defp starter_beginner?(_), do: false

  defp first_running_instance_id(instances) when is_list(instances) do
    instances
    |> Enum.map(&Map.get(&1, :id))
    |> Enum.filter(&is_binary/1)
    |> Enum.sort()
    |> List.first()
  end

  defp first_running_instance_id(_), do: nil

  defp maybe_emit_setup_telemetry(socket, setup_assistant) do
    previous = socket.assigns[:setup_check_statuses] || %{}

    :ok =
      Helpers.emit_step_telemetry(
        previous,
        setup_assistant.checks,
        runtime: socket.assigns[:runtime_key],
        node: socket.assigns[:cluster_node_param],
        source: "home"
      )

    socket
  end

  defp maybe_emit_next_step_links_telemetry(socket, %{linked_count: linked, total_count: total}) do
    current = %{linked_count: linked, total_count: total}

    if socket.assigns[:next_step_links_metrics] == current do
      socket
    else
      :ok =
        ProductMetrics.incidents_next_step_links_evaluated(
          socket,
          linked,
          total,
          source: "home_attention"
        )

      assign(socket, :next_step_links_metrics, current)
    end
  end

  defp maybe_emit_next_step_links_telemetry(socket, _), do: socket

  defp normalize_starter_mode(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      normalized -> normalized
    end
  end

  defp normalize_starter_mode(_value, fallback), do: fallback

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil

  defp runtime_scope_label(runtime_key, _jido_instance) when is_binary(runtime_key),
    do: runtime_key

  defp runtime_scope_label(_runtime_key, jido_instance) when is_atom(jido_instance) do
    jido_instance
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
  end

  defp runtime_scope_label(_, _), do: "default"
end
