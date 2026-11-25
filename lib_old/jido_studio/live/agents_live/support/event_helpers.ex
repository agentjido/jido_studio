defmodule JidoStudio.Live.AgentsLive.Support.EventHelpers do
  @moduledoc false

  alias JidoStudio.Agents.MessageSnapshot
  alias JidoStudio.Live.AgentsLive.Support.ScopeHelpers

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
    call_id =
      ScopeHelpers.normalize_scope_value(event[:call_id] || event_metadata_value(event, :call_id))

    span_id = ScopeHelpers.normalize_scope_value(event[:span_id])
    event_name = to_string(event[:event_name] || event[:type] || "event")
    chunk_key = ScopeHelpers.normalize_scope_value(event_metadata_value(event, :chunk_id))

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
        id: ScopeHelpers.normalize_scope_value(task[:task_id]) || Integer.to_string(idx),
        content:
          "Task " <>
            to_string(task[:task_id] || "unknown") <>
            " (" <> to_string(task[:task_status] || task[:status] || "running") <> ")",
        status: todo_status_from_task(task[:task_status] || task[:status]),
        active_form: ScopeHelpers.normalize_scope_value(task[:trace_id])
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
end
