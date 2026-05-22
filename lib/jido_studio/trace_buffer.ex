defmodule JidoStudio.TraceBuffer do
  @moduledoc false
  use GenServer

  alias JidoStudio.Ingestor
  alias JidoStudio.LiveOps
  alias JidoStudio.Observability.Correlation
  alias JidoStudio.TraceCatalog

  @default_size 5000
  @table :jido_studio_traces
  @handler_id "jido-studio-trace-buffer"

  @sensitive_exact_keys [
    "apikey",
    "api_key",
    "password",
    "secret",
    "token",
    "authtoken",
    "auth_token",
    "privatekey",
    "private_key",
    "accesskey",
    "access_key",
    "bearer",
    "apisecret",
    "api_secret",
    "clientsecret",
    "client_secret"
  ]

  @sensitive_suffixes [
    "_secret",
    "_key",
    "_token",
    "_password"
  ]

  @filter_key_map %{
    "event_prefix" => :event_prefix,
    "source" => :source,
    "agent_id" => :agent_id,
    "instance_id" => :instance_id,
    "signal_type" => :signal_type,
    "directive_type" => :directive_type,
    "trace_id" => :trace_id,
    "span_id" => :span_id,
    "parent_span_id" => :parent_span_id,
    "causation_id" => :causation_id,
    "call_id" => :call_id
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec events(pos_integer()) :: [map()]
  def events(limit \\ 50), do: events(limit, %{})

  @spec events(pos_integer(), keyword() | map()) :: [map()]
  def events(limit, filters) do
    limit = normalize_limit(limit)

    case :ets.info(@table) do
      :undefined ->
        []

      _ ->
        :ets.tab2list(@table)
        |> Enum.sort_by(&elem(&1, 0), :desc)
        |> Enum.map(&elem(&1, 1))
        |> filter_events(filters)
        |> Enum.take(limit)
    end
  end

  @spec events_for_instance(String.t(), pos_integer()) :: [map()]
  def events_for_instance(instance_id, limit \\ 50) when is_binary(instance_id) do
    events(limit, %{instance_id: instance_id})
  end

  @spec event_catalog() :: [[atom()]]
  def event_catalog do
    TraceCatalog.configured_events()
  end

  @spec filter_events([map()], keyword() | map()) :: [map()]
  def filter_events(events, filters) when is_list(events) do
    filter_map = normalize_filters(filters)

    Enum.filter(events, fn event ->
      matches_filters?(event, filter_map)
    end)
  end

  @spec matches_filters?(map(), keyword() | map()) :: boolean()
  def matches_filters?(event, filters) when is_map(event) do
    filter_map = normalize_filters(filters)

    Enum.all?(filter_map, fn
      {:event_prefix, prefix} when is_list(prefix) ->
        event[:event_prefix] == prefix

      {:source, source} when source in [:telemetry, :agent_debug] ->
        event[:source] == source

      {:agent_id, value} ->
        match_string(event[:agent_id], value) or match_string(event[:instance_id], value)

      {:instance_id, value} ->
        match_string(event[:instance_id], value) or match_string(event[:agent_id], value)

      {:signal_type, value} ->
        match_string(event[:signal_type], value)

      {:directive_type, value} ->
        match_string(event[:directive_type], value)

      {:trace_id, value} ->
        match_string(event[:trace_id], value)

      {:span_id, value} ->
        match_string(event[:span_id], value)

      {:parent_span_id, value} ->
        match_string(event[:parent_span_id], value)

      {:causation_id, value} ->
        match_string(event[:causation_id], value)

      {:call_id, value} ->
        match_string(event[:call_id], value)

      {_key, _value} ->
        true
    end)
  end

  def matches_filters?(_event, _filters), do: false

  @spec normalize_agent_debug_event(map(), keyword()) :: map()
  def normalize_agent_debug_event(event, opts \\ []) when is_map(event) do
    agent_id = Keyword.get(opts, :agent_id)
    agent_module = Keyword.get(opts, :agent_module)

    event_type = normalize_event_type(event[:type])

    metadata =
      event
      |> Map.get(:data, %{})
      |> normalize_metadata()
      |> Map.put_new(:agent_id, agent_id)
      |> maybe_put(:agent_module, agent_module)

    timestamp_ms = monotonic_to_wallclock(event[:at])

    normalize_event(
      [:jido, :agent_server, :debug, event_type],
      %{},
      metadata,
      timestamp_ms,
      :agent_debug,
      nil
    )
  end

  @impl true
  def init(opts) do
    size =
      Keyword.get(
        opts,
        :size,
        Application.get_env(:jido_studio, :trace_buffer_size, @default_size)
      )

    :ets.new(@table, [:ordered_set, :public, :named_table])

    attach_telemetry()

    {:ok, %{size: size, counter: 0}}
  end

  @impl true
  def handle_info({:telemetry_event, event_prefix, measurements, metadata}, state) do
    counter = state.counter + 1

    normalized =
      normalize_event(
        event_prefix,
        normalize_measurements(measurements),
        normalize_metadata(metadata),
        System.system_time(:millisecond),
        :telemetry,
        counter
      )

    :ets.insert(@table, {counter, normalized})
    Ingestor.ingest_event(normalized)
    broadcast_live_ops(normalized)

    if counter > state.size do
      case :ets.first(@table) do
        :"$end_of_table" -> :ok
        key -> :ets.delete(@table, key)
      end
    end

    {:noreply, %{state | counter: counter}}
  end

  defp attach_telemetry do
    :telemetry.detach(@handler_id)

    pid = self()

    :telemetry.attach_many(
      @handler_id,
      TraceCatalog.configured_events(),
      &__MODULE__.handle_telemetry/4,
      pid
    )
  rescue
    _ ->
      :ok
  end

  @doc false
  def handle_telemetry(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  defp normalize_event(event_prefix, measurements, metadata, timestamp_ms, source, counter)
       when is_list(event_prefix) and is_map(metadata) do
    trace_id = metadata[:jido_trace_id] || metadata[:trace_id]
    span_id = metadata[:jido_span_id] || metadata[:span_id]
    parent_span_id = metadata[:jido_parent_span_id] || metadata[:parent_span_id]
    causation_id = metadata[:jido_causation_id] || metadata[:causation_id]
    call_id = metadata[:call_id]

    agent_id = metadata[:agent_id]
    instance_id = metadata[:instance_id] || agent_id
    entity_type = metadata[:entity_type] || infer_entity_type(event_prefix)

    entity_id =
      metadata[:entity_id] || metadata[:tool_name] || metadata[:sensor_id] || call_id ||
        metadata[:agent_id] || span_id

    internal =
      (metadata[:internal] || metadata[:is_internal] || metadata["internal"]) == true or
        infer_internal?(event_prefix)

    chunk_index = normalize_optional_non_negative_integer(metadata[:chunk_index])
    chunk_count = normalize_optional_non_negative_integer(metadata[:chunk_count])
    task_id = metadata[:task_id] || metadata[:todo_id] || metadata["task_id"]
    task_status = metadata[:task_status] || metadata["task_status"]
    parent_agent_id = metadata[:parent_agent_id] || metadata["parent_agent_id"]
    scope = scope_from_metadata(metadata)

    %{
      id: counter,
      source: source,
      event_prefix: event_prefix,
      event_name: Enum.join(event_prefix, "."),
      type: List.last(event_prefix),
      timestamp_ms: timestamp_ms,
      measurements: measurements,
      metadata: sanitize_metadata(metadata),
      trace_id: trace_id,
      span_id: span_id,
      parent_span_id: parent_span_id,
      causation_id: causation_id,
      call_id: call_id,
      agent_id: agent_id,
      instance_id: instance_id,
      entity_type: entity_type,
      entity_id: entity_id,
      internal: internal,
      parent_agent_id: parent_agent_id,
      chunk_index: chunk_index,
      chunk_count: chunk_count,
      task_id: task_id,
      task_status: task_status,
      scope: scope,
      status: event_status(List.last(event_prefix)),
      signal_type: metadata[:signal_type],
      directive_type: metadata[:directive_type]
    }
    |> Correlation.normalize()
  end

  defp normalize_event(_event_prefix, _measurements, metadata, timestamp_ms, source, counter) do
    %{
      id: counter,
      source: source,
      event_prefix: [],
      event_name: "unknown",
      type: :unknown,
      timestamp_ms: timestamp_ms,
      measurements: %{},
      metadata: sanitize_metadata(metadata),
      trace_id: nil,
      span_id: nil,
      parent_span_id: nil,
      causation_id: nil,
      call_id: nil,
      agent_id: nil,
      instance_id: nil,
      entity_type: :other,
      entity_id: nil,
      internal: false,
      parent_agent_id: nil,
      chunk_index: nil,
      chunk_count: nil,
      task_id: nil,
      task_status: nil,
      scope: %{},
      status: nil,
      signal_type: nil,
      directive_type: nil
    }
    |> Correlation.normalize()
  end

  defp normalize_event_type(type) when is_atom(type), do: type

  defp normalize_event_type(type) when is_binary(type) do
    case type |> String.trim() |> String.downcase() do
      "" -> :unknown
      value -> value
    end
  end

  defp normalize_event_type(_), do: :unknown

  defp normalize_measurements(map) when is_map(map), do: map
  defp normalize_measurements(_), do: %{}

  defp normalize_metadata(map) when is_map(map), do: map
  defp normalize_metadata(_), do: %{}

  defp sanitize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(fn {key, value} -> {key, sanitize_metadata_entry(key, value)} end)
    |> Map.new()
  end

  defp sanitize_metadata(_), do: %{}

  defp sanitize_metadata_entry(key, _value) when key in [:stacktrace, "stacktrace"] do
    "[OMITTED]"
  end

  defp sanitize_metadata_entry(key, value) do
    should_redact =
      Application.get_env(:jido, :observability, []) |> Keyword.get(:redact_sensitive, false)

    cond do
      should_redact and sensitive_key?(key) -> "[REDACTED]"
      is_struct(value) -> inspect(value)
      is_map(value) -> sanitize_metadata(value)
      is_list(value) -> Enum.map(value, &sanitize_metadata_entry(:nested, &1))
      true -> value
    end
  end

  defp sensitive_key?(key) when is_atom(key) do
    key |> Atom.to_string() |> sensitive_key?()
  end

  defp sensitive_key?(key) when is_binary(key) do
    normalized_key = String.downcase(key)

    normalized_key in @sensitive_exact_keys or
      String.contains?(normalized_key, "secret_") or
      String.ends_with?(normalized_key, @sensitive_suffixes)
  end

  defp sensitive_key?(_), do: false

  defp normalize_filters(filters) when is_map(filters) do
    Enum.reduce(filters, %{}, fn {k, v}, acc ->
      if is_nil(v) or v == "" do
        acc
      else
        case normalize_filter_key(k) do
          nil ->
            acc

          key ->
            Map.put(acc, key, normalize_filter_value(key, v))
        end
      end
    end)
  end

  defp normalize_filters(filters) when is_list(filters) do
    filters |> Enum.into(%{}) |> normalize_filters()
  end

  defp normalize_filters(_), do: %{}

  defp normalize_filter_key(key) when is_atom(key), do: key
  defp normalize_filter_key(key) when is_binary(key), do: Map.get(@filter_key_map, key)
  defp normalize_filter_key(_key), do: nil

  defp normalize_filter_value(:source, value) when is_binary(value) do
    case String.downcase(value) do
      "telemetry" -> :telemetry
      "agent_debug" -> :agent_debug
      _ -> :all
    end
  end

  defp normalize_filter_value(_key, value), do: value

  defp match_string(nil, _expected), do: false

  defp match_string(actual, expected) do
    to_string(actual) == to_string(expected)
  end

  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_limit(_), do: 50

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp monotonic_to_wallclock(at) when is_integer(at) do
    now_wall = System.system_time(:millisecond)
    now_mono = System.monotonic_time(:millisecond)
    now_wall - (now_mono - at)
  end

  defp monotonic_to_wallclock(_), do: System.system_time(:millisecond)

  defp broadcast_live_ops(event) when is_map(event) do
    payload = %{
      timestamp_ms: event[:timestamp_ms],
      trace_id: event[:trace_id],
      span_id: event[:span_id],
      event_name: event[:event_name],
      source: event[:source],
      metadata: event[:metadata] || %{},
      measurements: event[:measurements] || %{},
      call_id: event[:call_id],
      task_id: event[:task_id],
      scope: event[:scope] || %{},
      type: event[:type],
      status: event[:status]
    }

    scope = event[:scope] || %{}
    _ = LiveOps.broadcast_agent_list(payload, scope)

    case event[:agent_id] || event[:instance_id] do
      agent_id when is_binary(agent_id) and agent_id != "" ->
        _ = LiveOps.broadcast_agent(agent_id, payload, scope)
        :ok

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp broadcast_live_ops(_), do: :ok

  defp infer_entity_type(prefix) when is_list(prefix) do
    values = Enum.map(prefix, &to_string/1)

    cond do
      Enum.member?(values, "tool") -> :tool
      Enum.member?(values, "middleware") -> :middleware
      Enum.member?(values, "scheduler") -> :scheduler
      Enum.member?(values, "sensor") -> :sensor
      Enum.member?(values, "ai") -> :model
      Enum.member?(values, "agent") -> :agent
      true -> :other
    end
  end

  defp infer_entity_type(_), do: :other

  defp infer_internal?(prefix) when is_list(prefix) do
    values = Enum.map(prefix, &to_string/1)

    Enum.member?(values, "strategy") or
      Enum.member?(values, "agent_server") or
      Enum.member?(values, "middleware")
  end

  defp infer_internal?(_), do: false

  defp event_status(:exception), do: "error"
  defp event_status("exception"), do: "error"
  defp event_status(:stop), do: "ok"
  defp event_status("stop"), do: "ok"
  defp event_status(:start), do: "running"
  defp event_status("start"), do: "running"
  defp event_status(_), do: nil

  defp normalize_optional_non_negative_integer(value) when is_integer(value) and value >= 0,
    do: value

  defp normalize_optional_non_negative_integer(_), do: nil

  defp scope_from_metadata(metadata) when is_map(metadata) do
    scope_map =
      metadata[:scope] || metadata["scope"] || %{}

    base =
      cond do
        is_map(scope_map) -> scope_map
        is_list(scope_map) -> Map.new(scope_map)
        true -> %{}
      end

    base
    |> maybe_put_scope(:project_id, metadata[:project_id] || metadata["project_id"])
    |> maybe_put_scope(:user_id, metadata[:user_id] || metadata["user_id"])
  end

  defp scope_from_metadata(_), do: %{}

  defp maybe_put_scope(scope, _key, nil), do: scope
  defp maybe_put_scope(scope, key, value), do: Map.put(scope, key, value)
end
