defmodule JidoStudio.Live.AgentsLive.ObservabilityState do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias JidoStudio.AgentInteractions
  alias JidoStudio.Agents.Introspection
  alias JidoStudio.Agents.RunnerForm
  alias JidoStudio.Agents.MessageSnapshot
  alias JidoStudio.Delegation
  alias JidoStudio.Live.AgentsLive.Support
  alias JidoStudio.Live.AgentsLive.ShowState
  alias JidoStudio.Observability
  alias JidoStudio.Presenters.Default
  alias JidoStudio.TraceBuffer

  def enrich_tool_events([], _instance_id, _traces_path), do: []

  def enrich_tool_events(tool_events, instance_id, traces_path) when is_list(tool_events) do
    telemetry =
      if is_binary(instance_id) do
        TraceBuffer.events_for_instance(instance_id, 500)
      else
        []
      end

    telemetry_by_call_id =
      Enum.reduce(telemetry, %{}, fn event, acc ->
        call_id = Support.event_metadata_value(event, :call_id)

        if is_binary(call_id) and call_id != "" do
          Map.update(acc, call_id, [event], fn existing -> [event | existing] end)
        else
          acc
        end
      end)

    Enum.map(tool_events, fn tool_event ->
      call_id = Map.get(tool_event, :call_id) || Map.get(tool_event, :id)
      related_events = Map.get(telemetry_by_call_id, call_id, [])
      telemetry_summary = summarize_tool_telemetry(related_events)
      trace_id = telemetry_summary.trace_id

      tool_event
      |> Map.put(:call_id, call_id)
      |> Map.put(:duration_ms, telemetry_summary.duration_ms)
      |> Map.put(:trace_id, trace_id)
      |> Map.put(:status, merge_tool_status(tool_event[:status], telemetry_summary.status))
      |> Map.put(:traces_path, tool_trace_path(traces_path, instance_id, call_id, trace_id))
    end)
  end

  def summarize_tool_telemetry(events) when is_list(events) do
    start_event = Enum.find(events, &(&1.event_prefix == [:jido, :ai, :tool, :execute, :start]))
    stop_event = Enum.find(events, &(&1.event_prefix == [:jido, :ai, :tool, :execute, :stop]))

    exception_event =
      Enum.find(events, &(&1.event_prefix == [:jido, :ai, :tool, :execute, :exception]))

    duration_ms =
      cond do
        is_map(stop_event) ->
          stop_event
          |> Map.get(:measurements, %{})
          |> Map.get(:duration)
          |> duration_to_ms()

        is_map(exception_event) ->
          exception_event
          |> Map.get(:measurements, %{})
          |> Map.get(:duration)
          |> duration_to_ms()

        true ->
          nil
      end

    trace_id =
      (stop_event && stop_event[:trace_id]) ||
        (exception_event && exception_event[:trace_id]) ||
        (start_event && start_event[:trace_id])

    status =
      cond do
        is_map(exception_event) -> :error
        is_map(stop_event) -> :completed
        is_map(start_event) -> :running
        true -> nil
      end

    %{duration_ms: duration_ms, trace_id: trace_id, status: status}
  end

  def summarize_tool_telemetry(_), do: %{duration_ms: nil, trace_id: nil, status: nil}

  def duration_to_ms(value) when is_integer(value) and value >= 0 do
    System.convert_time_unit(value, :native, :millisecond)
  end

  def duration_to_ms(_), do: nil

  def merge_tool_status(:error, _), do: :error
  def merge_tool_status(_, :error), do: :error
  def merge_tool_status(current, nil), do: current || :running
  def merge_tool_status(_current, telemetry_status), do: telemetry_status

  def tool_trace_path(nil, _instance_id, _call_id, _trace_id), do: nil

  def tool_trace_path(base_path, instance_id, call_id, trace_id) do
    params =
      [
        {"source", "telemetry"},
        {"instance_id", instance_id},
        {"call_id", call_id},
        {"trace_id", trace_id}
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

    case params do
      [] ->
        base_path

      _ ->
        separator = if String.contains?(base_path, "?"), do: "&", else: "?"
        base_path <> separator <> URI.encode_query(params)
    end
  end

  def refresh(socket) do
    live_action = socket.assigns[:live_action]
    agent = socket.assigns[:agent]
    instance_id = socket.assigns[:active_instance_id]
    pid = socket.assigns[:active_instance_pid]

    cond do
      live_action != :show or is_nil(agent) or not is_binary(instance_id) or not is_pid(pid) ->
        socket
        |> assign(:runtime_status, nil)
        |> assign(:runtime_messages, [])
        |> assign(:runtime_todos, [])
        |> assign(:instance_event_stream, [])
        |> assign(:expanded_event_ids, MapSet.new())
        |> assign(:interaction_model, Support.empty_interaction_model())
        |> assign(:runner_form, RunnerForm.new())
        |> assign(:runner_result, nil)
        |> assign(:runner_history, [])
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
        |> assign(:subagent_events, %{})
        |> assign(:expanded_subagent_id, nil)
        |> assign(:triage_links, %{})

      true ->
        preview =
          load_instance_observability(
            instance_id,
            pid,
            socket.assigns[:trace_preview_limit],
            socket.assigns[:trace_include_agent_debug?]
          )

        runtime_status = ShowState.instance_runtime_status(%{pid: pid})
        debug_enabled = ShowState.instance_debug_enabled(%{pid: pid})

        debug_level =
          Support.infer_debug_level(debug_enabled, socket.assigns[:instance_debug_level])

        presenter = socket.assigns[:presenter] || Default
        scope = socket.assigns[:scope_filters] || %{}

        subagents =
          if Delegation.enabled?() do
            Delegation.list_subagents(instance_id, scope: scope, limit: 200)
          else
            []
          end

        tasks =
          if Delegation.enabled?() do
            Delegation.list_tasks(instance_id, scope: scope, limit: 300)
          else
            []
          end

        latest_trace_id =
          preview
          |> Map.get(:events, [])
          |> Enum.find_value(fn event -> event[:trace_id] end)

        runtime_messages = MessageSnapshot.thread_messages(runtime_status)
        runtime_todos = Support.runtime_todos_for_display(runtime_status, tasks)

        event_stream =
          preview
          |> Map.get(:events, [])
          |> Support.build_instance_event_stream(socket.assigns[:live_event_limit])

        delegation_graph =
          if Delegation.enabled?() and is_binary(latest_trace_id) do
            Delegation.delegation_graph(latest_trace_id, limit: 800)
          else
            %{nodes: [], edges: []}
          end

        tool_insights =
          if Delegation.enabled?() do
            Delegation.list_tool_runs(instance_id, limit: 120)
          else
            []
          end

        middleware_snapshots =
          if Delegation.enabled?() do
            Delegation.list_middleware_snapshots(instance_id, limit: 40)
          else
            []
          end

        interaction_model =
          if AgentInteractions.enabled?() do
            Introspection.build(agent.module, %{pid: pid}, events: Map.get(preview, :events, []))
          else
            Support.empty_interaction_model()
          end

        view_model =
          ShowState.presenter_view_model(
            presenter,
            agent,
            runtime_status,
            instance_id: instance_id,
            pid: pid,
            debug_enabled: debug_enabled,
            raw_state: runtime_status && runtime_status.raw_state,
            observability_preview: preview,
            traces_path:
              ShowState.traces_path(socket.assigns.prefix, agent, instance_id, instance_id)
          )

        tabs =
          view_model
          |> Map.get(:tabs, [%{id: :overview, label: "Overview"}])
          |> Support.ordered_detail_tabs()

        socket
        |> assign(:runtime_status, runtime_status)
        |> assign(:runtime_messages, runtime_messages)
        |> assign(:runtime_todos, runtime_todos)
        |> assign(:instance_event_stream, event_stream)
        |> assign(
          :expanded_event_ids,
          Support.sanitize_expanded_event_ids(socket.assigns[:expanded_event_ids], event_stream)
        )
        |> assign(:instance_debug_enabled?, debug_enabled)
        |> assign(:instance_debug_level, debug_level)
        |> assign(:instance_observability_events, Map.get(preview, :events, []))
        |> assign(:instance_debug_events, Map.get(preview, :debug_events, []))
        |> assign(:instance_telemetry_events, Map.get(preview, :telemetry_events, []))
        |> assign(:instance_debug_error, Map.get(preview, :debug_error))
        |> assign(:subagents, subagents)
        |> assign(:tasks, tasks)
        |> assign(:delegation_graph, delegation_graph)
        |> assign(:tool_insights, tool_insights)
        |> assign(:middleware_snapshots, middleware_snapshots)
        |> assign(:interaction_model, interaction_model)
        |> assign(
          :runner_form,
          Support.sync_runner_form(socket.assigns[:runner_form], interaction_model)
        )
        |> assign(:detail_tabs, tabs)
        |> assign(
          :detail_tab,
          preserve_detail_tab(socket.assigns[:detail_tab], tabs, &ShowState.default_detail_tab/1)
        )
        |> assign(:sections_by_tab, Map.get(view_model, :sections_by_tab, %{}))
        |> assign(
          :triage_links,
          ShowState.triage_links(socket.assigns.prefix, instance_id, scope)
        )
        |> assign(
          :system_prompt,
          Map.get(view_model, :system_prompt, "No system prompt configured.")
        )
        |> Support.maybe_load_subagent_events(socket.assigns[:expanded_subagent_id])
    end
  end

  def load_instance_observability(instance_id, pid, limit, include_agent_debug?) do
    Observability.trace_preview(instance_id, pid,
      limit: normalize_observability_limit(limit),
      include_agent_debug?: include_agent_debug? != false
    )
  rescue
    error ->
      %{
        events: [],
        telemetry_events: [],
        debug_events: [],
        debug_error: {:exception, Exception.message(error)}
      }
  end

  def normalize_observability_limit(limit) when is_integer(limit) and limit > 0, do: limit
  def normalize_observability_limit(_), do: Observability.trace_preview_limit()

  def preserve_detail_tab(tab, tabs, default_tab_fun) when is_function(default_tab_fun, 1) do
    if Enum.any?(tabs, &(&1.id == tab)), do: tab, else: default_tab_fun.(tabs)
  end
end
