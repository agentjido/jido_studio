defmodule JidoStudio.Observability do
  @moduledoc false

  alias JidoStudio.AgentRegistry
  alias JidoStudio.TraceBuffer

  @default_trace_preview_limit 200
  @default_trace_page_limit 300

  @spec trace_preview(String.t(), pid() | nil, keyword()) :: map()
  def trace_preview(instance_id, pid, opts \\ []) when is_binary(instance_id) do
    limit = Keyword.get(opts, :limit, trace_preview_limit())
    include_agent_debug? = Keyword.get(opts, :include_agent_debug?, trace_include_agent_debug?())

    telemetry_events = TraceBuffer.events_for_instance(instance_id, limit)

    {debug_events, debug_error} =
      if include_agent_debug? and is_pid(pid) do
        load_agent_debug_events(pid, instance_id, limit)
      else
        {[], nil}
      end

    events =
      telemetry_events
      |> Kernel.++(debug_events)
      |> Enum.sort_by(&(&1[:timestamp_ms] || 0), :desc)
      |> Enum.take(limit)

    %{
      events: events,
      telemetry_events: telemetry_events,
      debug_events: debug_events,
      debug_error: debug_error
    }
  end

  @spec query_events(module() | nil, keyword()) :: [map()]
  def query_events(jido_instance, opts \\ []) do
    limit = Keyword.get(opts, :limit, trace_page_limit())
    include_agent_debug? = Keyword.get(opts, :include_agent_debug?, trace_include_agent_debug?())
    filters = Keyword.get(opts, :filters, %{})
    source = normalized_source(filters)

    telemetry_events =
      if source in [:all, :telemetry] do
        TraceBuffer.events(limit * 2, filters)
      else
        []
      end

    debug_events =
      if include_agent_debug? and source in [:all, :agent_debug] do
        collect_agent_debug_events(jido_instance, filters, limit)
      else
        []
      end

    telemetry_events
    |> Kernel.++(debug_events)
    |> Enum.sort_by(&(&1[:timestamp_ms] || 0), :desc)
    |> Enum.take(limit)
  end

  @spec collect_agent_debug_events(module() | nil, keyword() | map(), pos_integer()) :: [map()]
  def collect_agent_debug_events(jido_instance, filters, limit) do
    filter_map = normalize_filters(filters)

    jido_instance
    |> list_running_instances(filter_map)
    |> Enum.flat_map(fn %{id: id, pid: pid, module: module} ->
      case Jido.AgentServer.recent_events(pid, limit: min(limit, 50)) do
        {:ok, events} ->
          events
          |> Enum.map(
            &TraceBuffer.normalize_agent_debug_event(&1, agent_id: id, agent_module: module)
          )

        _ ->
          []
      end
    end)
    |> TraceBuffer.filter_events(filter_map)
    |> Enum.sort_by(&(&1[:timestamp_ms] || 0), :desc)
    |> Enum.take(limit)
  end

  @spec load_agent_debug_events(pid(), String.t(), pos_integer()) :: {[map()], term() | nil}
  def load_agent_debug_events(pid, agent_id, limit) when is_pid(pid) and is_binary(agent_id) do
    case Jido.AgentServer.recent_events(pid, limit: min(limit, 50)) do
      {:ok, events} ->
        normalized =
          Enum.map(events, &TraceBuffer.normalize_agent_debug_event(&1, agent_id: agent_id))

        {normalized, nil}

      {:error, :debug_not_enabled} ->
        {[], :debug_not_enabled}

      {:error, reason} ->
        {[], reason}

      _ ->
        {[], :unknown}
    end
  end

  def load_agent_debug_events(_pid, _agent_id, _limit), do: {[], :invalid_pid}

  @spec trace_preview_limit() :: pos_integer()
  def trace_preview_limit do
    Application.get_env(:jido_studio, :trace_preview_limit, @default_trace_preview_limit)
  end

  @spec trace_page_limit() :: pos_integer()
  def trace_page_limit do
    Application.get_env(:jido_studio, :trace_page_limit, @default_trace_page_limit)
  end

  @spec trace_include_agent_debug?() :: boolean()
  def trace_include_agent_debug? do
    Application.get_env(:jido_studio, :trace_include_agent_debug, true)
  end

  defp list_running_instances(nil, _filters), do: []

  defp list_running_instances(jido_instance, filters) do
    agent_id_filter = Map.get(filters, :agent_id) || Map.get(filters, :instance_id)

    AgentRegistry.list_agents(jido_instance: jido_instance)
    |> Enum.flat_map(fn agent ->
      Enum.map(agent.running_instances || [], fn instance ->
        %{id: instance.id, pid: instance.pid, module: agent.module}
      end)
    end)
    |> Enum.filter(fn %{id: id} ->
      if is_nil(agent_id_filter), do: true, else: to_string(id) == to_string(agent_id_filter)
    end)
  end

  defp normalize_filters(filters) when is_map(filters), do: filters
  defp normalize_filters(filters) when is_list(filters), do: Enum.into(filters, %{})
  defp normalize_filters(_), do: %{}

  defp normalized_source(filters) do
    filters
    |> normalize_filters()
    |> Map.get(:source, :all)
    |> case do
      source when source in [:telemetry, :agent_debug, :all] -> source
      "telemetry" -> :telemetry
      "agent_debug" -> :agent_debug
      _ -> :all
    end
  end
end
