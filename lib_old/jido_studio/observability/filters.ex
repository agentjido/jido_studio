defmodule JidoStudio.Observability.Filters do
  @moduledoc false

  @default_range "1h"
  @ranges ["15m", "1h", "24h", "7d", "custom", "all"]

  @default_filters %{
    range: @default_range,
    from: nil,
    to: nil,
    query: nil,
    status: "all",
    agent_id: nil,
    project_id: nil,
    user_id: nil,
    trace_id: nil,
    incident_id: nil,
    action: nil,
    workflow_id: nil,
    signal_type: nil,
    request_id: nil,
    error_only: false,
    stalled_only: false
  }

  @spec default_filters(map()) :: map()
  def default_filters(overrides \\ %{}) when is_map(overrides) do
    Map.merge(@default_filters, overrides)
  end

  @spec parse(map() | keyword() | nil, map()) :: map()
  def parse(params, defaults \\ @default_filters)

  def parse(nil, defaults), do: defaults

  def parse(params, defaults) when is_list(params) do
    params
    |> Enum.into(%{})
    |> parse(defaults)
  end

  def parse(params, defaults) when is_map(params) and is_map(defaults) do
    source = Map.get(params, "filters", params)

    defaults
    |> Map.merge(%{
      range: normalize_range(fetch(source, :range, defaults.range)),
      from: normalize_optional_string(fetch(source, :from, defaults.from)),
      to: normalize_optional_string(fetch(source, :to, defaults.to)),
      query: normalize_optional_string(fetch(source, :query, defaults.query)),
      status: normalize_status(fetch(source, :status, defaults.status)),
      agent_id: normalize_optional_string(fetch(source, :agent_id, defaults.agent_id)),
      project_id: normalize_optional_string(fetch(source, :project_id, defaults.project_id)),
      user_id: normalize_optional_string(fetch(source, :user_id, defaults.user_id)),
      trace_id: normalize_optional_string(fetch(source, :trace_id, defaults.trace_id)),
      incident_id: normalize_optional_string(fetch(source, :incident_id, defaults.incident_id)),
      action: normalize_optional_string(fetch(source, :action, defaults.action)),
      workflow_id: normalize_optional_string(fetch(source, :workflow_id, defaults.workflow_id)),
      signal_type: normalize_optional_string(fetch(source, :signal_type, defaults.signal_type)),
      request_id: normalize_optional_string(fetch(source, :request_id, defaults.request_id)),
      error_only: normalize_checkbox(fetch(source, :error_only, defaults.error_only), false),
      stalled_only: normalize_checkbox(fetch(source, :stalled_only, defaults.stalled_only), false)
    })
    |> maybe_clear_bounds()
  end

  @spec time_bounds(map()) :: {integer() | nil, integer() | nil}
  def time_bounds(filters) when is_map(filters) do
    case filters.range do
      "15m" -> {now_ms() - :timer.minutes(15), now_ms()}
      "1h" -> {now_ms() - :timer.hours(1), now_ms()}
      "24h" -> {now_ms() - :timer.hours(24), now_ms()}
      "7d" -> {now_ms() - :timer.hours(24 * 7), now_ms()}
      "custom" -> {parse_datetime_local(filters.from), parse_datetime_local(filters.to)}
      "all" -> {nil, nil}
      _ -> {now_ms() - :timer.hours(1), now_ms()}
    end
  end

  def time_bounds(_), do: {nil, nil}

  @spec within_bounds?(integer() | nil, {integer() | nil, integer() | nil}) :: boolean()
  def within_bounds?(nil, _bounds), do: false

  def within_bounds?(ts, {from_ms, to_ms}) when is_integer(ts) do
    from_ok = is_nil(from_ms) or ts >= from_ms
    to_ok = is_nil(to_ms) or ts <= to_ms
    from_ok and to_ok
  end

  def within_bounds?(_, _), do: false

  @spec normalize_limit(term(), pos_integer()) :: pos_integer()
  def normalize_limit(value, _default) when is_integer(value) and value > 0, do: value
  def normalize_limit(_value, default), do: default

  @spec to_query_params(map(), map()) :: map()
  def to_query_params(filters, defaults \\ @default_filters)

  def to_query_params(filters, defaults) when is_map(filters) and is_map(defaults) do
    %{}
    |> maybe_put("range", diff(filters.range, defaults.range))
    |> maybe_put("from", if(filters.range == "custom", do: filters.from, else: nil))
    |> maybe_put("to", if(filters.range == "custom", do: filters.to, else: nil))
    |> maybe_put("query", diff(filters.query, defaults.query))
    |> maybe_put("status", diff(filters.status, defaults.status))
    |> maybe_put("agent_id", diff(filters.agent_id, defaults.agent_id))
    |> maybe_put("project_id", diff(filters.project_id, defaults.project_id))
    |> maybe_put("user_id", diff(filters.user_id, defaults.user_id))
    |> maybe_put("trace_id", diff(filters.trace_id, defaults.trace_id))
    |> maybe_put("incident_id", diff(filters.incident_id, defaults.incident_id))
    |> maybe_put("action", diff(filters.action, defaults.action))
    |> maybe_put("workflow_id", diff(filters.workflow_id, defaults.workflow_id))
    |> maybe_put("signal_type", diff(filters.signal_type, defaults.signal_type))
    |> maybe_put("request_id", diff(filters.request_id, defaults.request_id))
    |> maybe_put("error_only", bool_param(filters.error_only, defaults.error_only))
    |> maybe_put("stalled_only", bool_param(filters.stalled_only, defaults.stalled_only))
  end

  def to_query_params(_, _), do: %{}

  @spec normalize_checkbox(term(), boolean()) :: boolean()
  def normalize_checkbox(nil, default), do: default
  def normalize_checkbox(true, _default), do: true
  def normalize_checkbox(false, _default), do: false
  def normalize_checkbox("true", _default), do: true
  def normalize_checkbox("1", _default), do: true
  def normalize_checkbox("on", _default), do: true
  def normalize_checkbox("false", _default), do: false
  def normalize_checkbox("0", _default), do: false
  def normalize_checkbox(_, default), do: default

  @spec normalize_optional_string(term()) :: String.t() | nil
  def normalize_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  def normalize_optional_string(nil), do: nil
  def normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  def normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  def normalize_optional_string(_), do: nil

  @spec match_string(term(), term()) :: boolean()
  def match_string(_actual, nil), do: true

  def match_string(actual, expected) do
    case {normalize_optional_string(actual), normalize_optional_string(expected)} do
      {nil, _} ->
        false

      {_, nil} ->
        true

      {actual_text, expected_text} ->
        String.contains?(String.downcase(actual_text), String.downcase(expected_text))
    end
  end

  defp maybe_clear_bounds(%{range: "custom"} = filters), do: filters
  defp maybe_clear_bounds(filters), do: %{filters | from: nil, to: nil}

  defp normalize_range(nil), do: @default_range

  defp normalize_range(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))
    if normalized in @ranges, do: normalized, else: @default_range
  end

  defp normalize_range(_), do: @default_range

  defp normalize_status(nil), do: "all"

  defp normalize_status(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))
    if normalized in ["all", "running", "ok", "error"], do: normalized, else: "all"
  end

  defp normalize_status(value) when value in [:running, :ok, :error, :all],
    do: Atom.to_string(value)

  defp normalize_status(_), do: "all"

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

  defp fetch(source, key, default) do
    Map.get(source, Atom.to_string(key), Map.get(source, key, default))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp diff(value, default) do
    if value == default, do: nil, else: value
  end

  defp bool_param(value, default) when value == default, do: nil
  defp bool_param(true, _default), do: "true"
  defp bool_param(false, _default), do: "false"

  defp now_ms, do: System.system_time(:millisecond)
end
