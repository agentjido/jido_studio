defmodule JidoStudio.Observability.Actions do
  @moduledoc false

  alias JidoStudio.Observability.Correlation
  alias JidoStudio.Observability.Filters
  alias JidoStudio.Persistence

  @namespace "actions"
  @default_limit 120

  @spec list_actions(keyword()) :: [map()]
  def list_actions(opts \\ []) do
    filters = Keyword.get(opts, :filters, %{}) |> parse_filters()
    limit = Filters.normalize_limit(Keyword.get(opts, :limit, @default_limit), @default_limit)
    bounds = Filters.time_bounds(filters)

    Persistence.list_docs(@namespace,
      order: :desc,
      sort_by: :last_event_at,
      limit: max(limit * 4, 200)
    )
    |> Enum.filter(&matches_filters?(&1, filters, bounds))
    |> Enum.map(&decorate_action/1)
    |> Enum.sort_by(&action_sort_key/1, :desc)
    |> Enum.take(limit)
  end

  @spec get_action(String.t()) :: {:ok, map()} | :not_found | {:error, term()}
  def get_action(action_id) when is_binary(action_id) do
    Persistence.get_doc(@namespace, action_id)
  end

  def get_action(_), do: :not_found

  @spec latest_executions(String.t(), keyword()) :: [map()]
  def latest_executions(action_id, opts \\ [])

  def latest_executions(action_id, opts) when is_binary(action_id) do
    limit = Filters.normalize_limit(Keyword.get(opts, :limit, 40), 40)

    action_stream(action_id)
    |> Persistence.read_events(order: :desc, limit: max(limit * 2, 80))
    |> Enum.map(&Correlation.normalize/1)
    |> Enum.filter(&execution_event?/1)
    |> Enum.sort_by(&(&1[:ts] || 0), :desc)
    |> Enum.take(limit)
  end

  def latest_executions(_, _), do: []

  @spec failure_samples(String.t(), keyword()) :: [map()]
  def failure_samples(action_id, opts \\ [])

  def failure_samples(action_id, opts) when is_binary(action_id) do
    limit = Filters.normalize_limit(Keyword.get(opts, :limit, 10), 10)

    latest_executions(action_id, limit: 80)
    |> Enum.filter(&error_event?/1)
    |> Enum.take(limit)
  end

  def failure_samples(_, _), do: []

  defp parse_filters(filters) do
    defaults =
      Filters.default_filters(%{
        range: "24h",
        status: "all",
        action: nil,
        query: nil,
        agent_id: nil,
        project_id: nil,
        user_id: nil,
        error_only: false
      })

    parsed = Filters.parse(filters, defaults)

    module_filter =
      filters
      |> normalize_input_map()
      |> fetch(:agent_module)
      |> Filters.normalize_optional_string()

    Map.put(parsed, :agent_module, module_filter)
  end

  defp matches_filters?(action, filters, bounds) do
    ts = action_sort_key(action)

    Filters.within_bounds?(ts, bounds) and
      status_match?(action, filters) and
      Filters.match_string(action[:action], filters[:action]) and
      Filters.match_string(action[:agent_id], filters[:agent_id]) and
      Filters.match_string(action[:agent_module], filters[:agent_module]) and
      Filters.match_string(action[:project_id], filters[:project_id]) and
      Filters.match_string(action[:user_id], filters[:user_id]) and
      Filters.match_string(action[:trace_id], filters[:trace_id]) and
      Filters.match_string(action[:incident_id], filters[:incident_id]) and
      query_match?(action, filters[:query])
  end

  defp status_match?(action, %{error_only: true}),
    do: normalize_status(action[:last_status]) == "error"

  defp status_match?(_action, %{status: "all"}), do: true

  defp status_match?(action, %{status: status}) do
    normalize_status(action[:last_status]) == normalize_status(status)
  end

  defp status_match?(_action, _), do: true

  defp query_match?(_action, nil), do: true

  defp query_match?(action, query) do
    query_text = String.downcase(to_string(query || ""))

    [
      action[:action],
      action[:agent_module],
      action[:agent_id],
      action[:trace_id],
      action[:incident_id]
    ]
    |> Enum.map(&to_string(&1 || ""))
    |> Enum.join(" ")
    |> String.downcase()
    |> String.contains?(query_text)
  end

  defp decorate_action(action) do
    call_count = normalize_non_negative_integer(action[:execution_count])
    failure_count = normalize_non_negative_integer(action[:failure_count])

    action
    |> Map.put(:execution_count, call_count)
    |> Map.put(:failure_count, failure_count)
    |> Map.put(:error_rate, failure_ratio(call_count, failure_count))
    |> Map.put(:p50_duration_ms, normalize_non_negative_integer(action[:p50_duration_ms]))
    |> Map.put(:p95_duration_ms, normalize_non_negative_integer(action[:p95_duration_ms]))
  end

  defp execution_event?(event) when is_map(event) do
    type = normalize_optional_string(event[:type])
    type in ["start", "stop", "exception"]
  end

  defp execution_event?(_), do: false

  defp error_event?(event) when is_map(event) do
    normalize_status(event[:status]) == "error" or
      normalize_optional_string(event[:type]) == "exception"
  end

  defp error_event?(_), do: false

  defp action_sort_key(action) when is_map(action) do
    action[:last_event_at] || action[:updated_at] || action[:started_at] || 0
  end

  defp action_sort_key(_), do: 0

  defp failure_ratio(0, _), do: 0.0

  defp failure_ratio(call_count, failure_count)
       when is_integer(call_count) and is_integer(failure_count) and call_count > 0 do
    failure_count / call_count
  end

  defp failure_ratio(_, _), do: 0.0

  defp normalize_status(value) when value in [:running, :ok, :error], do: Atom.to_string(value)

  defp normalize_status(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))
    if normalized in ["running", "ok", "error"], do: normalized, else: "running"
  end

  defp normalize_status(_), do: "running"

  defp normalize_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_), do: nil

  defp normalize_non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp normalize_non_negative_integer(_), do: 0

  defp action_stream(action_id), do: "action:" <> action_id

  defp normalize_input_map(nil), do: %{}

  defp normalize_input_map(filters) when is_list(filters) do
    filters
    |> Enum.into(%{})
    |> normalize_input_map()
  end

  defp normalize_input_map(filters) when is_map(filters) do
    Map.get(filters, "filters", filters)
  end

  defp normalize_input_map(_), do: %{}

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp fetch(_, _), do: nil
end
