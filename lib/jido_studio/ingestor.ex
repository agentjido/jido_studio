defmodule JidoStudio.Ingestor do
  @moduledoc false
  use GenServer

  alias JidoStudio.Persistence

  @traces_namespace "traces"
  @spans_namespace "spans"
  @subagents_namespace "subagents"
  @tasks_namespace "tasks"
  @tool_runs_namespace "tool_runs"
  @middleware_namespace "middleware_snapshots"

  @terminal_types [:stop, :exception]

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec ingest_event(map()) :: :ok
  def ingest_event(event) when is_map(event) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.cast(__MODULE__, {:ingest, event})
      _ -> :ok
    end

    :ok
  end

  def ingest_event(_), do: :ok

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:ingest, event}, state) do
    _ = persist_event(event)
    {:noreply, state}
  end

  defp persist_event(event) do
    normalized_event = normalize_ingested_event(event)
    trace_id = normalize_optional_string(normalized_event[:trace_id])

    if is_binary(trace_id) do
      _ = Persistence.append_event(trace_stream(trace_id), normalized_event)
      _ = persist_trace_doc(trace_id, normalized_event)
      _ = persist_span_doc(trace_id, normalized_event)
    end

    _ = persist_subagent_doc(trace_id, normalized_event)
    _ = persist_task_doc(trace_id, normalized_event)
    _ = persist_tool_run_doc(trace_id, normalized_event)
    _ = persist_middleware_doc(trace_id, normalized_event)

    :ok
  rescue
    _ -> :ok
  end

  defp persist_trace_doc(trace_id, event) do
    existing =
      case Persistence.get_doc(@traces_namespace, trace_id) do
        {:ok, doc} when is_map(doc) -> doc
        _ -> %{id: trace_id, trace_id: trace_id}
      end

    timestamp = event_timestamp(event)
    type = normalize_event_type(event[:type])

    started_at =
      existing
      |> Map.get(:started_at)
      |> min_timestamp(timestamp)

    ended_at =
      if type in @terminal_types do
        max_timestamp(Map.get(existing, :ended_at), timestamp)
      else
        Map.get(existing, :ended_at)
      end

    status = normalize_status(Map.get(existing, :status), type)

    error_payload =
      if type == :exception do
        normalize_metadata(Map.get(event, :metadata, %{}))
      else
        Map.get(existing, :error_payload)
      end

    span_ids =
      existing
      |> Map.get(:span_ids, [])
      |> maybe_add_span_id(event[:span_id])
      |> Enum.take(-300)

    duration_ms =
      case {started_at, ended_at} do
        {start_ms, end_ms} when is_integer(start_ms) and is_integer(end_ms) ->
          max(end_ms - start_ms, 0)

        _ ->
          nil
      end

    updated =
      existing
      |> Map.put(:trace_id, trace_id)
      |> Map.put(
        :agent_id,
        normalize_optional_string(event[:agent_id]) || Map.get(existing, :agent_id)
      )
      |> Map.put(:status, status)
      |> Map.put(:started_at, started_at || timestamp)
      |> Map.put(:ended_at, ended_at)
      |> Map.put(:duration_ms, duration_ms)
      |> Map.put(:error, type == :exception or Map.get(existing, :error, false))
      |> Map.put(:error_payload, error_payload)
      |> Map.put(:last_event_at, timestamp)
      |> Map.put(
        :event_count,
        normalize_non_negative_integer(Map.get(existing, :event_count), 0) + 1
      )
      |> Map.put(:span_ids, span_ids)
      |> Map.put(:span_count, length(span_ids))
      |> Map.put(
        :call_id,
        normalize_optional_string(event[:call_id]) || Map.get(existing, :call_id)
      )
      |> Map.put(
        :causation_id,
        normalize_optional_string(event[:causation_id]) || Map.get(existing, :causation_id)
      )
      |> Map.put(
        :scope,
        merge_scope(Map.get(existing, :scope), Map.get(event, :scope))
      )
      |> Map.put(
        :parent_agent_id,
        normalize_optional_string(event[:parent_agent_id]) || Map.get(existing, :parent_agent_id)
      )
      |> Map.put(
        :entity_type_rollup,
        increment_entity_rollup(Map.get(existing, :entity_type_rollup), event[:entity_type])
      )

    Persistence.put_doc(@traces_namespace, trace_id, updated)
  end

  defp persist_span_doc(trace_id, event) do
    span_id = normalize_optional_string(event[:span_id])

    if is_binary(span_id) do
      doc_id = "#{trace_id}:#{span_id}"

      existing =
        case Persistence.get_doc(@spans_namespace, doc_id) do
          {:ok, doc} when is_map(doc) -> doc
          _ -> %{id: doc_id, trace_id: trace_id, span_id: span_id}
        end

      timestamp = event_timestamp(event)
      type = normalize_event_type(event[:type])

      started_at =
        existing
        |> Map.get(:started_at)
        |> min_timestamp(timestamp)

      ended_at =
        if type in @terminal_types do
          max_timestamp(Map.get(existing, :ended_at), timestamp)
        else
          Map.get(existing, :ended_at)
        end

      duration_ms =
        case {started_at, ended_at} do
          {start_ms, end_ms} when is_integer(start_ms) and is_integer(end_ms) ->
            max(end_ms - start_ms, 0)

          _ ->
            nil
        end

      updated =
        existing
        |> Map.put(:trace_id, trace_id)
        |> Map.put(:span_id, span_id)
        |> Map.put(:parent_span_id, normalize_optional_string(event[:parent_span_id]))
        |> Map.put(:event_name, normalize_event_name(event))
        |> Map.put(:agent_id, normalize_optional_string(event[:agent_id]))
        |> Map.put(:status, normalize_status(Map.get(existing, :status), type))
        |> Map.put(:started_at, started_at || timestamp)
        |> Map.put(:ended_at, ended_at)
        |> Map.put(:duration_ms, duration_ms)
        |> Map.put(:last_event_at, timestamp)
        |> Map.put(:error, type == :exception or Map.get(existing, :error, false))
        |> Map.put(
          :error_payload,
          if(type == :exception,
            do: normalize_metadata(event[:metadata]),
            else: Map.get(existing, :error_payload)
          )
        )
        |> Map.put(:metadata, normalize_metadata(event[:metadata]))
        |> Map.put(:entity_type, normalize_optional_string(event[:entity_type]))
        |> Map.put(:entity_id, normalize_optional_string(event[:entity_id]))
        |> Map.put(:internal, event[:internal] == true)
        |> Map.put(:parent_agent_id, normalize_optional_string(event[:parent_agent_id]))
        |> Map.put(:chunk_index, normalize_optional_integer(event[:chunk_index]))
        |> Map.put(:chunk_count, normalize_optional_integer(event[:chunk_count]))
        |> Map.put(:task_id, normalize_optional_string(event[:task_id]))
        |> Map.put(:task_status, normalize_optional_string(event[:task_status]))
        |> Map.put(:scope, merge_scope(Map.get(existing, :scope), Map.get(event, :scope)))

      Persistence.put_doc(@spans_namespace, doc_id, updated)
    else
      :ok
    end
  end

  defp persist_subagent_doc(trace_id, event) do
    parent_agent_id = normalize_optional_string(event[:parent_agent_id])
    agent_id = normalize_optional_string(event[:agent_id] || event[:instance_id])

    if is_binary(parent_agent_id) and is_binary(agent_id) and parent_agent_id != agent_id do
      doc_id =
        case trace_id do
          value when is_binary(value) -> "#{value}:#{parent_agent_id}:#{agent_id}"
          _ -> "#{parent_agent_id}:#{agent_id}"
        end

      existing =
        case Persistence.get_doc(@subagents_namespace, doc_id) do
          {:ok, doc} when is_map(doc) -> doc
          _ -> %{id: doc_id}
        end

      timestamp = event_timestamp(event)

      updated =
        existing
        |> Map.put(:trace_id, trace_id || Map.get(existing, :trace_id))
        |> Map.put(:parent_agent_id, parent_agent_id)
        |> Map.put(:agent_id, agent_id)
        |> Map.put(
          :status,
          normalize_optional_string(event[:status]) || Map.get(existing, :status)
        )
        |> Map.put(:event_name, normalize_event_name(event))
        |> Map.put(:scope, merge_scope(Map.get(existing, :scope), event[:scope]))
        |> Map.put(:last_event_at, timestamp)

      Persistence.put_doc(@subagents_namespace, doc_id, updated)
    else
      :ok
    end
  end

  defp persist_task_doc(trace_id, event) do
    task_id = normalize_optional_string(event[:task_id])

    if is_binary(task_id) do
      agent_id = normalize_optional_string(event[:agent_id] || event[:instance_id]) || "unknown"
      doc_id = "#{agent_id}:#{task_id}"
      timestamp = event_timestamp(event)
      type = normalize_event_type(event[:type])

      existing =
        case Persistence.get_doc(@tasks_namespace, doc_id) do
          {:ok, doc} when is_map(doc) -> doc
          _ -> %{id: doc_id}
        end

      started_at =
        if type == :start do
          min_timestamp(Map.get(existing, :started_at), timestamp)
        else
          Map.get(existing, :started_at)
        end

      ended_at =
        if type in @terminal_types do
          max_timestamp(Map.get(existing, :ended_at), timestamp)
        else
          Map.get(existing, :ended_at)
        end

      status =
        normalize_optional_string(event[:task_status]) ||
          task_status_from_event(type, Map.get(existing, :status))

      updated =
        existing
        |> Map.put(:trace_id, trace_id || Map.get(existing, :trace_id))
        |> Map.put(:task_id, task_id)
        |> Map.put(:agent_id, agent_id)
        |> Map.put(
          :parent_agent_id,
          normalize_optional_string(event[:parent_agent_id]) ||
            Map.get(existing, :parent_agent_id)
        )
        |> Map.put(:task_status, status)
        |> Map.put(:status, status)
        |> Map.put(:started_at, started_at)
        |> Map.put(:ended_at, ended_at)
        |> Map.put(
          :event_count,
          normalize_non_negative_integer(Map.get(existing, :event_count), 0) + 1
        )
        |> Map.put(:last_event_at, timestamp)
        |> Map.put(:span_id, normalize_optional_string(event[:span_id]))
        |> Map.put(:scope, merge_scope(Map.get(existing, :scope), event[:scope]))

      Persistence.put_doc(@tasks_namespace, doc_id, updated)
    else
      :ok
    end
  end

  defp persist_tool_run_doc(trace_id, event) do
    type = normalize_event_type(event[:type])
    entity_type = normalize_optional_string(event[:entity_type])
    call_id = normalize_optional_string(event[:call_id])
    event_name = normalize_event_name(event)
    tool_event? = entity_type == "tool" or String.contains?(event_name, ".tool.")

    if tool_event? and is_binary(call_id) do
      timestamp = event_timestamp(event)
      doc_id = call_id

      existing =
        case Persistence.get_doc(@tool_runs_namespace, doc_id) do
          {:ok, doc} when is_map(doc) -> doc
          _ -> %{id: doc_id}
        end

      started_at =
        if type == :start do
          min_timestamp(Map.get(existing, :started_at), timestamp)
        else
          Map.get(existing, :started_at)
        end

      measured_duration = duration_ms_from_event(event)

      duration_ms =
        cond do
          is_integer(measured_duration) -> measured_duration
          type in @terminal_types and is_integer(started_at) -> max(timestamp - started_at, 0)
          true -> nil
        end

      call_count =
        normalize_non_negative_integer(Map.get(existing, :call_count), 0) +
          if(type == :start, do: 1, else: 0)

      failure_count =
        normalize_non_negative_integer(Map.get(existing, :failure_count), 0) +
          if(type == :exception, do: 1, else: 0)

      recent_durations =
        existing
        |> Map.get(:recent_durations, [])
        |> maybe_append_duration(duration_ms)
        |> Enum.take(-100)

      p95_duration_ms = percentile_ms(recent_durations, 0.95)

      updated =
        existing
        |> Map.put(:trace_id, trace_id || Map.get(existing, :trace_id))
        |> Map.put(:call_id, call_id)
        |> Map.put(
          :agent_id,
          normalize_optional_string(event[:agent_id] || event[:instance_id]) ||
            Map.get(existing, :agent_id)
        )
        |> Map.put(:tool_name, tool_name_from_event(event) || Map.get(existing, :tool_name))
        |> Map.put(:call_count, call_count)
        |> Map.put(:failure_count, failure_count)
        |> Map.put(:failure_ratio, failure_ratio(call_count, failure_count))
        |> Map.put(:last_duration_ms, duration_ms)
        |> Map.put(:p95_duration_ms, p95_duration_ms)
        |> Map.put(:last_status, tool_status(type))
        |> Map.put(:last_event_at, timestamp)
        |> Map.put(:recent_durations, recent_durations)
        |> Map.put(:scope, merge_scope(Map.get(existing, :scope), event[:scope]))

      Persistence.put_doc(@tool_runs_namespace, doc_id, updated)
    else
      :ok
    end
  end

  defp persist_middleware_doc(trace_id, event) do
    metadata = normalize_metadata(event[:metadata])
    entity_type = normalize_optional_string(event[:entity_type])
    chain = middleware_chain(metadata)
    middleware? = entity_type == "middleware" or chain != []

    if middleware? do
      agent_id = normalize_optional_string(event[:agent_id] || event[:instance_id]) || "unknown"
      entity_id = normalize_optional_string(event[:entity_id]) || "default"
      doc_id = "#{agent_id}:#{entity_id}"
      timestamp = event_timestamp(event)
      last_duration_ms = duration_ms_from_event(event)

      existing =
        case Persistence.get_doc(@middleware_namespace, doc_id) do
          {:ok, doc} when is_map(doc) -> doc
          _ -> %{id: doc_id}
        end

      updated =
        existing
        |> Map.put(:trace_id, trace_id || Map.get(existing, :trace_id))
        |> Map.put(:agent_id, agent_id)
        |> Map.put(:entity_id, entity_id)
        |> Map.put(
          :middleware_chain,
          if(chain == [], do: Map.get(existing, :middleware_chain, []), else: chain)
        )
        |> Map.put(
          :config_snapshot,
          metadata[:middleware_config] || metadata["middleware_config"] ||
            Map.get(existing, :config_snapshot, %{})
        )
        |> Map.put(:last_duration_ms, last_duration_ms)
        |> Map.put(:last_invoked_at, timestamp)
        |> Map.put(:scope, merge_scope(Map.get(existing, :scope), event[:scope]))

      Persistence.put_doc(@middleware_namespace, doc_id, updated)
    else
      :ok
    end
  end

  defp normalize_ingested_event(event) when is_map(event) do
    metadata = normalize_metadata(Map.get(event, :metadata))
    event_prefix = Map.get(event, :event_prefix)
    type = normalize_event_type(Map.get(event, :type))

    entity_type =
      normalize_optional_string(event[:entity_type]) ||
        infer_entity_type(event_prefix, metadata)

    entity_id =
      normalize_optional_string(event[:entity_id]) ||
        normalize_optional_string(metadata[:entity_id]) ||
        normalize_optional_string(metadata[:tool_name]) ||
        normalize_optional_string(event[:call_id]) ||
        normalize_optional_string(event[:agent_id]) ||
        normalize_optional_string(event[:span_id])

    scope = merge_scope(nil, event[:scope] || metadata[:scope] || metadata["scope"])

    event
    |> Map.put(:metadata, metadata)
    |> Map.put(:trace_id, normalize_optional_string(event[:trace_id]))
    |> Map.put(:span_id, normalize_optional_string(event[:span_id]))
    |> Map.put(:parent_span_id, normalize_optional_string(event[:parent_span_id]))
    |> Map.put(
      :parent_agent_id,
      normalize_optional_string(event[:parent_agent_id] || metadata[:parent_agent_id])
    )
    |> Map.put(
      :agent_id,
      normalize_optional_string(event[:agent_id] || event[:instance_id] || metadata[:agent_id])
    )
    |> Map.put(
      :instance_id,
      normalize_optional_string(event[:instance_id] || event[:agent_id] || metadata[:instance_id])
    )
    |> Map.put(:event_name, normalize_event_name(event))
    |> Map.put(:type, type)
    |> Map.put(:status, event_status(event[:status], type))
    |> Map.put(:entity_type, entity_type)
    |> Map.put(:entity_id, entity_id)
    |> Map.put(:internal, event_internal?(event, event_prefix, metadata))
    |> Map.put(
      :chunk_index,
      normalize_optional_integer(event[:chunk_index] || metadata[:chunk_index])
    )
    |> Map.put(
      :chunk_count,
      normalize_optional_integer(event[:chunk_count] || metadata[:chunk_count])
    )
    |> Map.put(:task_id, normalize_optional_string(event[:task_id] || metadata[:task_id]))
    |> Map.put(
      :task_status,
      normalize_optional_string(event[:task_status] || metadata[:task_status])
    )
    |> Map.put(:scope, scope)
  end

  defp normalize_ingested_event(_), do: %{}

  defp normalize_event_type(type) when type in [:start, :stop, :exception], do: type

  defp normalize_event_type(type) when is_binary(type) do
    case String.downcase(type) do
      "start" -> :start
      "stop" -> :stop
      "exception" -> :exception
      _ -> :event
    end
  end

  defp normalize_event_type(_), do: :event

  defp normalize_status(_existing_status, :exception), do: "error"
  defp normalize_status("error", :stop), do: "error"
  defp normalize_status(_existing_status, :stop), do: "ok"
  defp normalize_status(nil, :start), do: "running"
  defp normalize_status(nil, _), do: "running"
  defp normalize_status(existing_status, _), do: existing_status

  defp normalize_event_name(event) when is_map(event) do
    cond do
      is_binary(event[:event_name]) ->
        event[:event_name]

      is_list(event[:event_prefix]) ->
        Enum.join(event[:event_prefix], ".")

      true ->
        "event"
    end
  end

  defp normalize_event_name(_), do: "event"

  defp normalize_metadata(map) when is_map(map), do: map
  defp normalize_metadata(_), do: %{}

  defp infer_entity_type(prefix, metadata) do
    cond do
      is_binary(metadata[:entity_type]) and metadata[:entity_type] != "" -> metadata[:entity_type]
      is_list(prefix) and Enum.member?(prefix, :tool) -> "tool"
      is_list(prefix) and Enum.member?(prefix, :middleware) -> "middleware"
      is_list(prefix) and Enum.member?(prefix, :scheduler) -> "scheduler"
      is_list(prefix) and Enum.member?(prefix, :sensor) -> "sensor"
      is_list(prefix) and Enum.member?(prefix, :ai) -> "model"
      is_list(prefix) and Enum.member?(prefix, :agent) -> "agent"
      true -> "other"
    end
  end

  defp event_internal?(event, event_prefix, metadata) do
    explicit =
      event[:internal] ||
        metadata[:internal] ||
        metadata["internal"] ||
        metadata[:is_internal] ||
        metadata["is_internal"]

    cond do
      explicit in [true, "true", 1, "1"] ->
        true

      is_list(event_prefix) ->
        Enum.member?(event_prefix, :strategy) or
          Enum.member?(event_prefix, :agent_server) or
          Enum.member?(event_prefix, :middleware)

      true ->
        false
    end
  end

  defp event_status(existing, _type) when is_binary(existing) and existing != "", do: existing

  defp event_status(existing, _type) when existing in [:running, :ok, :error],
    do: Atom.to_string(existing)

  defp event_status(_existing, :exception), do: "error"
  defp event_status(_existing, :stop), do: "ok"
  defp event_status(_existing, :start), do: "running"
  defp event_status(_existing, _type), do: nil

  defp merge_scope(lhs, rhs) do
    left = normalize_scope(lhs)
    right = normalize_scope(rhs)
    merged = Map.merge(left, right)

    if map_size(merged) == 0, do: %{}, else: merged
  end

  defp normalize_scope(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      normalized = normalize_optional_string(value)

      if is_binary(normalized) do
        Map.put(acc, key, normalized)
      else
        acc
      end
    end)
  end

  defp normalize_scope(list) when is_list(list) do
    list
    |> Map.new()
    |> normalize_scope()
  end

  defp normalize_scope(_), do: %{}

  defp increment_entity_rollup(nil, entity_type), do: increment_entity_rollup(%{}, entity_type)

  defp increment_entity_rollup(map, entity_type) when is_map(map) do
    key = normalize_optional_string(entity_type) || "other"
    Map.update(map, key, 1, &(&1 + 1))
  end

  defp increment_entity_rollup(_, _), do: %{"other" => 1}

  defp task_status_from_event(:exception, _), do: "error"
  defp task_status_from_event(:stop, "error"), do: "error"
  defp task_status_from_event(:stop, _), do: "ok"
  defp task_status_from_event(:start, nil), do: "running"
  defp task_status_from_event(_, current), do: current || "running"

  defp duration_ms_from_event(event) when is_map(event) do
    duration =
      event
      |> Map.get(:measurements, %{})
      |> Map.get(:duration)

    if is_integer(duration) and duration >= 0 do
      System.convert_time_unit(duration, :native, :millisecond)
    else
      nil
    end
  end

  defp duration_ms_from_event(_), do: nil

  defp maybe_append_duration(list, nil), do: list

  defp maybe_append_duration(list, value) when is_integer(value) and value >= 0,
    do: list ++ [value]

  defp maybe_append_duration(list, _), do: list

  defp percentile_ms([], _), do: nil

  defp percentile_ms(values, percentile) when is_list(values) and is_number(percentile) do
    sorted = Enum.sort(values)
    idx = round((length(sorted) - 1) * percentile)
    Enum.at(sorted, idx)
  end

  defp percentile_ms(_, _), do: nil

  defp failure_ratio(0, _), do: 0.0

  defp failure_ratio(call_count, failure_count)
       when is_integer(call_count) and is_integer(failure_count) do
    failure_count / call_count
  end

  defp failure_ratio(_, _), do: 0.0

  defp tool_status(:exception), do: "error"
  defp tool_status(:stop), do: "ok"
  defp tool_status(:start), do: "running"
  defp tool_status(_), do: "running"

  defp tool_name_from_event(event) when is_map(event) do
    metadata = normalize_metadata(event[:metadata])
    normalize_optional_string(metadata[:tool_name] || metadata["tool_name"] || event[:entity_id])
  end

  defp tool_name_from_event(_), do: nil

  defp middleware_chain(metadata) when is_map(metadata) do
    chain = metadata[:middleware_chain] || metadata["middleware_chain"] || metadata[:middleware]

    cond do
      is_list(chain) -> Enum.map(chain, &to_string/1)
      is_binary(chain) -> [chain]
      true -> []
    end
  end

  defp middleware_chain(_), do: []

  defp event_timestamp(event) when is_map(event) do
    case event[:timestamp_ms] do
      value when is_integer(value) -> value
      _ -> System.system_time(:millisecond)
    end
  end

  defp event_timestamp(_), do: System.system_time(:millisecond)

  defp maybe_add_span_id(span_ids, nil), do: span_ids

  defp maybe_add_span_id(span_ids, span_id) do
    id = normalize_optional_string(span_id)

    if is_binary(id) and not Enum.member?(span_ids, id) do
      span_ids ++ [id]
    else
      span_ids
    end
  end

  defp trace_stream(trace_id), do: "trace:" <> trace_id

  defp normalize_optional_string(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil

  defp normalize_optional_integer(value) when is_integer(value), do: value
  defp normalize_optional_integer(_), do: nil

  defp normalize_non_negative_integer(value, _default) when is_integer(value) and value >= 0,
    do: value

  defp normalize_non_negative_integer(_value, default), do: default

  defp min_timestamp(nil, rhs), do: rhs
  defp min_timestamp(lhs, nil), do: lhs
  defp min_timestamp(lhs, rhs), do: min(lhs, rhs)

  defp max_timestamp(nil, rhs), do: rhs
  defp max_timestamp(lhs, nil), do: lhs
  defp max_timestamp(lhs, rhs), do: max(lhs, rhs)
end
