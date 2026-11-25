defmodule JidoStudio.Observability.Incidents do
  @moduledoc false

  alias JidoStudio.Observability.Correlation
  alias JidoStudio.Observability.Filters
  alias JidoStudio.Persistence
  alias JidoStudio.Tracing

  @namespace "incidents"
  @default_query_limit 200
  @default_retention_ms :timer.hours(24)

  @spec incident_index_enabled?() :: boolean()
  def incident_index_enabled? do
    Application.get_env(:jido_studio, :incident_index_enabled, true) != false
  end

  @spec incident_query_limit() :: pos_integer()
  def incident_query_limit do
    Application.get_env(:jido_studio, :incident_query_limit, @default_query_limit)
    |> Filters.normalize_limit(@default_query_limit)
  end

  @spec incident_retention_ms() :: pos_integer()
  def incident_retention_ms do
    Application.get_env(:jido_studio, :incident_retention, @default_retention_ms)
    |> normalize_retention()
  end

  @spec ingest_event(map()) :: :ok
  def ingest_event(event) when is_map(event) do
    if incident_index_enabled?() do
      normalized = Correlation.normalize(event)
      incident_id = normalized[:incident_id]

      if is_binary(incident_id) do
        existing =
          case Persistence.get_doc(@namespace, incident_id) do
            {:ok, doc} when is_map(doc) -> doc
            _ -> %{id: incident_id, incident_id: incident_id}
          end

        ts = normalized[:ts] || now_ms()

        updated =
          existing
          |> Map.put(:incident_id, incident_id)
          |> Map.put(:request_id, normalized[:request_id] || existing[:request_id])
          |> Map.put(:started_at, min_timestamp(existing[:started_at], ts) || ts)
          |> Map.put(:last_event_at, ts)
          |> Map.put(:status, next_status(existing[:status], normalized))
          |> Map.put(:event_count, normalize_non_negative_integer(existing[:event_count]) + 1)
          |> Map.put(:error_count, error_count(existing[:error_count], normalized))
          |> Map.put(:latest_trace_id, normalized[:trace_id] || existing[:latest_trace_id])
          |> Map.put(:latest_agent_id, normalized[:agent_id] || existing[:latest_agent_id])
          |> Map.put(:latest_action, normalized[:action] || existing[:latest_action])
          |> Map.put(
            :latest_workflow_id,
            normalized[:workflow_id] || existing[:latest_workflow_id]
          )
          |> Map.put(
            :latest_signal_type,
            normalized[:signal_type] || existing[:latest_signal_type]
          )
          |> Map.put(:project_id, normalized[:project_id] || existing[:project_id])
          |> Map.put(:user_id, normalized[:user_id] || existing[:user_id])
          |> Map.put(:scope, merge_scope(existing[:scope], normalized[:scope]))
          |> Map.put(:trace_ids, append_unique(existing[:trace_ids], normalized[:trace_id]))
          |> Map.put(:agent_ids, append_unique(existing[:agent_ids], normalized[:agent_id]))
          |> Map.put(:actions, append_unique(existing[:actions], normalized[:action]))
          |> Map.put(
            :workflow_ids,
            append_unique(existing[:workflow_ids], normalized[:workflow_id])
          )
          |> Map.put(
            :signal_types,
            append_unique(existing[:signal_types], normalized[:signal_type])
          )
          |> Map.put(:project_ids, append_unique(existing[:project_ids], normalized[:project_id]))
          |> Map.put(:user_ids, append_unique(existing[:user_ids], normalized[:user_id]))

        _ = Persistence.put_doc(@namespace, incident_id, updated)
        _ = Persistence.append_event(incident_stream(incident_id), normalized)
      end
    end

    :ok
  rescue
    _ ->
      :ok
  end

  def ingest_event(_), do: :ok

  @spec list_incidents(map() | keyword(), pos_integer() | nil) :: [map()]
  def list_incidents(filters \\ %{}, limit \\ nil) do
    parsed = parse_filters(filters)
    limit = Filters.normalize_limit(limit || incident_query_limit(), incident_query_limit())
    bounds = Filters.time_bounds(parsed)
    cutoff = now_ms() - incident_retention_ms()

    Persistence.list_docs(@namespace,
      order: :desc,
      sort_by: :last_event_at,
      limit: max(limit * 5, 200)
    )
    |> Enum.filter(&incident_matches?(&1, parsed, bounds, cutoff))
    |> Enum.sort_by(&incident_time/1, :desc)
    |> Enum.take(limit)
  end

  @spec incident_timeline(String.t(), map() | keyword()) :: [map()]
  def incident_timeline(incident_id, filters \\ %{})

  def incident_timeline(incident_id, filters) when is_binary(incident_id) do
    parsed = parse_filters(filters)
    bounds = Filters.time_bounds(parsed)
    cutoff = now_ms() - incident_retention_ms()

    limit =
      Filters.normalize_limit(
        extract_limit(filters) || parsed[:limit] || incident_query_limit(),
        incident_query_limit()
      )

    incident_stream(incident_id)
    |> Persistence.read_events(order: :asc, limit: max(limit, 50))
    |> Enum.map(&Correlation.normalize/1)
    |> Enum.filter(&event_matches?(&1, parsed, bounds, cutoff))
    |> Enum.take(limit)
  end

  def incident_timeline(_, _), do: []

  @spec incident_entities(String.t()) :: [map()]
  def incident_entities(incident_id) when is_binary(incident_id) do
    incident_timeline(incident_id, %{range: "all", limit: 1_500})
    |> Enum.reduce(%{}, fn event, acc ->
      acc
      |> increment_entity("agent", event[:agent_id])
      |> increment_entity("action", event[:action])
      |> increment_entity("workflow", event[:workflow_id])
      |> increment_entity("signal", event[:signal_type])
      |> increment_entity("trace", event[:trace_id])
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.count, &1.kind, &1.id}, :desc)
  end

  def incident_entities(_), do: []

  @spec related_traces(String.t()) :: [map()]
  def related_traces(incident_id) when is_binary(incident_id) do
    trace_ids =
      case Persistence.get_doc(@namespace, incident_id) do
        {:ok, incident} when is_map(incident) ->
          incident[:trace_ids] || []

        _ ->
          incident_timeline(incident_id, %{range: "all", limit: 1_500})
          |> Enum.map(& &1[:trace_id])
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
      end

    trace_ids
    |> Enum.map(fn trace_id ->
      case Tracing.get_trace(trace_id) do
        {:ok, trace} -> trace
        _ -> %{trace_id: trace_id, status: "unknown", last_event_at: 0}
      end
    end)
    |> Enum.sort_by(&incident_time/1, :desc)
  end

  def related_traces(_), do: []

  @spec latest_for_agent(String.t(), map() | keyword()) :: map() | nil
  def latest_for_agent(agent_id, filters \\ %{})

  def latest_for_agent(agent_id, filters) when is_binary(agent_id) do
    filters
    |> parse_filters()
    |> Map.put(:agent_id, agent_id)
    |> list_incidents(1)
    |> List.first()
  end

  def latest_for_agent(_, _), do: nil

  defp incident_matches?(incident, filters, bounds, cutoff) when is_map(incident) do
    ts = incident_time(incident)

    ts >= cutoff and
      Filters.within_bounds?(ts, bounds) and
      status_match?(incident, filters[:status], filters[:error_only]) and
      contains_any?(incident[:trace_ids], filters[:trace_id]) and
      contains_any?(incident[:agent_ids], filters[:agent_id]) and
      contains_any?(incident[:actions], filters[:action]) and
      contains_any?(incident[:workflow_ids], filters[:workflow_id]) and
      contains_any?(incident[:signal_types], filters[:signal_type]) and
      contains_any?(incident[:project_ids], filters[:project_id]) and
      contains_any?(incident[:user_ids], filters[:user_id]) and
      request_match?(incident, filters[:request_id]) and
      query_match?(incident, filters[:query])
  end

  defp incident_matches?(_, _, _, _), do: false

  defp event_matches?(event, filters, bounds, cutoff) when is_map(event) do
    ts = event[:ts] || event[:timestamp_ms] || 0

    ts >= cutoff and
      Filters.within_bounds?(ts, bounds) and
      status_match?(event, filters[:status], filters[:error_only]) and
      Filters.match_string(event[:trace_id], filters[:trace_id]) and
      Filters.match_string(event[:agent_id], filters[:agent_id]) and
      Filters.match_string(event[:action], filters[:action]) and
      Filters.match_string(event[:workflow_id], filters[:workflow_id]) and
      Filters.match_string(event[:signal_type], filters[:signal_type]) and
      Filters.match_string(event[:project_id], filters[:project_id]) and
      Filters.match_string(event[:user_id], filters[:user_id]) and
      Filters.match_string(event[:request_id], filters[:request_id]) and
      query_match?(event, filters[:query])
  end

  defp event_matches?(_, _, _, _), do: false

  defp parse_filters(filters) do
    Filters.parse(filters, Filters.default_filters(%{range: "24h"}))
  end

  defp incident_time(map) when is_map(map) do
    map[:last_event_at] || map[:ts] || map[:started_at] || 0
  end

  defp status_match?(item, _status, true) when is_map(item) do
    error_count = normalize_non_negative_integer(item[:error_count])
    status = normalize_optional_string(item[:status])
    error_count > 0 or status == "error" or item[:error] == true
  end

  defp status_match?(_item, "all", _error_only), do: true

  defp status_match?(item, nil, _error_only), do: status_match?(item, "all", false)

  defp status_match?(item, status, _error_only) when is_map(item) do
    normalize_optional_string(item[:status]) == normalize_optional_string(status)
  end

  defp status_match?(_, _, _), do: false

  defp request_match?(_incident, nil), do: true

  defp request_match?(incident, request_id) do
    Filters.match_string(incident[:request_id], request_id)
  end

  defp query_match?(_item, nil), do: true

  defp query_match?(item, query) do
    query_text = String.downcase(to_string(query || ""))

    haystack =
      [
        item[:incident_id],
        item[:latest_agent_id],
        item[:latest_action],
        item[:latest_workflow_id],
        item[:latest_signal_type],
        item[:request_id],
        Enum.join(List.wrap(item[:trace_ids]), " "),
        Enum.join(List.wrap(item[:agent_ids]), " "),
        Enum.join(List.wrap(item[:actions]), " "),
        Enum.join(List.wrap(item[:workflow_ids]), " "),
        Enum.join(List.wrap(item[:signal_types]), " "),
        item[:event_name],
        item[:type]
      ]
      |> Enum.map(&to_string(&1 || ""))
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(haystack, query_text)
  end

  defp contains_any?(_values, nil), do: true

  defp contains_any?(values, expected) do
    values
    |> List.wrap()
    |> Enum.any?(fn value -> Filters.match_string(value, expected) end)
  end

  defp increment_entity(acc, _kind, nil), do: acc

  defp increment_entity(acc, kind, id) do
    key = {kind, id}

    Map.update(acc, key, %{kind: kind, id: id, count: 1}, fn existing ->
      %{existing | count: existing.count + 1}
    end)
  end

  defp append_unique(list, nil), do: List.wrap(list) |> Enum.uniq() |> Enum.take(-100)

  defp append_unique(list, value) do
    (List.wrap(list) ++ [value])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.take(-100)
  end

  defp merge_scope(lhs, rhs) when is_map(lhs) and is_map(rhs), do: Map.merge(lhs, rhs)
  defp merge_scope(nil, rhs) when is_map(rhs), do: rhs
  defp merge_scope(lhs, nil) when is_map(lhs), do: lhs
  defp merge_scope(_, _), do: %{}

  defp error_count(current, event) do
    normalize_non_negative_integer(current) + if(error_event?(event), do: 1, else: 0)
  end

  defp next_status("error", _event), do: "error"

  defp next_status(_current_status, event) when is_map(event) do
    cond do
      error_event?(event) -> "error"
      normalize_optional_string(event[:status]) in ["ok", "running"] -> event[:status]
      normalize_optional_string(event[:type]) == "stop" -> "ok"
      true -> "running"
    end
  end

  defp error_event?(event) when is_map(event) do
    normalize_optional_string(event[:status]) == "error" or
      normalize_optional_string(event[:type]) == "exception" or
      event[:error] == true
  end

  defp error_event?(_), do: false

  defp incident_stream(incident_id), do: "incident:" <> incident_id

  defp normalize_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil

  defp normalize_non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp normalize_non_negative_integer(_), do: 0

  defp min_timestamp(nil, rhs), do: rhs
  defp min_timestamp(lhs, nil), do: lhs
  defp min_timestamp(lhs, rhs), do: min(lhs, rhs)

  defp normalize_retention(value) when is_integer(value) and value > 0, do: value

  defp normalize_retention({:seconds, value}) when is_integer(value) and value > 0,
    do: value * 1_000

  defp normalize_retention({:minutes, value}) when is_integer(value) and value > 0,
    do: value * 60_000

  defp normalize_retention({:hours, value}) when is_integer(value) and value > 0,
    do: value * 3_600_000

  defp normalize_retention(_), do: @default_retention_ms

  defp extract_limit(filters) when is_map(filters) do
    Map.get(filters, :limit) || Map.get(filters, "limit")
  end

  defp extract_limit(filters) when is_list(filters) do
    filters
    |> Enum.into(%{})
    |> extract_limit()
  end

  defp extract_limit(_), do: nil

  defp now_ms, do: System.system_time(:millisecond)
end
