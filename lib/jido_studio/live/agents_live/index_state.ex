defmodule JidoStudio.Live.AgentsLive.IndexState do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias JidoStudio.AgentRegistry
  alias JidoStudio.Agents.FilterForm, as: AgentsFilterForm
  alias JidoStudio.Agents.RunnerForm
  alias JidoStudio.Chat.Session, as: ChatSession
  alias JidoStudio.Live.AgentsLive.ShowState
  alias JidoStudio.Live.AgentsLive.Support
  alias JidoStudio.LiveOps
  alias JidoStudio.Onboarding.StarterAgent
  alias JidoStudio.Presenters.Default
  alias JidoStudio.ScopeQuery

  @default_model "claude-sonnet-4-5"

  def apply(socket, params, opts \\ []) do
    chat_provider_options = Keyword.get(opts, :chat_provider_options, ["anthropic"])

    start_form_schema = Default.start_form_schema(%{})
    jido_instance = socket.assigns[:jido_instance]

    base_scope = socket.assigns[:scope_filters] || %{project_id: nil, user_id: nil, agent_id: nil}
    scope_filters = Support.merge_scope_filters(base_scope, Map.get(params, "scope"))
    base_filters = socket.assigns[:agent_filters] || AgentsFilterForm.new()
    agent_filters = AgentsFilterForm.parse(Map.get(params, "filters"), base_filters)

    listed_agents =
      AgentRegistry.list_agents(
        jido_instance: jido_instance,
        scope: socket.assigns[:cluster_scope]
      )

    agents = Support.filter_agents_by_scope(listed_agents, scope_filters)
    {product_agents, internal_agents} = Support.split_discovered_agents(agents)
    {starter_agent, starter_reason} = StarterAgent.pick(product_agents)

    starter_launch_path =
      starter_launch_path(
        socket.assigns.prefix,
        starter_agent,
        socket.assigns[:runtime_key],
        socket.assigns[:cluster_node_param]
      )

    active_instances =
      Support.build_active_instances(agents,
        now: DateTime.utc_now(),
        viewer_count_fun: &LiveOps.viewer_count/1
      )

    filtered_instances = AgentsFilterForm.apply_filters(active_instances, agent_filters)
    followed_from_params = Support.normalize_scope_value(Map.get(params, "followed_instance_id"))

    running_count =
      AgentRegistry.running_count(
        jido_instance,
        scope: socket.assigns[:cluster_scope]
      )

    socket =
      socket
      |> assign(:page_title, "Agents")
      |> assign(:scope_filters, scope_filters)
      |> assign(:agent_filters, agent_filters)
      |> assign(:agents, agents)
      |> assign(:product_agents, product_agents)
      |> assign(:internal_agents, internal_agents)
      |> assign(:starter_agent, starter_agent)
      |> assign(:starter_reason, starter_reason)
      |> assign(:starter_launch_path, starter_launch_path)
      |> assign(:active_instances, active_instances)
      |> assign(:filtered_instances, filtered_instances)
      |> assign(
        :followed_instance_id,
        followed_from_params || socket.assigns[:followed_instance_id]
      )
      |> assign(:running_count, running_count)
      |> assign(:agent, nil)
      |> assign(:presenter, Default)
      |> assign(:agent_workspace_key, nil)
      |> assign(:running_instances, [])
      |> assign(:instance_cards, [])
      |> assign(:active_instance_id, nil)
      |> assign(:active_instance_pid, nil)
      |> assign(:runtime_status, nil)
      |> assign(:chat_state, ChatSession.empty())
      |> assign(:chat_config, ShowState.default_chat_config())
      |> assign(:chat_enabled?, false)
      |> assign(:chat_unavailable_reason, nil)
      |> assign(:chat_pending?, false)
      |> assign(:chat_pending_message_id, nil)
      |> assign(:chat_stream, nil)
      |> assign(:draft_message, "")
      |> assign(:workspace_source, :fresh)
      |> assign(:persisted_thread_contexts, %{})
      |> assign(:persist_workspace_ref, nil)
      |> assign(:workbench_tab, :chat)
      |> assign(:instance_section, :play)
      |> assign(:runtime_messages, [])
      |> assign(:runtime_todos, [])
      |> assign(:instance_event_stream, [])
      |> assign(:instance_event_query, "")
      |> assign(:expanded_event_ids, MapSet.new())
      |> assign(:expanded_subagent_id, nil)
      |> assign(:subagent_detail_tab, "config")
      |> assign(:subagent_events, %{})
      |> assign(:interaction_model, Support.empty_interaction_model())
      |> assign(:runner_form, RunnerForm.new())
      |> assign(:runner_result, nil)
      |> assign(:runner_history, [])
      |> assign(:interaction_history, %{})
      |> assign(:show_advanced_signals?, true)
      |> assign(:signal_scope, "entry_advanced")
      |> ShowState.assign_chat_controls(@default_model, chat_provider_options)
      |> assign(:start_form_schema, start_form_schema)
      |> assign(:start_form, Support.default_start_form(start_form_schema))
      |> assign(:instance_observability_events, [])
      |> assign(:instance_debug_events, [])
      |> assign(:instance_telemetry_events, [])
      |> assign(:instance_debug_error, nil)
      |> assign(:instance_debug_enabled?, false)
      |> assign(:instance_debug_level, "off")
      |> assign(:subagents, [])
      |> assign(:tasks, [])
      |> assign(:delegation_graph, %{nodes: [], edges: []})
      |> assign(:tool_insights, [])
      |> assign(:middleware_snapshots, [])
      |> assign(:triage_links, %{})
      |> Support.maybe_subscribe_viewers(active_instances)
      |> Support.maybe_auto_follow_filtered_instances()

    socket
    |> assign(
      :followed_instance_id,
      Support.resolve_followed_instance(socket, filtered_instances)
    )
    |> Support.maybe_track_followed_viewer()
  end

  def refresh(socket) do
    jido_instance = socket.assigns[:jido_instance]

    agents =
      AgentRegistry.list_agents(
        jido_instance: jido_instance,
        scope: socket.assigns[:cluster_scope]
      )
      |> Support.filter_agents_by_scope(socket.assigns[:scope_filters])

    {product_agents, internal_agents} = Support.split_discovered_agents(agents)
    {starter_agent, starter_reason} = StarterAgent.pick(product_agents)

    starter_launch_path =
      starter_launch_path(
        socket.assigns.prefix,
        starter_agent,
        socket.assigns[:runtime_key],
        socket.assigns[:cluster_node_param]
      )

    active_instances =
      Support.build_active_instances(agents,
        now: DateTime.utc_now(),
        viewer_count_fun: &LiveOps.viewer_count/1
      )

    filtered_instances =
      AgentsFilterForm.apply_filters(active_instances, socket.assigns.agent_filters)

    running_count =
      AgentRegistry.running_count(
        jido_instance,
        scope: socket.assigns[:cluster_scope]
      )

    socket
    |> assign(:agents, agents)
    |> assign(:product_agents, product_agents)
    |> assign(:internal_agents, internal_agents)
    |> assign(:starter_agent, starter_agent)
    |> assign(:starter_reason, starter_reason)
    |> assign(:starter_launch_path, starter_launch_path)
    |> assign(:running_count, running_count)
    |> assign(:active_instances, active_instances)
    |> assign(:filtered_instances, filtered_instances)
    |> Support.maybe_subscribe_viewers(active_instances)
    |> Support.maybe_auto_follow_filtered_instances()
    |> then(fn updated ->
      updated
      |> assign(
        :followed_instance_id,
        Support.resolve_followed_instance(updated, filtered_instances)
      )
      |> Support.maybe_track_followed_viewer()
    end)
  end

  def update_scope_filters(socket, scope_params) do
    filters = Support.normalize_scope_filters(scope_params)
    jido_instance = socket.assigns[:jido_instance]

    if Phoenix.LiveView.connected?(socket) and socket.assigns[:live_ops_enabled?] do
      _ = LiveOps.subscribe_agent_list(filters)
    end

    agents =
      AgentRegistry.list_agents(
        jido_instance: jido_instance,
        scope: socket.assigns[:cluster_scope]
      )
      |> Support.filter_agents_by_scope(filters)

    {product_agents, internal_agents} = Support.split_discovered_agents(agents)
    {starter_agent, starter_reason} = StarterAgent.pick(product_agents)

    starter_launch_path =
      starter_launch_path(
        socket.assigns.prefix,
        starter_agent,
        socket.assigns[:runtime_key],
        socket.assigns[:cluster_node_param]
      )

    active_instances =
      Support.build_active_instances(agents,
        now: DateTime.utc_now(),
        viewer_count_fun: &LiveOps.viewer_count/1
      )

    filtered_instances =
      AgentsFilterForm.apply_filters(active_instances, socket.assigns.agent_filters)

    socket
    |> assign(:scope_filters, filters)
    |> assign(:agents, agents)
    |> assign(:product_agents, product_agents)
    |> assign(:internal_agents, internal_agents)
    |> assign(:starter_agent, starter_agent)
    |> assign(:starter_reason, starter_reason)
    |> assign(:starter_launch_path, starter_launch_path)
    |> assign(:active_instances, active_instances)
    |> assign(:filtered_instances, filtered_instances)
    |> Support.maybe_subscribe_viewers(active_instances)
    |> Support.maybe_auto_follow_filtered_instances()
    |> then(fn updated ->
      updated
      |> assign(
        :followed_instance_id,
        Support.resolve_followed_instance(updated, filtered_instances)
      )
      |> Support.maybe_track_followed_viewer()
    end)
  end

  def update_instance_filters(socket, params) do
    filters = AgentsFilterForm.parse(params, socket.assigns.agent_filters)
    filtered_instances = AgentsFilterForm.apply_filters(socket.assigns.active_instances, filters)

    socket
    |> assign(:agent_filters, filters)
    |> assign(:filtered_instances, filtered_instances)
    |> Support.maybe_auto_follow_filtered_instances()
    |> then(fn updated ->
      updated
      |> assign(
        :followed_instance_id,
        Support.resolve_followed_instance(updated, filtered_instances)
      )
      |> Support.maybe_track_followed_viewer()
    end)
  end

  def toggle_auto_follow_instances(socket) do
    socket
    |> assign(:auto_follow_instances?, not socket.assigns.auto_follow_instances?)
    |> Support.maybe_auto_follow_filtered_instances()
    |> then(fn updated ->
      updated
      |> assign(
        :followed_instance_id,
        Support.resolve_followed_instance(updated, updated.assigns.filtered_instances)
      )
      |> Support.maybe_track_followed_viewer()
    end)
  end

  def update_auto_follow_target(socket, params) do
    target = Support.normalize_auto_follow_target(params, socket.assigns.auto_follow_target)

    socket
    |> assign(:auto_follow_target, target)
    |> Support.maybe_auto_follow_filtered_instances()
    |> then(fn updated ->
      updated
      |> assign(
        :followed_instance_id,
        Support.resolve_followed_instance(updated, updated.assigns.filtered_instances)
      )
      |> Support.maybe_track_followed_viewer()
    end)
  end

  def follow_instance(socket, instance_id) do
    socket
    |> assign(:followed_instance_id, Support.normalize_scope_value(instance_id))
    |> Support.maybe_track_followed_viewer()
  end

  def unfollow_instance(socket) do
    socket
    |> assign(:followed_instance_id, nil)
    |> Support.maybe_track_followed_viewer()
  end

  def handle_agent_list_event(socket, payload) do
    if Support.scope_filters_match?(Map.get(payload, :scope), socket.assigns[:scope_filters]) do
      refresh(socket)
    else
      Support.maybe_track_followed_viewer(socket)
    end
  end

  def handle_presence_diff(socket, topic) do
    if String.starts_with?(topic, "live_ops:viewers:") and socket.assigns.live_action == :index do
      agents = socket.assigns.agents || []

      active_instances =
        Support.build_active_instances(agents,
          now: DateTime.utc_now(),
          viewer_count_fun: &LiveOps.viewer_count/1
        )

      filtered_instances =
        AgentsFilterForm.apply_filters(active_instances, socket.assigns.agent_filters)

      socket
      |> assign(:active_instances, active_instances)
      |> assign(:filtered_instances, filtered_instances)
      |> Support.maybe_auto_follow_filtered_instances()
      |> then(fn updated ->
        updated
        |> assign(
          :followed_instance_id,
          Support.resolve_followed_instance(updated, filtered_instances)
        )
        |> Support.maybe_track_followed_viewer()
      end)
    else
      socket
    end
  end

  def after_observability_refresh(socket) do
    if socket.assigns.live_action == :index do
      refresh(socket)
    else
      Support.maybe_track_followed_viewer(socket)
    end
  end

  defp starter_launch_path(prefix, %{slug: slug}, runtime_key, node_param) when is_binary(slug) do
    ScopeQuery.with_scope_query("#{prefix}/agents/#{slug}?start=1", runtime_key, node_param)
  end

  defp starter_launch_path(prefix, _starter_agent, runtime_key, node_param) do
    ScopeQuery.with_scope_query("#{prefix}/agents", runtime_key, node_param)
  end
end
