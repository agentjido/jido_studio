defmodule JidoStudio.Tracing do
  @moduledoc false

  alias JidoStudio.Persistence
  alias JidoStudio.TraceFilter

  @traces_namespace "traces"
  @spans_namespace "spans"
  @default_limit 200

  @spec list_traces(keyword()) :: [map()]
  def list_traces(opts \\ []) do
    filters = Keyword.get(opts, :filters, %{})
    limit = normalize_limit(Keyword.get(opts, :limit, @default_limit))

    Persistence.list_docs(@traces_namespace,
      order: :desc,
      limit: max(limit * 5, 500),
      sort_by: :last_event_at
    )
    |> Enum.filter(&trace_matches_filters?(&1, filters))
    |> Enum.sort_by(&trace_sort_key/1, :desc)
    |> Enum.take(limit)
  end

  @spec get_trace(String.t()) :: {:ok, map()} | :not_found | {:error, term()}
  def get_trace(trace_id) when is_binary(trace_id) do
    Persistence.get_doc(@traces_namespace, trace_id)
  end

  def get_trace(_), do: :not_found

  @spec list_trace_events(String.t(), keyword()) :: [map()]
  def list_trace_events(trace_id, opts \\ [])

  def list_trace_events(trace_id, opts) when is_binary(trace_id) do
    limit = normalize_limit(Keyword.get(opts, :limit, 500))
    filter_opts = trace_filter_opts(Keyword.get(opts, :filters, %{}))

    ("trace:" <> trace_id)
    |> Persistence.read_events(
      order: normalize_order(Keyword.get(opts, :order, :asc)),
      limit: limit,
      after_seq: Keyword.get(opts, :after_seq),
      before_seq: Keyword.get(opts, :before_seq)
    )
    |> TraceFilter.apply(filter_opts)
    |> maybe_take(limit)
  end

  def list_trace_events(_, _), do: []

  @spec list_trace_spans(String.t(), keyword()) :: [map()]
  def list_trace_spans(trace_id, opts \\ [])

  def list_trace_spans(trace_id, opts) when is_binary(trace_id) do
    limit =
      normalize_limit(
        Keyword.get(opts, :limit, TraceFilter.max_span_rows()),
        TraceFilter.max_span_rows()
      )

    filter_opts = trace_filter_opts(Keyword.get(opts, :filters, %{}))

    spans =
      Persistence.list_docs(@spans_namespace,
        id_prefix: trace_id <> ":",
        order: :asc,
        sort_by: :started_at,
        limit: limit
      )

    trace_started_at =
      case get_trace(trace_id) do
        {:ok, trace} -> Map.get(trace, :started_at)
        _ -> nil
      end

    spans
    |> TraceFilter.apply(filter_opts)
    |> decorate_span_hierarchy(trace_started_at)
    |> mark_critical_path()
    |> maybe_take(limit)
  end

  def list_trace_spans(_, _), do: []

  @spec trace_entity_rollups(String.t(), keyword()) :: [map()]
  def trace_entity_rollups(trace_id, opts \\ [])

  def trace_entity_rollups(trace_id, opts) when is_binary(trace_id) do
    list_trace_spans(trace_id, opts)
    |> Enum.reduce(%{}, fn span, acc ->
      entity_type = normalize_optional_string(span[:entity_type]) || "other"
      duration = span[:duration_ms] || 0
      errors = if(span[:status] == "error" or span[:error] == true, do: 1, else: 0)

      Map.update(
        acc,
        entity_type,
        %{entity_type: entity_type, duration_ms: duration, count: 1, errors: errors},
        fn existing ->
          %{
            existing
            | duration_ms: existing.duration_ms + duration,
              count: existing.count + 1,
              errors: existing.errors + errors
          }
        end
      )
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.duration_ms, &1.count}, :desc)
  end

  def trace_entity_rollups(_, _), do: []

  defp trace_matches_filters?(trace, filters) when is_map(trace) do
    status_filter =
      normalize_status_filter(Map.get(filters, :status) || Map.get(filters, "status"))

    agent_filter =
      normalize_optional_string(Map.get(filters, :agent) || Map.get(filters, "agent"))

    {from_ms, to_ms} =
      time_range_bounds(
        Map.get(filters, :range) || Map.get(filters, "range"),
        Map.get(filters, :from) || Map.get(filters, "from"),
        Map.get(filters, :to) || Map.get(filters, "to")
      )

    status_ok =
      case status_filter do
        nil -> true
        "all" -> true
        status -> normalize_optional_string(Map.get(trace, :status)) == status
      end

    agent_ok =
      case agent_filter do
        nil ->
          true

        value ->
          trace
          |> Map.get(:agent_id)
          |> normalize_optional_string()
          |> case do
            nil -> false
            trace_agent -> String.contains?(String.downcase(trace_agent), String.downcase(value))
          end
      end

    ts = trace_time(trace)
    time_ok = within_time_bounds?(ts, from_ms, to_ms)

    status_ok and agent_ok and time_ok
  end

  defp trace_matches_filters?(_, _), do: false

  defp trace_time(trace) when is_map(trace) do
    Map.get(trace, :started_at) || Map.get(trace, :last_event_at)
  end

  defp trace_sort_key(trace) when is_map(trace) do
    Map.get(trace, :started_at) || Map.get(trace, :last_event_at) || 0
  end

  defp normalize_status_filter(nil), do: nil

  defp normalize_status_filter(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if normalized in ["running", "ok", "error", "all"] do
      normalized
    else
      nil
    end
  end

  defp normalize_status_filter(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_status_filter()
  end

  defp normalize_status_filter(_), do: nil

  defp normalize_optional_string(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil

  defp time_range_bounds(range, from, to) do
    case normalize_optional_string(range) do
      "15m" -> {now_ms() - :timer.minutes(15), now_ms()}
      "1h" -> {now_ms() - :timer.hours(1), now_ms()}
      "24h" -> {now_ms() - :timer.hours(24), now_ms()}
      "custom" -> {parse_datetime_local(from), parse_datetime_local(to)}
      _ -> {now_ms() - :timer.hours(1), now_ms()}
    end
  end

  defp within_time_bounds?(_timestamp, nil, nil), do: true
  defp within_time_bounds?(nil, _from_ms, _to_ms), do: false

  defp within_time_bounds?(timestamp, from_ms, to_ms) do
    from_ok = is_nil(from_ms) or timestamp >= from_ms
    to_ok = is_nil(to_ms) or timestamp <= to_ms
    from_ok and to_ok
  end

  defp parse_datetime_local(value) when is_binary(value) and value != "" do
    case NaiveDateTime.from_iso8601(value <> ":00") do
      {:ok, naive} ->
        naive
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix(:millisecond)

      _ ->
        nil
    end
  end

  defp parse_datetime_local(_), do: nil

  defp decorate_span_hierarchy(spans, trace_started_at) do
    spans_by_id = Map.new(spans, fn span -> {span[:span_id], span} end)

    children_by_parent =
      Enum.reduce(spans, %{}, fn span, acc ->
        parent = span[:parent_span_id]
        Map.update(acc, parent, [span], fn existing -> [span | existing] end)
      end)

    roots =
      spans
      |> Enum.filter(fn span ->
        parent = span[:parent_span_id]
        is_nil(parent) or not Map.has_key?(spans_by_id, parent)
      end)
      |> Enum.sort_by(&span_sort_key/1, :asc)

    ordered =
      Enum.flat_map(roots, fn root ->
        flatten_span_tree(root, children_by_parent, 0)
      end)

    # If cycles/orphans exist, ensure every span still appears once.
    seen = MapSet.new(Enum.map(ordered, & &1[:span_id]))

    extra =
      spans
      |> Enum.reject(&MapSet.member?(seen, &1[:span_id]))
      |> Enum.sort_by(&span_sort_key/1, :asc)
      |> Enum.map(&decorate_span(&1, 0, trace_started_at))

    (ordered ++ extra)
    |> Enum.map(&decorate_span_offsets(&1, trace_started_at))
  end

  defp mark_critical_path(spans) when is_list(spans) do
    by_id = Map.new(spans, fn span -> {span[:span_id], span} end)

    children_by_parent =
      Enum.reduce(spans, %{}, fn span, acc ->
        parent = span[:parent_span_id]
        Map.update(acc, parent, [span], &[span | &1])
      end)

    roots =
      spans
      |> Enum.filter(fn span ->
        parent = span[:parent_span_id]
        is_nil(parent) or not Map.has_key?(by_id, parent)
      end)
      |> Enum.sort_by(&span_sort_key/1, :asc)

    {_, path} =
      Enum.reduce(roots, {0, []}, fn root, {best_duration, best_path} ->
        {duration, current_path} = longest_path(root, children_by_parent)

        if duration > best_duration do
          {duration, current_path}
        else
          {best_duration, best_path}
        end
      end)

    path_ids = MapSet.new(Enum.map(path, & &1[:span_id]))
    Enum.map(spans, &Map.put(&1, :critical_path, MapSet.member?(path_ids, &1[:span_id])))
  end

  defp mark_critical_path(other), do: other

  defp longest_path(span, children_by_parent) do
    children = Map.get(children_by_parent, span[:span_id], [])

    if children == [] do
      {span_duration(span), [span]}
    else
      {child_duration, child_path} =
        Enum.reduce(children, {0, []}, fn child, {best_duration, best_path} ->
          {duration, path} = longest_path(child, children_by_parent)
          if duration > best_duration, do: {duration, path}, else: {best_duration, best_path}
        end)

      {span_duration(span) + child_duration, [span | child_path]}
    end
  end

  defp span_duration(span) when is_map(span) do
    value = Map.get(span, :duration_ms)
    if is_integer(value) and value >= 0, do: value, else: 0
  end

  defp span_duration(_), do: 0

  defp flatten_span_tree(span, children_by_parent, depth) do
    decorated = Map.put(span, :depth, depth)

    children =
      children_by_parent
      |> Map.get(span[:span_id], [])
      |> Enum.sort_by(&span_sort_key/1, :asc)

    [decorated | Enum.flat_map(children, &flatten_span_tree(&1, children_by_parent, depth + 1))]
  end

  defp decorate_span(span, depth, trace_started_at) do
    span
    |> Map.put(:depth, depth)
    |> decorate_span_offsets(trace_started_at)
  end

  defp decorate_span_offsets(span, trace_started_at) do
    started_at = span[:started_at]

    offset_ms =
      if is_integer(started_at) and is_integer(trace_started_at) do
        max(started_at - trace_started_at, 0)
      else
        nil
      end

    Map.put(span, :offset_ms, offset_ms)
  end

  defp span_sort_key(span) when is_map(span) do
    span[:started_at] || span[:last_event_at] || 0
  end

  defp normalize_limit(value) when is_integer(value) and value > 0, do: value
  defp normalize_limit(_), do: @default_limit

  defp normalize_limit(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_limit(_value, default), do: default

  defp normalize_order(:asc), do: :asc
  defp normalize_order(:desc), do: :desc
  defp normalize_order("asc"), do: :asc
  defp normalize_order("desc"), do: :desc
  defp normalize_order(_), do: :asc

  defp trace_filter_opts(filters) do
    [
      hide_internal: normalize_boolean(filters[:hide_internal] || filters["hide_internal"]),
      entity_type: filters[:entity_type] || filters["entity_type"],
      status: filters[:status] || filters["status"],
      stream_only: normalize_boolean(filters[:stream_only] || filters["stream_only"]),
      query: filters[:query] || filters["query"]
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp normalize_boolean(nil), do: nil
  defp normalize_boolean(true), do: true
  defp normalize_boolean(false), do: false
  defp normalize_boolean("true"), do: true
  defp normalize_boolean("false"), do: false
  defp normalize_boolean("1"), do: true
  defp normalize_boolean("0"), do: false
  defp normalize_boolean(_), do: nil

  defp maybe_take(list, limit) when is_integer(limit) and limit > 0, do: Enum.take(list, limit)
  defp maybe_take(list, _limit), do: list

  defp now_ms, do: System.system_time(:millisecond)
end
