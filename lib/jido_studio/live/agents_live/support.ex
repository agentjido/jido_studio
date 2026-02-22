defmodule JidoStudio.Live.AgentsLive.Support do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias JidoStudio.AgentInteractions
  alias JidoStudio.Agents.InstanceIndex
  alias JidoStudio.Delegation
  alias JidoStudio.Live.AgentsLive.Contracts
  alias JidoStudio.Live.AgentsLive.Errors
  alias JidoStudio.Live.AgentsLive.Routes
  alias JidoStudio.Live.AgentsLive.RunnerState
  alias JidoStudio.Live.AgentsLive.Support.EventHelpers
  alias JidoStudio.Live.AgentsLive.Support.ScopeHelpers
  alias JidoStudio.LiveOps
  alias JidoStudio.Naming
  alias JidoStudio.TraceBuffer

  def viewer_id do
    "studio-viewer-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defdelegate event_metadata_value(event, key), to: EventHelpers
  defdelegate format_event_name(event), to: EventHelpers
  defdelegate format_event_timestamp(ts), to: EventHelpers

  def short_instance_id(id) when is_binary(id) do
    if String.length(id) <= 12, do: id, else: String.slice(id, 0, 12)
  end

  def short_instance_id(_), do: "instance"

  def build_active_instances(agents, opts) when is_list(agents) do
    trace_events = Keyword.get(opts, :trace_events, TraceBuffer.events(2_000))

    InstanceIndex.build_rows(
      agents,
      opts
      |> Keyword.put(:trace_events, trace_events)
      |> Keyword.put_new(:now, DateTime.utc_now())
    )
  end

  def build_active_instances(_, _), do: []

  def split_discovered_agents(agents) when is_list(agents) do
    Enum.reduce(agents, {[], []}, fn agent, {product, internal} ->
      if internal_agent?(agent) do
        {product, internal ++ [agent]}
      else
        {product ++ [agent], internal}
      end
    end)
  end

  def split_discovered_agents(_), do: {[], []}

  def internal_agent?(%{} = agent) do
    tags =
      agent
      |> Map.get(:tags, [])
      |> normalize_tag_list()

    internal_tags = AgentInteractions.internal_agent_tags()
    Enum.any?(tags, &(&1 in internal_tags))
  end

  def internal_agent?(_), do: false

  def internal_instance?(%{} = row) do
    tags =
      row
      |> Map.get(:agent_tags, [])
      |> normalize_tag_list()

    internal_tags = AgentInteractions.internal_agent_tags()
    Enum.any?(tags, &(&1 in internal_tags))
  end

  def internal_instance?(_), do: false

  def normalize_tag_list(tags) when is_list(tags) do
    tags
    |> Enum.map(fn
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.downcase/1)
  end

  def normalize_tag_list(_), do: []

  def requested_workbench_tab(params) when is_map(params) do
    panel = Map.get(params, "panel")
    legacy_view = Map.get(params, "view")

    if is_nil(panel) and is_nil(legacy_view) do
      nil
    else
      parse_workbench_tab(panel, legacy_view)
    end
  end

  def requested_workbench_tab(_), do: nil

  def resolve_default_workbench_tab(requested_tab, interaction_model, chat_enabled?)
      when requested_tab in [
             :chat,
             :interact,
             :messages,
             :events,
             :todos,
             :thread_context,
             :thread_events,
             :instance,
             :sub_agents,
             :tasks,
             :tool_insights,
             :middleware
           ] do
    cond do
      requested_tab == :chat and not chat_enabled? and
          interaction_model[:runner_supported?] == true ->
        :interact

      requested_tab == :chat and not chat_enabled? ->
        interaction_model[:primary_default_tab] || :chat

      true ->
        requested_tab
    end
  end

  def resolve_default_workbench_tab(_requested_tab, interaction_model, chat_enabled?) do
    cond do
      chat_enabled? ->
        :chat

      interaction_model[:runner_supported?] == true ->
        :interact

      true ->
        interaction_model[:primary_default_tab] || :chat
    end
  end

  def empty_interaction_model do
    %{
      signals: [],
      actions: [],
      warnings: [],
      chat_supported?: false,
      runner_supported?: false,
      dispatch_available?: false,
      primary_default_tab: :chat
    }
  end

  def interaction_signals_for_display(%{signals: signals}, show_advanced?)
      when is_list(signals) do
    entry_signals =
      signals
      |> Enum.filter(&(&1[:advanced?] != true))
      |> Enum.sort_by(fn row -> {row[:signal_type] || "", -(row[:priority] || 0)} end)

    advanced_signals =
      signals
      |> Enum.filter(&(&1[:advanced?] == true))
      |> Enum.sort_by(fn row -> {row[:signal_type] || "", -(row[:priority] || 0)} end)

    if show_advanced? do
      entry_signals ++ advanced_signals
    else
      entry_signals
    end
  end

  def interaction_signals_for_display(_, _), do: []

  def interaction_actions_for_display(%{actions: actions}) when is_list(actions), do: actions
  def interaction_actions_for_display(_), do: []

  defdelegate sync_runner_form(existing, interaction_model), to: RunnerState
  defdelegate maybe_apply_payload_template(form, interaction_model, selection), to: RunnerState
  defdelegate payload_template_for_selection(interaction_model, selection), to: RunnerState
  defdelegate payload_template_from_action(action), to: RunnerState
  defdelegate selected_dispatch_ref(socket), to: RunnerState
  defdelegate schema_for_signal(interaction_model, signal_type), to: RunnerState
  defdelegate decode_runner_payload(payload_json), to: RunnerState
  defdelegate normalize_runner_history_entry(result, dispatch_ref), to: RunnerState
  defdelegate prepend_runner_history(history, entry), to: RunnerState
  defdelegate update_interaction_history(history, instance_id, entries), to: RunnerState
  defdelegate current_runner_history(socket, instance_id), to: RunnerState

  defdelegate format_dispatch_error(reason), to: Errors
  defdelegate chat_unavailable_message(reason), to: Errors

  def maybe_subscribe_viewers(socket, active_instances)
      when is_list(active_instances) do
    can_subscribe? =
      Phoenix.LiveView.connected?(socket) and socket.assigns[:live_ops_enabled?] and
        LiveOps.viewer_tracking?()

    if can_subscribe? do
      current = socket.assigns[:viewer_subscriptions] || MapSet.new()

      desired =
        active_instances
        |> Enum.map(&normalize_scope_value(&1[:instance_id]))
        |> Enum.filter(&is_binary/1)
        |> MapSet.new()

      subscriptions_to_add = MapSet.difference(desired, current)
      Enum.each(subscriptions_to_add, &LiveOps.subscribe_viewers/1)

      assign(socket, :viewer_subscriptions, desired)
    else
      assign(socket, :viewer_subscriptions, MapSet.new())
    end
  end

  def maybe_subscribe_viewers(socket, _), do: socket

  def maybe_auto_follow_filtered_instances(socket) do
    filtered_instances = socket.assigns[:filtered_instances] || []
    followed_instance_id = resolve_followed_instance(socket, filtered_instances)
    assign(socket, :followed_instance_id, followed_instance_id)
  end

  def resolve_followed_instance(socket, filtered_instances) when is_list(filtered_instances) do
    followed = normalize_scope_value(socket.assigns[:followed_instance_id])

    cond do
      followed_instance_visible?(filtered_instances, followed) ->
        followed

      socket.assigns[:auto_follow_instances?] == true ->
        filtered_instances
        |> first_auto_follow_match(socket.assigns[:auto_follow_target])
        |> case do
          nil -> nil
          row -> row[:instance_id]
        end

      true ->
        nil
    end
  end

  def resolve_followed_instance(_, _), do: nil

  def followed_instance_visible?(filtered_instances, followed_instance_id)
      when is_list(filtered_instances) and is_binary(followed_instance_id) do
    Enum.any?(filtered_instances, fn row ->
      normalize_scope_value(row[:instance_id]) == followed_instance_id
    end)
  end

  def followed_instance_visible?(_, _), do: false

  def first_auto_follow_match(filtered_instances, target) do
    match = Enum.find(filtered_instances, fn row -> auto_follow_target_match?(row, target) end)

    cond do
      match != nil ->
        match

      auto_follow_target_blank?(target) ->
        List.first(filtered_instances)

      true ->
        nil
    end
  end

  def auto_follow_target_match?(row, target) when is_map(row) and is_map(target) do
    target_instance = normalize_scope_value(target[:instance_id] || target["instance_id"])
    target_project = normalize_scope_value(target[:project_id] || target["project_id"])
    target_user = normalize_scope_value(target[:user_id] || target["user_id"])

    instance_ok =
      is_nil(target_instance) or
        normalize_scope_value(row[:instance_id]) == target_instance

    project_ok =
      is_nil(target_project) or
        normalize_scope_value(row[:project_id]) == target_project

    user_ok = is_nil(target_user) or normalize_scope_value(row[:user_id]) == target_user

    instance_ok and project_ok and user_ok
  end

  def auto_follow_target_match?(_, _), do: true

  def auto_follow_target_blank?(target) when is_map(target) do
    normalize_scope_value(target[:instance_id] || target["instance_id"]) == nil and
      normalize_scope_value(target[:project_id] || target["project_id"]) == nil and
      normalize_scope_value(target[:user_id] || target["user_id"]) == nil
  end

  def auto_follow_target_blank?(_), do: true

  def normalize_auto_follow_target(params, fallback)

  def normalize_auto_follow_target(params, fallback) when is_map(params) do
    base =
      if is_map(fallback) do
        fallback
      else
        %{instance_id: nil, project_id: nil, user_id: nil}
      end

    %{
      instance_id:
        normalize_scope_value(
          Map.get(params, "instance_id", Map.get(params, :instance_id, base[:instance_id]))
        ),
      project_id:
        normalize_scope_value(
          Map.get(params, "project_id", Map.get(params, :project_id, base[:project_id]))
        ),
      user_id:
        normalize_scope_value(
          Map.get(params, "user_id", Map.get(params, :user_id, base[:user_id]))
        )
    }
  end

  def normalize_auto_follow_target(_, fallback) when is_map(fallback), do: fallback

  def normalize_auto_follow_target(_, _),
    do: %{instance_id: nil, project_id: nil, user_id: nil}

  def maybe_track_followed_viewer(socket) do
    can_track? =
      Phoenix.LiveView.connected?(socket) and socket.assigns[:live_ops_enabled?] and
        LiveOps.viewer_tracking?()

    viewer_id = socket.assigns[:viewer_id]
    tracked_instance_id = socket.assigns[:tracked_viewer_instance_id]
    target_instance_id = viewer_target_instance(socket)

    cond do
      not can_track? ->
        socket

      not is_binary(viewer_id) ->
        socket

      is_nil(target_instance_id) and is_binary(tracked_instance_id) ->
        _ = LiveOps.untrack_viewer(tracked_instance_id, viewer_id)
        assign(socket, :tracked_viewer_instance_id, nil)

      target_instance_id == tracked_instance_id ->
        socket

      is_binary(target_instance_id) ->
        if is_binary(tracked_instance_id) do
          _ = LiveOps.untrack_viewer(tracked_instance_id, viewer_id)
        end

        _ = LiveOps.subscribe_viewers(target_instance_id)
        _ = LiveOps.track_viewer(target_instance_id, viewer_id, viewer_metadata(socket))

        assign(socket, :tracked_viewer_instance_id, target_instance_id)

      true ->
        socket
    end
  end

  def viewer_target_instance(socket) do
    cond do
      socket.assigns[:live_action] == :show and is_binary(socket.assigns[:active_instance_id]) ->
        socket.assigns[:active_instance_id]

      socket.assigns[:live_action] == :index and is_binary(socket.assigns[:followed_instance_id]) ->
        socket.assigns[:followed_instance_id]

      true ->
        nil
    end
  end

  def viewer_metadata(socket) do
    %{
      path: socket.assigns[:current_path] || "",
      panel: socket.assigns[:workbench_tab] || :chat,
      timezone: socket.assigns[:user_timezone] || "UTC"
    }
  end

  def maybe_load_subagent_events(socket, nil), do: assign(socket, :subagent_events, %{})

  def maybe_load_subagent_events(socket, subagent_id) when is_binary(subagent_id) do
    trace_id =
      socket.assigns[:instance_event_stream]
      |> List.wrap()
      |> Enum.find_value(fn event -> normalize_scope_value(event[:trace_id]) end) ||
        socket.assigns[:instance_observability_events]
        |> List.wrap()
        |> Enum.find_value(fn event -> normalize_scope_value(event[:trace_id]) end)

    events =
      if Delegation.enabled?() and is_binary(trace_id) do
        Delegation.list_subagent_events(trace_id, subagent_id, limit: 240)
      else
        []
      end

    assign(socket, :subagent_events, %{subagent_id => events})
  end

  defdelegate normalize_scope_filters(scope_params), to: ScopeHelpers
  defdelegate merge_scope_filters(existing, scope_params), to: ScopeHelpers
  defdelegate normalize_scope_value(value), to: ScopeHelpers
  defdelegate filter_agents_by_scope(agents, scope_filters), to: ScopeHelpers
  defdelegate scope_candidate_instance_ids(scope_filters), to: ScopeHelpers
  defdelegate scope_filters_match?(event_scope, scope_filters), to: ScopeHelpers

  def infer_debug_level(false, _current), do: "off"
  def infer_debug_level(true, "verbose"), do: "verbose"
  def infer_debug_level(true, _), do: "on"

  def normalize_debug_level(level, true) when level in ["on", "verbose"], do: level
  def normalize_debug_level(_level, true), do: "on"
  def normalize_debug_level(_level, false), do: "off"

  def debug_level_button_class(active?) do
    if active? do
      "inline-flex items-center rounded-md px-2.5 py-1 text-xs border border-js-info/30 bg-js-info/15 text-js-info"
    else
      "inline-flex items-center rounded-md px-2.5 py-1 text-xs border border-js-border text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
    end
  end

  def task_badge_variant("error"), do: :error
  def task_badge_variant(:error), do: :error
  def task_badge_variant("ok"), do: :success
  def task_badge_variant(:ok), do: :success
  def task_badge_variant("running"), do: :info
  def task_badge_variant(:running), do: :info
  def task_badge_variant(_), do: :default

  defdelegate workbench_sections(), to: Contracts
  defdelegate parse_instance_section(section), to: Contracts
  defdelegate section_query_value(section), to: Contracts
  defdelegate default_workbench_tab_for_section(section), to: Contracts
  defdelegate workbench_tabs_for_section(section), to: Contracts
  defdelegate section_description(section), to: Contracts
  defdelegate workbench_tab_in_section?(tab, section), to: Contracts
  defdelegate section_for_workbench_tab(tab), to: Contracts

  def workbench_tab_button_class(active?) do
    base = "js-instance-menu-tab"
    if active?, do: "#{base} is-active", else: base
  end

  def workbench_section_button_class(active?) do
    base = "js-instance-menu-section"
    if active?, do: "#{base} is-active", else: base
  end

  def workbench_grid_class(true) do
    "grid grid-cols-1 gap-2 md:grid-cols-[180px_minmax(0,1fr)] md:grid-rows-[minmax(0,1fr)_minmax(0,1fr)] lg:min-h-0 lg:grid-cols-[190px_minmax(0,1fr)_280px] lg:grid-rows-[minmax(0,1fr)] xl:grid-cols-[200px_minmax(0,1fr)_300px]"
  end

  def workbench_grid_class(false) do
    "grid grid-cols-1 gap-2 md:grid-cols-[180px_minmax(0,1fr)] lg:grid-cols-[200px_minmax(0,1fr)] lg:min-h-0"
  end

  def workbench_threads_rail_class(true), do: "md:row-span-2 lg:row-span-1"
  def workbench_threads_rail_class(false), do: nil

  defdelegate parse_workbench_tab(panel, legacy_view \\ nil), to: Contracts
  defdelegate panel_query_value(panel), to: Contracts
  defdelegate tab_query_value(tab), to: Contracts
  defdelegate workbench_section_path(prefix, agent, instance_id, section), to: Routes
  defdelegate workbench_path(prefix, agent, instance_id, panel, tab, section \\ nil), to: Routes

  def thread_context_sections(
        sections_by_tab,
        persisted_contexts,
        active_thread_id,
        instance_online?
      )
      when is_map(sections_by_tab) do
    context = Map.get(sections_by_tab, :context, [])
    reasoning = Map.get(sections_by_tab, :reasoning, [])
    overview = Map.get(sections_by_tab, :overview, [])

    persisted =
      persisted_thread_context_sections(persisted_contexts, active_thread_id, instance_online?)

    sections = context ++ reasoning ++ overview ++ persisted

    if sections == [], do: [], else: sections
  end

  def thread_context_sections(_, persisted_contexts, active_thread_id, instance_online?) do
    persisted_thread_context_sections(persisted_contexts, active_thread_id, instance_online?)
  end

  def persisted_thread_context_sections(contexts, active_thread_id, instance_online?) do
    with true <- is_map(contexts),
         true <- is_binary(active_thread_id),
         %{} = snapshot <- Map.get(contexts, active_thread_id) do
      summary_rows =
        [
          {"Source",
           if(instance_online?,
             do: "Persisted snapshot (live available)",
             else: "Persisted snapshot (instance offline)"
           )},
          {"Captured At", format_event_timestamp(Map.get(snapshot, :captured_at))},
          {"Status", to_string(Map.get(snapshot, :status, "unknown"))},
          {"Strategy Thread", to_string(Map.get(snapshot, :strategy_thread_id, "n/a"))},
          {"Iteration", to_string(Map.get(snapshot, :iteration, 0))},
          {"Conversation", to_string(Map.get(snapshot, :conversation_count, 0))},
          {"Pending Tool Calls", to_string(Map.get(snapshot, :pending_tool_calls_count, 0))},
          {"Thinking Blocks", to_string(Map.get(snapshot, :thinking_blocks_count, 0))},
          {"Termination", to_string(Map.get(snapshot, :termination_reason, "n/a"))},
          {"Model", to_string(Map.get(snapshot, :model, "n/a"))}
        ]

      sections = [
        %{title: "Persisted Context Snapshot", kind: :kv, data: summary_rows, variant: :warning}
      ]

      case Map.get(snapshot, :strategy_state) do
        %{} = strategy_state ->
          sections ++
            [
              %{
                title: "Persisted Strategy State",
                kind: :code,
                data: inspect(strategy_state, pretty: true, limit: 120, printable_limit: 20_000),
                variant: :default
              }
            ]

        _ ->
          sections
      end
    else
      _ -> []
    end
  end

  def active_strategy_thread_id(%{raw_state: raw_state}) when is_map(raw_state) do
    raw_state
    |> Map.get(:__strategy__, %{})
    |> Map.get(:thread, %{})
    |> Map.get(:id)
  end

  def active_strategy_thread_id(_), do: nil

  defdelegate thread_events_for_display(events, thread_id, query, limit), to: EventHelpers
  defdelegate instance_events_for_display(events, query, limit), to: EventHelpers
  defdelegate build_instance_event_stream(events, limit), to: EventHelpers
  defdelegate event_stream_row(key, event), to: EventHelpers
  defdelegate merge_event_stream_rows(existing, event), to: EventHelpers
  defdelegate event_stream_sort_key(row), to: EventHelpers
  defdelegate event_merge_key(event), to: EventHelpers
  defdelegate sanitize_expanded_event_ids(expanded_event_ids, event_stream), to: EventHelpers
  defdelegate runtime_todos_for_display(runtime_status, tasks), to: EventHelpers
  defdelegate fallback_todos_from_tasks(tasks), to: EventHelpers
  defdelegate todo_status_from_task(status), to: EventHelpers
  defdelegate todo_badge_variant(status), to: EventHelpers
  defdelegate normalize_non_negative_int(value, default), to: EventHelpers
  defdelegate event_thread_id(event), to: EventHelpers
  defdelegate filter_events_by_query(events, query), to: EventHelpers
  defdelegate normalize_optional_query(query), to: EventHelpers
  defdelegate normalize_thread_event_limit(limit), to: EventHelpers

  def ordered_detail_tabs(tabs) when is_list(tabs) do
    desired = [:overview, :reasoning, :context, :weather, :model, :memory, :tracing]

    sorted =
      tabs
      |> Enum.sort_by(fn tab ->
        case Enum.find_index(desired, &(&1 == tab.id)) do
          nil -> 1_000
          idx -> idx
        end
      end)

    if sorted == [], do: [%{id: :overview, label: "Overview"}], else: sorted
  end

  def ordered_detail_tabs(_), do: [%{id: :overview, label: "Overview"}]

  def summary_meta(runtime_status, model_label) do
    details =
      (runtime_status && runtime_status.snapshot && runtime_status.snapshot.details) || %{}

    status = runtime_status && runtime_status.snapshot && runtime_status.snapshot.status

    [
      {"Status", summary_status_label(status), summary_status_variant(status)},
      {"Model", to_string(model_label || "n/a"), :info},
      {"Iteration", to_string(details[:iteration] || 0), :default},
      {"Tool Calls", to_string(length(details[:tool_calls] || [])), :default},
      {"Turns", to_string(length(details[:conversation] || [])), :default}
    ]
  end

  def summary_status_label(status) do
    status = if is_nil(status), do: :offline, else: status

    status
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  def summary_status_variant(:running), do: :success
  def summary_status_variant(:success), do: :success
  def summary_status_variant(:error), do: :error
  def summary_status_variant(_), do: :default

  def default_start_form(schema) do
    Enum.reduce(schema, %{}, fn field, acc ->
      Map.put(acc, field.name, default_field_value(field))
    end)
  end

  def normalize_start_form(form, schema) do
    defaults = default_start_form(schema)

    Enum.reduce(schema, defaults, fn field, acc ->
      key = field.name
      raw = Map.get(form, key)
      Map.put(acc, key, normalize_field_value(field, raw))
    end)
  end

  def default_field_value(%{type: :checkbox} = field) do
    if Map.get(field, :default, "false") in ["true", "on", "1"], do: "true", else: "false"
  end

  def default_field_value(field), do: Map.get(field, :default, "")

  def normalize_field_value(%{type: :checkbox}, raw) do
    if raw in ["true", "on", "1"], do: "true", else: "false"
  end

  def normalize_field_value(_field, raw), do: to_string(raw || "") |> String.trim()

  def build_start_opts(form) do
    instance_id = form["instance_id"] |> to_string() |> String.trim()
    debug? = form["debug"] == "true"

    with {:ok, initial_state} <- parse_initial_state(form["initial_state_json"]) do
      opts = []
      opts = if instance_id == "", do: opts, else: [{:id, instance_id} | opts]
      opts = if debug?, do: [{:debug, true} | opts], else: opts
      opts = if initial_state == %{}, do: opts, else: [{:initial_state, initial_state} | opts]
      {:ok, Enum.reverse(opts)}
    end
  end

  def parse_initial_state(nil), do: {:ok, %{}}
  def parse_initial_state(""), do: {:ok, %{}}

  def parse_initial_state(raw_json) when is_binary(raw_json) do
    json = String.trim(raw_json)

    if json == "" do
      {:ok, %{}}
    else
      case Jason.decode(json) do
        {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
        {:ok, _other} -> {:error, "Initial state JSON must decode to an object/map."}
        {:error, error} -> {:error, "Invalid initial state JSON: #{Exception.message(error)}"}
      end
    end
  end

  def parse_initial_state(_), do: {:error, "Initial state must be valid JSON."}

  def resolve_instance_id(_jido_instance, pid, _opts) when is_pid(pid) do
    with {:ok, state} <- Jido.AgentServer.state(pid),
         id when is_binary(id) <- state.id do
      {:ok, id}
    else
      _ -> {:error, "Started instance but failed to resolve instance ID."}
    end
  rescue
    _ -> {:error, "Started instance but failed to resolve instance ID."}
  end

  def format_start_error(reason) when is_binary(reason), do: reason
  def format_start_error(reason), do: "Failed to start agent instance: #{inspect(reason)}"

  def start_field_id(name) when is_binary(name) do
    "start-" <>
      (name
       |> String.downcase()
       |> String.replace(~r/[^a-z0-9]+/, "-")
       |> String.trim("-"))
  end

  def now_ms, do: System.system_time(:millisecond)

  def humanize_agent_name(name), do: Naming.humanize(name)
end
