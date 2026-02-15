defmodule JidoStudio.Ingestor do
  @moduledoc false
  use GenServer

  alias JidoStudio.Persistence

  @traces_namespace "traces"
  @spans_namespace "spans"

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
    trace_id = normalize_optional_string(event[:trace_id])

    if is_binary(trace_id) do
      _ = Persistence.append_event(trace_stream(trace_id), event)
      _ = persist_trace_doc(trace_id, event)
      _ = persist_span_doc(trace_id, event)
    end

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

      Persistence.put_doc(@spans_namespace, doc_id, updated)
    else
      :ok
    end
  end

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
