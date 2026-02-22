defmodule JidoStudio.Live.AgentsLive.Support do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias JidoStudio.AgentInteractions
  alias JidoStudio.Agents.InstanceIndex
  alias JidoStudio.Agents.MessageSnapshot
  alias JidoStudio.Agents.RunnerForm
  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Delegation
  alias JidoStudio.LiveOps
  alias JidoStudio.Naming
  alias JidoStudio.TraceBuffer

  def viewer_id do
    "studio-viewer-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  def event_metadata_value(event, key) when is_map(event) do
    metadata = Map.get(event, :metadata, %{})
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  def event_metadata_value(_event, _key), do: nil

  def format_event_name(event) when is_map(event) do
    cond do
      is_binary(event[:event_name]) ->
        event[:event_name]

      is_list(event[:event_prefix]) ->
        Enum.join(event[:event_prefix], ".")

      true ->
        "event"
    end
  end

  def format_event_name(_), do: "event"

  def format_event_timestamp(ts) when is_integer(ts) do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  def format_event_timestamp(_), do: "--:--:--"

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

  def sync_runner_form(%RunnerForm{} = existing, interaction_model) do
    signals = interaction_model[:signals] || []
    actions = interaction_model[:actions] || []

    selected_signal_ok? =
      is_binary(existing.selected_signal_key) and
        Enum.any?(signals, &(&1[:key] == existing.selected_signal_key))

    selected_action_ok? =
      is_binary(existing.selected_action_key) and
        Enum.any?(actions, &(&1[:key] == existing.selected_action_key))

    cond do
      selected_signal_ok? or selected_action_ok? ->
        existing

      signals != [] ->
        existing
        |> RunnerForm.select_signal(hd(signals)[:key])
        |> maybe_apply_payload_template(interaction_model, {:signal, hd(signals)[:key]})

      actions != [] ->
        existing
        |> RunnerForm.select_action(hd(actions)[:key])
        |> maybe_apply_payload_template(interaction_model, {:action, hd(actions)[:key]})

      true ->
        RunnerForm.new()
    end
  end

  def sync_runner_form(_, interaction_model) do
    sync_runner_form(RunnerForm.new(), interaction_model)
  end

  def maybe_apply_payload_template(%RunnerForm{} = form, interaction_model, selection) do
    template = payload_template_for_selection(interaction_model, selection)

    if form.payload_json in [nil, "", "{}"] and template not in [nil, "{}", ""] do
      RunnerForm.parse(%{"payload_json" => template}, form)
    else
      form
    end
  end

  def payload_template_for_selection(interaction_model, {:signal, key}) do
    signals = interaction_model[:signals] || []
    signal = Enum.find(signals, &(&1[:key] == key))

    action =
      if signal do
        actions = interaction_model[:actions] || []
        Enum.find(actions, &(&1[:primary_signal_type] == signal[:signal_type]))
      else
        nil
      end

    payload_template_from_action(action)
  end

  def payload_template_for_selection(interaction_model, {:action, key}) do
    action = Enum.find(interaction_model[:actions] || [], &(&1[:key] == key))
    payload_template_from_action(action)
  end

  def payload_template_for_selection(_, _), do: "{}"

  def payload_template_from_action(nil), do: "{}"

  def payload_template_from_action(%{required_fields: fields}) when is_list(fields) do
    fields
    |> Enum.reduce(%{}, fn field, acc -> Map.put(acc, field, "<value>") end)
    |> Jason.encode!()
  rescue
    _ -> "{}"
  end

  def payload_template_from_action(_), do: "{}"

  def selected_dispatch_ref(socket) do
    case RunnerForm.selected_target(socket.assigns.runner_form) do
      {:signal, key} ->
        signal =
          socket.assigns.interaction_model.signals
          |> List.wrap()
          |> Enum.find(&(&1[:key] == key))

        if is_map(signal) do
          {:ok,
           %{
             kind: :signal,
             signal_type: signal[:signal_type],
             source: "/jido_studio/interact",
             schema: schema_for_signal(socket.assigns.interaction_model, signal[:signal_type])
           }}
        else
          {:error, :signal_not_found}
        end

      {:action, key} ->
        action =
          socket.assigns.interaction_model.actions
          |> List.wrap()
          |> Enum.find(&(&1[:key] == key))

        if is_map(action) and is_binary(action[:primary_signal_type]) do
          {:ok,
           %{
             kind: :action,
             primary_signal_type: action[:primary_signal_type],
             source: "/jido_studio/interact",
             schema: action[:schema]
           }}
        else
          {:error, :action_not_dispatchable}
        end

      _ ->
        {:error, :no_target_selected}
    end
  end

  def schema_for_signal(interaction_model, signal_type) when is_binary(signal_type) do
    interaction_model[:actions]
    |> List.wrap()
    |> Enum.find(&(&1[:primary_signal_type] == signal_type))
    |> case do
      %{schema: schema} -> schema
      _ -> nil
    end
  end

  def schema_for_signal(_, _), do: nil

  def decode_runner_payload(payload_json) when is_binary(payload_json) do
    case Jason.decode(payload_json) do
      {:ok, %{} = payload} -> {:ok, payload}
      {:ok, _other} -> {:error, :payload_must_be_json_object}
      {:error, error} -> {:error, {:invalid_json, Exception.message(error)}}
    end
  end

  def decode_runner_payload(_), do: {:error, :payload_must_be_json_object}

  def normalize_runner_history_entry(result, dispatch_ref) when is_map(result) do
    %{
      timestamp_ms: result[:timestamp_ms] || System.system_time(:millisecond),
      mode: result[:mode] || :sync,
      signal_type: dispatch_ref[:signal_type] || dispatch_ref[:primary_signal_type] || "unknown",
      status:
        result
        |> get_in([:result, :status])
        |> case do
          nil -> :ok
          value -> value
        end
    }
  end

  def normalize_runner_history_entry(_result, dispatch_ref) do
    %{
      timestamp_ms: System.system_time(:millisecond),
      mode: :sync,
      signal_type: dispatch_ref[:signal_type] || dispatch_ref[:primary_signal_type] || "unknown",
      status: :ok
    }
  end

  def prepend_runner_history(history, entry) do
    limit = AgentInteractions.runner_history_limit()
    [entry | List.wrap(history)] |> Enum.take(limit)
  end

  def update_interaction_history(history, instance_id, entries)
      when is_map(history) and is_binary(instance_id) do
    Map.put(history, instance_id, List.wrap(entries))
  end

  def update_interaction_history(history, _instance_id, _entries) when is_map(history),
    do: history

  def update_interaction_history(_, _instance_id, _entries), do: %{}

  def current_runner_history(socket, instance_id) when is_binary(instance_id) do
    socket.assigns[:interaction_history]
    |> case do
      history when is_map(history) -> Map.get(history, instance_id, [])
      _ -> []
    end
  end

  def current_runner_history(_, _), do: []

  def format_dispatch_error({:invalid_json, message}), do: "Invalid JSON: " <> message

  def format_dispatch_error({:payload_validation_failed, reason}),
    do: "Payload validation failed: " <> inspect(reason)

  def format_dispatch_error(reason), do: inspect(reason)

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

  def normalize_scope_filters(scope_params) when is_map(scope_params) do
    %{
      project_id: normalize_scope_value(scope_params["project_id"] || scope_params[:project_id]),
      user_id: normalize_scope_value(scope_params["user_id"] || scope_params[:user_id]),
      agent_id: normalize_scope_value(scope_params["agent_id"] || scope_params[:agent_id])
    }
  end

  def normalize_scope_filters(_), do: %{project_id: nil, user_id: nil, agent_id: nil}

  def merge_scope_filters(existing, nil) when is_map(existing), do: existing

  def merge_scope_filters(existing, scope_params) when is_map(existing) do
    incoming = normalize_scope_filters(scope_params)

    if incoming.project_id || incoming.user_id || incoming.agent_id do
      incoming
    else
      existing
    end
  end

  def merge_scope_filters(_, scope_params), do: normalize_scope_filters(scope_params)

  def normalize_scope_value(nil), do: nil

  def normalize_scope_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_scope_value(value) when is_atom(value), do: Atom.to_string(value)
  def normalize_scope_value(_), do: nil

  def filter_agents_by_scope(agents, nil), do: agents

  def filter_agents_by_scope(agents, scope_filters)
      when is_list(agents) and is_map(scope_filters) do
    agent_id_query = normalize_scope_value(scope_filters.agent_id)
    scoped_instance_ids = scope_candidate_instance_ids(scope_filters)

    Enum.filter(agents, fn agent ->
      running_instances = agent.running_instances || []
      instance_ids = Enum.map(running_instances, &to_string(&1.id))

      agent_match? =
        case agent_id_query do
          nil ->
            true

          query ->
            String.contains?(String.downcase(agent.slug || ""), String.downcase(query)) or
              String.contains?(String.downcase(agent.name || ""), String.downcase(query)) or
              Enum.any?(
                instance_ids,
                &String.contains?(String.downcase(&1), String.downcase(query))
              )
        end

      scope_match? =
        case scoped_instance_ids do
          :all ->
            true

          ids when is_struct(ids, MapSet) ->
            if MapSet.size(ids) > 0 do
              Enum.any?(instance_ids, &MapSet.member?(ids, &1))
            else
              false
            end

          _ ->
            true
        end

      agent_match? and scope_match?
    end)
  end

  def filter_agents_by_scope(agents, _), do: agents

  def scope_candidate_instance_ids(scope_filters) do
    project_id = normalize_scope_value(scope_filters.project_id)
    user_id = normalize_scope_value(scope_filters.user_id)

    if is_nil(project_id) and is_nil(user_id) do
      :all
    else
      TraceBuffer.events(2_000)
      |> Enum.reduce(MapSet.new(), fn event, acc ->
        scope = event[:scope] || event[:metadata] || %{}
        event_project_id = scope[:project_id] || scope["project_id"]
        event_user_id = scope[:user_id] || scope["user_id"]
        agent_id = event[:agent_id] || event[:instance_id]

        project_ok = is_nil(project_id) or to_string(event_project_id) == project_id
        user_ok = is_nil(user_id) or to_string(event_user_id) == user_id

        if project_ok and user_ok and is_binary(agent_id) do
          MapSet.put(acc, agent_id)
        else
          acc
        end
      end)
    end
  end

  def scope_filters_match?(_event_scope, nil), do: true

  def scope_filters_match?(event_scope, scope_filters) when is_map(scope_filters) do
    scope =
      cond do
        is_map(event_scope) -> event_scope
        is_list(event_scope) -> Map.new(event_scope)
        true -> %{}
      end

    project_id = normalize_scope_value(scope_filters.project_id)
    user_id = normalize_scope_value(scope_filters.user_id)

    project_ok =
      is_nil(project_id) or to_string(scope[:project_id] || scope["project_id"]) == project_id

    user_ok = is_nil(user_id) or to_string(scope[:user_id] || scope["user_id"]) == user_id
    project_ok and user_ok
  end

  def scope_filters_match?(_, _), do: true

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

  @workbench_sections [
    %{
      id: :play,
      label: "Play",
      default_tab: :chat,
      tabs: [
        %{id: :chat, label: "Chat"},
        %{id: :interact, label: "Interact"},
        %{id: :messages, label: "Messages"}
      ]
    },
    %{
      id: :observe,
      label: "Observe",
      default_tab: :events,
      tabs: [
        %{id: :events, label: "Events"},
        %{id: :todos, label: "TODOs"},
        %{id: :thread_context, label: "Thread Context"},
        %{id: :thread_events, label: "Thread Events"}
      ]
    },
    %{
      id: :configure,
      label: "Configure",
      default_tab: :instance,
      tabs: [
        %{id: :instance, label: "Instance"},
        %{id: :sub_agents, label: "Sub-Agents"},
        %{id: :tasks, label: "Tasks"},
        %{id: :tool_insights, label: "Tool Insights"},
        %{id: :middleware, label: "Middleware"}
      ]
    }
  ]

  @workbench_tab_order [
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
  ]

  @workbench_tabs_by_section Enum.reduce(@workbench_sections, %{}, fn section, acc ->
                               Enum.reduce(section.tabs, acc, fn tab, inner ->
                                 Map.put(inner, tab.id, section.id)
                               end)
                             end)

  def workbench_sections, do: @workbench_sections

  def parse_instance_section(section)

  def parse_instance_section(section) when section in [:play, :observe, :configure], do: section
  def parse_instance_section("play"), do: :play
  def parse_instance_section("observe"), do: :observe
  def parse_instance_section("configure"), do: :configure
  def parse_instance_section(_), do: :play

  def section_query_value(:play), do: "play"
  def section_query_value(:observe), do: "observe"
  def section_query_value(:configure), do: "configure"
  def section_query_value(_), do: "play"

  def default_workbench_tab_for_section(section) do
    section =
      section
      |> parse_instance_section()

    section =
      Enum.find(@workbench_sections, &(&1.id == section)) ||
        Enum.find(@workbench_sections, &(&1.id == :play))

    section.default_tab
  end

  def workbench_tabs_for_section(section) do
    section =
      section
      |> parse_instance_section()

    section =
      Enum.find(@workbench_sections, &(&1.id == section)) ||
        Enum.find(@workbench_sections, &(&1.id == :play))

    section.tabs
  end

  def section_description(:play), do: "Try interactions and send messages."
  def section_description(:observe), do: "Track events, TODOs, and runtime flow."
  def section_description(:configure), do: "Inspect instance details and tools."
  def section_description(_), do: "Inspect and operate this instance."

  def workbench_tab_in_section?(tab, section) do
    tab = parse_workbench_tab(tab)

    section
    |> workbench_tabs_for_section()
    |> Enum.any?(&(&1.id == tab))
  end

  def section_for_workbench_tab(tab) do
    tab = parse_workbench_tab(tab)
    Map.get(@workbench_tabs_by_section, tab, :play)
  end

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

  def parse_workbench_tab(panel, legacy_view \\ nil)

  def parse_workbench_tab(panel, _legacy_view)
      when panel in @workbench_tab_order,
      do: panel

  def parse_workbench_tab("chat", _legacy_view), do: :chat
  def parse_workbench_tab("interact", _legacy_view), do: :interact
  def parse_workbench_tab("messages", _legacy_view), do: :messages
  def parse_workbench_tab("events", _legacy_view), do: :events
  def parse_workbench_tab("todos", _legacy_view), do: :todos
  def parse_workbench_tab("thread_context", _legacy_view), do: :thread_context
  def parse_workbench_tab("context", _legacy_view), do: :thread_context
  def parse_workbench_tab("thread_events", _legacy_view), do: :thread_events
  def parse_workbench_tab("thread_events_legacy", _legacy_view), do: :thread_events
  def parse_workbench_tab("instance", _legacy_view), do: :instance
  def parse_workbench_tab("sub_agents", _legacy_view), do: :sub_agents
  def parse_workbench_tab("tasks", _legacy_view), do: :tasks
  def parse_workbench_tab("tool_insights", _legacy_view), do: :tool_insights
  def parse_workbench_tab("middleware", _legacy_view), do: :middleware
  def parse_workbench_tab(_, "inspect"), do: :instance
  def parse_workbench_tab(_, :inspect), do: :instance
  def parse_workbench_tab(_, _), do: :chat

  def workbench_section_path(prefix, agent, instance_id, section) do
    section =
      section
      |> parse_instance_section()
      |> section_query_value()

    path = "#{prefix}/agents/#{agent.slug}/#{URI.encode_www_form(instance_id)}/#{section}"
    Scope.with_scope_query(path, Scope.current_node_param())
  end

  def workbench_path(prefix, agent, instance_id, panel, tab, section \\ nil) do
    panel = parse_workbench_tab(panel)
    section = parse_instance_section(section || section_for_workbench_tab(panel))
    default_panel = default_workbench_tab_for_section(section)
    base = workbench_section_path(prefix, agent, instance_id, section)
    panel_value = panel_query_value(panel)
    tab_value = tab_query_value(tab)

    params =
      if(panel != default_panel, do: [{"panel", panel_value}], else: []) ++
        if(panel == :instance and is_binary(tab_value), do: [{"tab", tab_value}], else: [])

    query =
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> URI.encode_query()

    if query == "" do
      base
    else
      separator = if String.contains?(base, "?"), do: "&", else: "?"
      "#{base}#{separator}#{query}"
    end
  end

  def panel_query_value(:chat), do: "chat"
  def panel_query_value(:interact), do: "interact"
  def panel_query_value(:messages), do: "messages"
  def panel_query_value(:events), do: "events"
  def panel_query_value(:todos), do: "todos"
  def panel_query_value(:thread_context), do: "thread_context"
  def panel_query_value(:thread_events), do: "thread_events"
  def panel_query_value(:instance), do: "instance"
  def panel_query_value(:sub_agents), do: "sub_agents"
  def panel_query_value(:tasks), do: "tasks"
  def panel_query_value(:tool_insights), do: "tool_insights"
  def panel_query_value(:middleware), do: "middleware"
  def panel_query_value(_), do: "chat"

  def tab_query_value(tab) when is_atom(tab), do: Atom.to_string(tab)
  def tab_query_value(tab) when is_binary(tab) and tab != "", do: tab
  def tab_query_value(_), do: nil

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

  def thread_events_for_display(events, thread_id, query, limit) when is_list(events) do
    filtered =
      if is_binary(thread_id) and thread_id != "" do
        Enum.filter(events, fn event ->
          case event_thread_id(event) do
            nil -> false
            value -> value == thread_id
          end
        end)
      else
        []
      end

    selected =
      cond do
        filtered != [] -> filtered
        true -> events
      end

    selected
    |> filter_events_by_query(query)
    |> Enum.take(normalize_thread_event_limit(limit))
  end

  def thread_events_for_display(_, _, _, _), do: []

  def instance_events_for_display(events, query, limit) when is_list(events) do
    events
    |> filter_events_by_query(query)
    |> Enum.take(normalize_thread_event_limit(limit))
  end

  def instance_events_for_display(_, _, _), do: []

  def build_instance_event_stream(events, limit) when is_list(events) do
    events
    |> Enum.reduce(%{}, fn event, acc ->
      key = event_merge_key(event)

      Map.update(acc, key, event_stream_row(key, event), fn existing ->
        merge_event_stream_rows(existing, event)
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(&event_stream_sort_key/1, :desc)
    |> Enum.take(normalize_thread_event_limit(limit))
  end

  def build_instance_event_stream(_, _), do: []

  def event_stream_row(key, event) do
    %{
      id: key,
      timestamp_ms: event[:timestamp_ms],
      event_name: event[:event_name],
      type: event[:type],
      source: event[:source],
      metadata: event[:metadata] || %{},
      measurements: event[:measurements] || %{},
      trace_id: event[:trace_id],
      span_id: event[:span_id],
      call_id: event[:call_id] || event_metadata_value(event, :call_id),
      task_id: event[:task_id] || event_metadata_value(event, :task_id),
      chunk_count: 1,
      raw: [event]
    }
  end

  def merge_event_stream_rows(existing, event) do
    latest =
      cond do
        is_integer(event[:timestamp_ms]) and is_integer(existing[:timestamp_ms]) ->
          if event[:timestamp_ms] >= existing[:timestamp_ms],
            do: event,
            else: hd(existing[:raw] || [event])

        is_integer(event[:timestamp_ms]) ->
          event

        true ->
          hd(existing[:raw] || [event])
      end

    %{
      existing
      | timestamp_ms: latest[:timestamp_ms] || existing[:timestamp_ms],
        event_name: latest[:event_name] || existing[:event_name],
        type: latest[:type] || existing[:type],
        source: latest[:source] || existing[:source],
        metadata: latest[:metadata] || existing[:metadata],
        measurements: latest[:measurements] || existing[:measurements],
        trace_id: latest[:trace_id] || existing[:trace_id],
        span_id: latest[:span_id] || existing[:span_id],
        call_id: latest[:call_id] || existing[:call_id],
        task_id: latest[:task_id] || existing[:task_id],
        chunk_count: normalize_non_negative_int(existing[:chunk_count], 1) + 1,
        raw: [event | List.wrap(existing[:raw])]
    }
  end

  def event_stream_sort_key(row) do
    {row[:timestamp_ms] || 0, to_string(row[:id] || "")}
  end

  def event_merge_key(event) when is_map(event) do
    call_id = normalize_scope_value(event[:call_id] || event_metadata_value(event, :call_id))
    span_id = normalize_scope_value(event[:span_id])
    event_name = to_string(event[:event_name] || event[:type] || "event")
    chunk_key = normalize_scope_value(event_metadata_value(event, :chunk_id))

    cond do
      is_binary(call_id) and is_binary(chunk_key) ->
        "call:" <> call_id <> ":" <> event_name <> ":" <> chunk_key

      is_binary(call_id) ->
        "call:" <> call_id <> ":" <> event_name

      is_binary(chunk_key) ->
        "chunk:" <> chunk_key <> ":" <> event_name

      is_binary(span_id) ->
        "span:" <> span_id <> ":" <> event_name

      true ->
        "event:" <>
          Integer.to_string(event[:timestamp_ms] || 0) <>
          ":" <> Integer.to_string(:erlang.phash2(event))
    end
  end

  def event_merge_key(_), do: "event:unknown"

  def sanitize_expanded_event_ids(expanded_event_ids, event_stream) do
    valid_ids =
      event_stream
      |> List.wrap()
      |> Enum.map(&to_string(&1[:id]))
      |> MapSet.new()

    expanded_event_ids
    |> case do
      %MapSet{} = existing -> existing
      _ -> MapSet.new()
    end
    |> Enum.reduce(MapSet.new(), fn id, acc ->
      id = to_string(id)
      if MapSet.member?(valid_ids, id), do: MapSet.put(acc, id), else: acc
    end)
  end

  def runtime_todos_for_display(runtime_status, tasks) do
    todos = MessageSnapshot.todos(runtime_status)

    if todos == [] do
      fallback_todos_from_tasks(tasks)
    else
      todos
    end
  end

  def fallback_todos_from_tasks(tasks) when is_list(tasks) do
    tasks
    |> Enum.take(50)
    |> Enum.with_index(1)
    |> Enum.map(fn {task, idx} ->
      %{
        id: normalize_scope_value(task[:task_id]) || Integer.to_string(idx),
        content:
          "Task " <>
            to_string(task[:task_id] || "unknown") <>
            " (" <> to_string(task[:task_status] || task[:status] || "running") <> ")",
        status: todo_status_from_task(task[:task_status] || task[:status]),
        active_form: normalize_scope_value(task[:trace_id])
      }
    end)
  end

  def fallback_todos_from_tasks(_), do: []

  def todo_status_from_task(status) when status in ["ok", :ok, "completed", :completed],
    do: :completed

  def todo_status_from_task(status) when status in ["error", :error], do: :error
  def todo_status_from_task(status) when status in ["running", :running], do: :in_progress
  def todo_status_from_task(_), do: :pending

  def todo_badge_variant(:completed), do: :success
  def todo_badge_variant(:in_progress), do: :info
  def todo_badge_variant(:error), do: :error
  def todo_badge_variant(_), do: :default

  def normalize_non_negative_int(value, _default) when is_integer(value) and value >= 0,
    do: value

  def normalize_non_negative_int(_value, default), do: default

  def event_thread_id(event) when is_map(event) do
    metadata = Map.get(event, :metadata, %{})
    Map.get(metadata, :thread_id) || Map.get(metadata, "thread_id")
  end

  def event_thread_id(_), do: nil

  def filter_events_by_query(events, query) when is_list(events) do
    case normalize_optional_query(query) do
      nil ->
        events

      normalized ->
        Enum.filter(events, fn event ->
          haystack =
            [
              format_event_name(event),
              inspect(event[:metadata] || %{}, limit: 5),
              to_string(event[:type] || ""),
              to_string(event[:source] || ""),
              to_string(event[:trace_id] || ""),
              to_string(event[:span_id] || "")
            ]
            |> Enum.join(" ")
            |> String.downcase()

          String.contains?(haystack, normalized)
        end)
    end
  end

  def filter_events_by_query(events, _), do: events

  def normalize_optional_query(query) when is_binary(query) do
    query
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      value -> value
    end
  end

  def normalize_optional_query(_), do: nil

  def normalize_thread_event_limit(value) when is_integer(value) and value > 0, do: value
  def normalize_thread_event_limit(_), do: 200

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
