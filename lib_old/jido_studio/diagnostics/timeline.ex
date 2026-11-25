defmodule JidoStudio.Diagnostics.Timeline do
  @moduledoc false

  alias JidoStudio.Cluster.RPC
  alias JidoStudio.TraceFilter
  alias JidoStudio.Tracing

  @default_trace_limit 25
  @default_range "1h"
  @default_span_cap 2_000
  @entity_types ~w(all agent model tool middleware scheduler sensor other)

  @spec entity_types() :: [String.t()]
  def entity_types, do: @entity_types

  @spec build(map(), [map()], keyword()) :: map()
  def build(trace, spans, opts \\ [])

  def build(trace, spans, opts) when is_map(trace) and is_list(spans) and is_list(opts) do
    span_cap = normalize_span_cap(Keyword.get(opts, :span_cap))
    critical? = truthy?(Keyword.get(opts, :critical), true)
    selected_span_id = normalize_optional_string(Keyword.get(opts, :selected_span_id))

    warnings =
      opts
      |> Keyword.get(:warnings, [])
      |> List.wrap()
      |> Enum.filter(&is_binary/1)

    trace_started_at = int_or_nil(trace[:started_at])
    trace_duration_ms = int_or_nil(trace[:duration_ms])

    normalized_spans =
      Enum.map(spans, fn span ->
        normalize_span(span, trace_started_at)
      end)

    timing_unavailable_count = Enum.count(normalized_spans, &(not &1.timed?))

    timed_spans =
      normalized_spans
      |> Enum.filter(& &1.timed?)
      |> maybe_clear_critical(critical?)

    chart_duration_ms = chart_duration_ms(trace_duration_ms, timed_spans)

    timed_spans =
      Enum.map(timed_spans, fn span ->
        decorate_percentages(span, chart_duration_ms)
      end)

    selected_span = Enum.find(timed_spans, &(&1.span_id == selected_span_id))

    truncated? = span_cap_reached?(trace, spans, span_cap)

    warnings =
      warnings
      |> maybe_add_warning(
        truncated?,
        "Span cap reached for this timeline. Refine filters for more detail."
      )
      |> maybe_add_warning(
        timing_unavailable_count > 0,
        "#{timing_unavailable_count} spans are missing timing data and are hidden from waterfall bars."
      )
      |> maybe_add_warning(
        is_binary(selected_span_id) and is_nil(selected_span),
        "Selected span is unavailable under current filters."
      )
      |> Enum.uniq()

    %{
      trace_id: trace[:trace_id] || trace[:id],
      trace_started_at: trace_started_at,
      trace_duration_ms: trace_duration_ms || chart_duration_ms,
      chart_duration_ms: chart_duration_ms,
      span_cap: span_cap,
      total_spans: length(spans),
      timed_span_count: length(timed_spans),
      timing_unavailable_count: timing_unavailable_count,
      spans: timed_spans,
      lanes: build_lanes(timed_spans),
      selected_span_id: selected_span_id,
      selected_span: selected_span,
      critical_path_ids:
        Enum.flat_map(timed_spans, &if(&1.critical_path?, do: [&1.span_id], else: [])),
      critical?: critical?,
      truncated?: truncated?,
      warnings: warnings
    }
  end

  def build(_trace, _spans, opts) when is_list(opts) do
    span_cap = normalize_span_cap(Keyword.get(opts, :span_cap))

    %{
      trace_id: nil,
      trace_started_at: nil,
      trace_duration_ms: nil,
      chart_duration_ms: 1,
      span_cap: span_cap,
      total_spans: 0,
      timed_span_count: 0,
      timing_unavailable_count: 0,
      spans: [],
      lanes: [],
      selected_span_id: nil,
      selected_span: nil,
      critical_path_ids: [],
      critical?: truthy?(Keyword.get(opts, :critical), true),
      truncated?: false,
      warnings: []
    }
  end

  @spec pick_recent_traces(term(), keyword()) :: [map()]
  def pick_recent_traces(scope, opts \\ []) do
    limit = normalize_limit(Keyword.get(opts, :limit), @default_trace_limit)
    range = normalize_optional_string(Keyword.get(opts, :range)) || @default_range
    query_opts = [filters: %{range: range}, limit: limit]

    scope
    |> RPC.call(Tracing, :list_traces, [query_opts])
    |> case do
      {:ok, [%{ok?: _} | _] = node_results} ->
        node_results
        |> Enum.flat_map(fn
          %{ok?: true, node: node, value: value} when is_list(value) ->
            Enum.map(value, &trace_summary(&1, node))

          trace when is_map(trace) ->
            if Map.has_key?(trace, :trace_id) or Map.has_key?(trace, :id) do
              [trace_summary(trace, Node.self())]
            else
              []
            end

          _ ->
            []
        end)

      {:ok, traces} when is_list(traces) ->
        Enum.map(traces, &trace_summary(&1, Node.self()))

      _ ->
        []
    end
    |> Enum.reject(&is_nil(&1.trace_id))
    |> Enum.reduce(%{}, fn summary, acc ->
      key = "#{summary.node}:#{summary.trace_id}"
      Map.put_new(acc, key, summary)
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.started_at || 0, &1.trace_id}, :desc)
    |> Enum.take(limit)
  end

  defp trace_summary(trace, node) when is_map(trace) do
    %{
      trace_id: normalize_optional_string(trace[:trace_id] || trace[:id]),
      agent_id: normalize_optional_string(trace[:agent_id]),
      status: normalize_optional_string(trace[:status]) || "running",
      started_at: int_or_nil(trace[:started_at] || trace[:last_event_at]),
      duration_ms: int_or_nil(trace[:duration_ms]),
      node: to_string(node)
    }
  end

  defp chart_duration_ms(trace_duration_ms, spans) do
    spans_duration =
      spans
      |> Enum.map(&((&1.offset_ms || 0) + (&1.duration_ms || 0)))
      |> Enum.max(fn -> 0 end)

    max(trace_duration_ms || 0, spans_duration)
    |> max(1)
  end

  defp decorate_percentages(span, chart_duration_ms) do
    left_pct = 100.0 * span.offset_ms / chart_duration_ms
    width_pct = 100.0 * max(span.duration_ms, 1) / chart_duration_ms

    span
    |> Map.put(:left_pct, clamp_percentage(left_pct))
    |> Map.put(:width_pct, clamp_percentage(max(width_pct, 0.8)))
  end

  defp clamp_percentage(value) when is_float(value) do
    value
    |> max(0.0)
    |> min(100.0)
  end

  defp maybe_clear_critical(spans, true), do: spans

  defp maybe_clear_critical(spans, false) do
    Enum.map(spans, &Map.put(&1, :critical_path?, false))
  end

  defp build_lanes(spans) do
    spans
    |> Enum.group_by(& &1.lane_key)
    |> Enum.map(fn {lane_key, lane_spans} ->
      first = Enum.min_by(lane_spans, & &1.offset_ms)
      total_duration = Enum.reduce(lane_spans, 0, &(&1.duration_ms + &2))

      %{
        key: lane_key,
        label: first.lane_label,
        entity_type: first.entity_type,
        entity_id: first.entity_id,
        first_offset_ms: first.offset_ms,
        count: length(lane_spans),
        duration_ms: total_duration
      }
    end)
    |> Enum.sort_by(&{&1.first_offset_ms, &1.label}, :asc)
  end

  defp normalize_span(span, trace_started_at) when is_map(span) do
    span_id = normalize_optional_string(span[:span_id]) || "span-#{:erlang.phash2(span)}"
    entity_type = normalize_entity_type(span[:entity_type])

    entity_id =
      span[:entity_id] ||
        span[:agent_id] ||
        span[:tool_name] ||
        span[:action] ||
        span[:workflow_id] ||
        span[:event_name] ||
        span_id
        |> normalize_optional_string()

    lane_key = "#{entity_type}:#{entity_id || "unknown"}"

    offset_ms =
      int_or_nil(span[:offset_ms]) ||
        derive_offset(int_or_nil(span[:started_at]), trace_started_at)

    duration_ms =
      int_or_nil(span[:duration_ms]) ||
        derive_duration(int_or_nil(span[:started_at]), int_or_nil(span[:ended_at]))

    timed? =
      is_integer(offset_ms) and offset_ms >= 0 and is_integer(duration_ms) and duration_ms >= 0

    %{
      span_id: span_id,
      parent_span_id: normalize_optional_string(span[:parent_span_id]),
      event_name: normalize_optional_string(span[:event_name]) || span_id,
      status: normalize_optional_string(span[:status]) || "running",
      entity_type: entity_type,
      entity_id: entity_id,
      lane_key: lane_key,
      lane_label: "#{entity_type} · #{entity_id || "unknown"}",
      offset_ms: offset_ms,
      duration_ms: duration_ms,
      depth: int_or_nil(span[:depth]) || 0,
      critical_path?: truthy?(span[:critical_path], false),
      call_id: normalize_optional_string(span[:call_id]),
      task_id: normalize_optional_string(span[:task_id]),
      trace_id: normalize_optional_string(span[:trace_id]),
      timed?: timed?
    }
  end

  defp normalize_span(_span, _trace_started_at) do
    %{
      span_id: "unknown",
      parent_span_id: nil,
      event_name: "unknown",
      status: "running",
      entity_type: "other",
      entity_id: "unknown",
      lane_key: "other:unknown",
      lane_label: "other · unknown",
      offset_ms: nil,
      duration_ms: nil,
      depth: 0,
      critical_path?: false,
      call_id: nil,
      task_id: nil,
      trace_id: nil,
      timed?: false
    }
  end

  defp derive_offset(started_at, trace_started_at)
       when is_integer(started_at) and is_integer(trace_started_at) do
    max(started_at - trace_started_at, 0)
  end

  defp derive_offset(_started_at, _trace_started_at), do: nil

  defp derive_duration(started_at, ended_at)
       when is_integer(started_at) and is_integer(ended_at) do
    if ended_at >= started_at, do: ended_at - started_at, else: nil
  end

  defp derive_duration(_started_at, _ended_at), do: nil

  defp span_cap_reached?(trace, spans, span_cap) when is_map(trace) and is_list(spans) do
    trace_span_count = int_or_nil(trace[:span_count])

    cond do
      is_integer(trace_span_count) and trace_span_count > length(spans) ->
        true

      length(spans) >= span_cap ->
        true

      true ->
        false
    end
  end

  defp span_cap_reached?(_trace, _spans, _span_cap), do: false

  defp maybe_add_warning(warnings, true, message) when is_binary(message),
    do: [message | warnings]

  defp maybe_add_warning(warnings, _predicate, _message), do: warnings

  defp int_or_nil(value) when is_integer(value), do: value
  defp int_or_nil(value) when is_float(value), do: trunc(value)
  defp int_or_nil(_), do: nil

  defp normalize_entity_type(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_entity_type(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))
    if normalized in tl(@entity_types), do: normalized, else: "other"
  end

  defp normalize_entity_type(_), do: "other"

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil

  defp truthy?(nil, default), do: default
  defp truthy?(true, _default), do: true
  defp truthy?("true", _default), do: true
  defp truthy?("1", _default), do: true
  defp truthy?(1, _default), do: true
  defp truthy?(false, _default), do: false
  defp truthy?("false", _default), do: false
  defp truthy?("0", _default), do: false
  defp truthy?(0, _default), do: false
  defp truthy?(_value, default), do: default

  defp normalize_limit(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_limit(_value, default), do: default

  defp normalize_span_cap(nil) do
    min(TraceFilter.max_span_rows(), @default_span_cap)
  end

  defp normalize_span_cap(value) when is_integer(value) and value > 0 do
    max(1, min(value, @default_span_cap))
  end

  defp normalize_span_cap(_value), do: min(TraceFilter.max_span_rows(), @default_span_cap)
end
