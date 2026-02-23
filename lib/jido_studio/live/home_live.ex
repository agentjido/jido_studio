defmodule JidoStudio.HomeLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components
  import JidoStudio.Setup.Components

  alias JidoStudio.AgentRegistry
  alias JidoStudio.Cluster.RPC
  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Naming
  alias JidoStudio.Observability.Incidents
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
      |> assign(:example_agent, nil)
      |> assign(:example_launch_path, nil)
      |> assign(:example_running?, false)
      |> assign(:example_provider_name, nil)
      |> assign(:example_keys_missing?, false)
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
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6 space-y-4">
      <.page_header title="Home" subtitle="Operational overview with fast paths to action">
        <:actions>
          <.badge variant={:default}>
            runtime:{runtime_scope_label(@runtime_key, @jido_instance)}
          </.badge>
          <.badge variant={:info}>node:{@cluster_node_param || "all"}</.badge>
        </:actions>
      </.page_header>

      <div
        data-js-home-setup
        data-js-home-setup-complete={to_string(@setup_assistant.core_ready?)}
        class="space-y-3"
      >
        <div data-js-home-setup-grid class="grid grid-cols-1 xl:grid-cols-2 gap-4">
          <.card>
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
                  <.link
                    :if={item[:path]}
                    navigate={item.path}
                    class="text-[11px] text-js-info hover:text-js-text"
                  >
                    Open
                  </.link>
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

          <.card data-js-home-setup-card class="h-full">
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
            class="border-js-info/35 bg-gradient-to-r from-js-info/12 via-js-card to-js-card p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="text-[11px] uppercase tracking-wider text-js-info">Example</p>
                <h2 class="mt-1 text-base font-semibold text-js-text">Calculator Agent</h2>
                <p class="mt-1 text-xs text-js-text-muted max-w-2xl">
                  Run one calculator example to learn the Studio flow before moving to deeper diagnostics.
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
                  <.badge variant={if @example_running?, do: :success, else: :default}>
                    {if @example_running?, do: "Running", else: "Available"}
                  </.badge>
                  <.badge :if={@example_keys_missing?} variant={:warning}>
                    Missing {@example_provider_name || "LLM"} key
                  </.badge>
                  <span class="text-xs text-js-text">{display_agent_name(@example_agent)}</span>
                </div>
                <p class="mt-2 text-xs text-js-text-muted">
                  {example_status_hint(@example_running?, @example_keys_missing?)}
                </p>
              </div>

              <div class="rounded-md border border-js-border/70 bg-js-bg-elevated/40 p-3">
                <p class="text-[11px] uppercase tracking-wide text-js-text-subtle">
                  Try These Prompts
                </p>
                <p class="mt-2 text-xs text-js-text-muted font-mono">What is 25 * 4 + 50?</p>
                <p class="mt-1 text-xs text-js-text-muted font-mono">
                  Calculate ((18 / 3) + 7) * 9
                </p>
                <p class="mt-1 text-xs text-js-text-muted font-mono">
                  What is a 20% tip on 42.50?
                </p>
              </div>
            </div>

            <div class="mt-3 flex flex-wrap items-center gap-2">
              <.link
                navigate={
                  @example_launch_path ||
                    page_path(@prefix, "/agents", @runtime_key, @cluster_node_param)
                }
                class="inline-flex items-center rounded-md bg-js-primary px-3 py-1.5 text-xs font-medium text-js-primary-foreground hover:brightness-110"
              >
                Open Calculator Example
              </.link>
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
            <span>Calculator example hidden.</span>
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
                <div class="text-xs text-js-text truncate">{failure_title(incident)}</div>
                <div class="text-[11px] text-js-text-subtle font-mono truncate">
                  {failure_subtitle(incident)}
                </div>
              </div>
              <div class="text-[11px] text-js-text-subtle font-mono whitespace-nowrap">
                {format_timestamp(incident[:last_event_at] || incident[:started_at])}
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

    summary = %{
      online_agents: Enum.count(agents, &((&1.running_instances || []) != [])),
      available_agents: Enum.count(agents, &((&1.running_instances || []) == [])),
      running_instances: Enum.reduce(agents, 0, &(&2 + length(&1.running_instances || []))),
      active_incidents: Enum.count(incidents, &incident_active?/1),
      node_count: node_count(scope),
      thread_persistence?: thread_persistence?,
      thread_storage_adapter: storage_info.adapter,
      thread_storage_path: storage_info.path
    }

    top_agents =
      agents
      |> Enum.sort_by(&length(&1.running_instances || []), :desc)
      |> Enum.take(5)

    example_agent = find_calculator_agent(agents)
    example_provider = example_provider(example_agent)
    example_keys_missing? = provider_key_missing?(example_provider)

    attention_items =
      []
      |> maybe_add_attention(summary.active_incidents > 0, %{
        title: "#{summary.active_incidents} active incidents",
        description: "Open Activity or Diagnostics to inspect current failures and timelines.",
        path:
          page_path(
            socket.assigns.prefix,
            "/activity",
            runtime_key,
            socket.assigns.cluster_node_param
          )
      })
      |> maybe_add_attention(Enum.any?(traces, &(&1[:status] == "error")), %{
        title: "Recent error traces detected",
        description: "A trace ended with errors in the current scope within the recent window.",
        path:
          page_path(
            socket.assigns.prefix,
            "/diagnostics",
            runtime_key,
            socket.assigns.cluster_node_param
          )
      })

    recent_failures =
      incidents
      |> Enum.filter(&incident_active?/1)
      |> Enum.take(5)

    recent_activity =
      traces
      |> Enum.take(8)
      |> Enum.map(fn trace ->
        %{
          title: trace[:trace_id] || trace[:id] || "trace",
          subtitle:
            [trace[:agent_id], trace[:status]] |> Enum.reject(&is_nil/1) |> Enum.join(" / "),
          when: format_timestamp(trace[:last_event_at] || trace[:started_at])
        }
      end)

    example_launch_path =
      example_launch_path(
        socket.assigns.prefix,
        example_agent,
        runtime_key,
        socket.assigns.cluster_node_param
      )

    setup_assistant =
      Setup.build(
        scope: scope,
        jido_instance: jido_instance,
        prefix: socket.assigns.prefix,
        runtime_key: runtime_key,
        node_param: socket.assigns.cluster_node_param,
        agents: agents
      )

    selected_profile_key =
      Helpers.normalize_profile_key(
        socket.assigns[:selected_setup_profile],
        setup_assistant.active_profile_key
      )

    setup_assistant = Map.put(setup_assistant, :active_profile_key, selected_profile_key)
    setup_profile = Profiles.find_profile(selected_profile_key)
    setup_statuses = Setup.check_statuses(setup_assistant)

    socket
    |> maybe_emit_setup_telemetry(setup_assistant)
    |> assign(:summary, summary)
    |> assign(:top_agents, top_agents)
    |> assign(:example_agent, example_agent)
    |> assign(:example_launch_path, example_launch_path)
    |> assign(:example_running?, example_running?(example_agent))
    |> assign(:example_provider_name, provider_display_name(example_provider))
    |> assign(:example_keys_missing?, example_keys_missing?)
    |> assign(:setup_assistant, setup_assistant)
    |> assign(:setup_profile, setup_profile)
    |> assign(:setup_check_statuses, setup_statuses)
    |> assign(:attention_items, attention_items)
    |> assign(:recent_activity, recent_activity)
    |> assign(:recent_failures, recent_failures)
  end

  defp cluster_incidents(scope) do
    scope
    |> collect(Incidents, :list_incidents, [%{range: "24h"}, 40])
    |> Enum.uniq_by(&(&1[:incident_id] || &1[:id]))
    |> Enum.sort_by(&(&1[:last_event_at] || 0), :desc)
  end

  defp cluster_traces(scope) do
    scope
    |> collect(Tracing, :list_traces, [[filters: %{range: "24h"}, limit: 30]])
    |> Enum.uniq_by(&(&1[:trace_id] || &1[:id]))
    |> Enum.sort_by(&(&1[:last_event_at] || &1[:started_at] || 0), :desc)
  end

  defp collect(:all, module, fun, args) do
    case RPC.call(:all, module, fun, args) do
      {:ok, results} when is_list(results) ->
        results
        |> Enum.flat_map(fn
          %{ok?: true, value: items} when is_list(items) -> items
          _ -> []
        end)

      _ ->
        []
    end
  end

  defp collect(scope, module, fun, args) do
    node = Scope.selected_node(scope) || Node.self()

    case RPC.call({:node, node}, module, fun, args) do
      {:ok, items} when is_list(items) -> items
      _ -> []
    end
  end

  defp node_count(:all), do: length(Scope.available_nodes())
  defp node_count(_), do: 1

  defp incident_active?(incident) when is_map(incident) do
    status = to_string(incident[:status] || "")
    error_count = incident[:error_count] || 0

    status == "error" or error_count > 0
  end

  defp incident_active?(_), do: false

  defp maybe_add_attention(items, true, item), do: [item | items]
  defp maybe_add_attention(items, false, _item), do: items

  defp failure_title(incident) when is_map(incident) do
    incident[:latest_action] || incident[:latest_signal_type] || incident[:incident_id] ||
      "incident"
  end

  defp failure_title(_incident), do: "incident"

  defp failure_subtitle(incident) when is_map(incident) do
    [incident[:latest_agent_id], incident[:status]]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" / ")
    |> case do
      "" -> "failure"
      value -> value
    end
  end

  defp failure_subtitle(_incident), do: "failure"

  defp format_timestamp(ts) when is_integer(ts) and ts > 0 do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp format_timestamp(_), do: "-"

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
          "#{prefix}/agents/#{slug}/#{URI.encode_www_form(instance_id)}",
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

  defp find_calculator_agent(agents) when is_list(agents) do
    Enum.find(agents, &calculator_agent?/1)
  end

  defp find_calculator_agent(_), do: nil

  defp calculator_agent?(agent) when is_map(agent) do
    [
      Map.get(agent, :name),
      Map.get(agent, :slug),
      Map.get(agent, :description),
      module_name(Map.get(agent, :module))
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.any?(fn value ->
      value
      |> String.downcase()
      |> String.contains?("calculator")
    end)
  end

  defp calculator_agent?(_), do: false

  defp module_name(module) when is_atom(module), do: Atom.to_string(module)
  defp module_name(_), do: nil

  defp example_launch_path(prefix, nil, runtime_key, node_param) do
    ScopeQuery.with_scope_query("#{prefix}/agents", runtime_key, node_param)
  end

  defp example_launch_path(prefix, agent, runtime_key, node_param) do
    agent_launch_path(prefix, agent, runtime_key, node_param)
  end

  defp example_running?(%{running_instances: instances}) when is_list(instances) do
    instances != []
  end

  defp example_running?(_), do: false

  defp example_status_hint(_running?, true) do
    "This example uses an LLM provider key for chat responses. You can still inspect and run signals/actions in Interact."
  end

  defp example_status_hint(true, false) do
    "A calculator instance is already live. Open it and ask a simple arithmetic prompt."
  end

  defp example_status_hint(false, false) do
    "Open the calculator module and start an instance when you're ready."
  end

  defp example_provider(%{running_instances: instances} = agent) when is_list(instances) do
    runtime_provider =
      Enum.find_value(instances, fn
        %{pid: pid} when is_pid(pid) -> runtime_provider(pid)
        _ -> nil
      end)

    runtime_provider || strategy_provider(agent)
  end

  defp example_provider(agent), do: strategy_provider(agent)

  defp runtime_provider(pid) when is_pid(pid) do
    case Jido.AgentServer.status(pid) do
      {:ok, status} ->
        status
        |> runtime_model_label()
        |> provider_from_model_label()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp runtime_provider(_), do: nil

  defp runtime_model_label(%{snapshot: %{details: details}}) when is_map(details) do
    details[:model] || details["model"]
  end

  defp runtime_model_label(_), do: nil

  defp strategy_provider(%{module: module}) when is_atom(module) do
    module
    |> strategy_model_label()
    |> provider_from_model_label()
  end

  defp strategy_provider(_), do: nil

  defp strategy_model_label(module) when is_atom(module) do
    if function_exported?(module, :strategy_opts, 0) do
      module
      |> apply(:strategy_opts, [])
      |> Keyword.get(:model)
      |> to_string()
    end
  rescue
    _ -> nil
  end

  defp strategy_model_label(_), do: nil

  defp provider_from_model_label(model_label) when is_binary(model_label) do
    case String.split(String.trim(model_label), ":", parts: 2) do
      [provider, _model] -> provider |> String.trim() |> String.downcase()
      _ -> nil
    end
  end

  defp provider_from_model_label(_), do: nil

  defp provider_key_missing?(provider) when provider in [nil, "", "ollama", "custom"], do: false

  defp provider_key_missing?("anthropic"),
    do: not env_present?(["ANTHROPIC_API_KEY", "CLAUDE_API_KEY"])

  defp provider_key_missing?("openai"), do: not env_present?(["OPENAI_API_KEY"])
  defp provider_key_missing?("groq"), do: not env_present?(["GROQ_API_KEY"])
  defp provider_key_missing?(_), do: false

  defp provider_display_name("anthropic"), do: "Anthropic"
  defp provider_display_name("openai"), do: "OpenAI"
  defp provider_display_name("groq"), do: "Groq"
  defp provider_display_name(provider) when is_binary(provider), do: Naming.humanize(provider)
  defp provider_display_name(_), do: nil

  defp env_present?(env_vars) when is_list(env_vars) do
    Enum.any?(env_vars, fn var ->
      case System.get_env(var) do
        value when is_binary(value) -> String.trim(value) != ""
        _ -> false
      end
    end)
  end

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
