defmodule JidoStudio.Observability.Signals do
  @moduledoc false

  alias JidoStudio.Observability.Correlation
  alias JidoStudio.Observability.Filters
  alias JidoStudio.Persistence

  @stream "events:all"
  @default_limit 250

  @spec list_signals(keyword()) :: [map()]
  def list_signals(opts \\ []) do
    filters = Keyword.get(opts, :filters, %{}) |> parse_filters()
    limit = Filters.normalize_limit(Keyword.get(opts, :limit, @default_limit), @default_limit)
    bounds = Filters.time_bounds(filters)

    events =
      Persistence.read_events(@stream, order: :desc, limit: max(limit * 8, 500))
      |> Enum.map(&Correlation.normalize/1)

    events
    |> Enum.filter(&signal_event?/1)
    |> Enum.filter(&matches_filters?(&1, filters, bounds))
    |> Enum.sort_by(&signal_time/1, :desc)
    |> Enum.take(limit)
  end

  @spec get_signal(String.t() | integer(), keyword()) :: map() | nil
  def get_signal(id, opts \\ []) do
    parsed_id = normalize_signal_id(id)

    if is_integer(parsed_id) do
      list_signals(Keyword.put_new(opts, :limit, 400))
      |> Enum.find(fn signal -> signal[:seq] == parsed_id end)
    else
      nil
    end
  end

  @spec signal_types(keyword()) :: [String.t()]
  def signal_types(opts \\ []) do
    list_signals(Keyword.put_new(opts, :limit, 500))
    |> Enum.map(&normalize_optional_string(&1[:signal_type]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec agents(keyword()) :: [String.t()]
  def agents(opts \\ []) do
    list_signals(Keyword.put_new(opts, :limit, 500))
    |> Enum.map(&normalize_optional_string(&1[:agent_id]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec summary(keyword()) :: map()
  def summary(opts \\ []) do
    signals = list_signals(Keyword.put_new(opts, :limit, 400))

    %{
      total: length(signals),
      errors: Enum.count(signals, &(normalize_optional_string(&1[:status]) == "error")),
      by_type: by_field(signals, :signal_type),
      by_agent: by_field(signals, :agent_id)
    }
  end

  defp parse_filters(filters) do
    defaults =
      Filters.default_filters(%{
        range: "1h",
        signal_type: nil,
        status: "all",
        agent_id: nil,
        project_id: nil,
        user_id: nil,
        error_only: false
      })

    Filters.parse(filters, defaults)
  end

  defp signal_event?(event) when is_map(event) do
    signal_type = normalize_optional_string(event[:signal_type])
    event_name = normalize_optional_string(event[:event_name]) || ""

    is_binary(signal_type) or
      String.contains?(event_name, ".signal.") or
      String.contains?(event_name, ".signals.")
  end

  defp signal_event?(_), do: false

  defp matches_filters?(event, filters, bounds) do
    ts = signal_time(event)

    Filters.within_bounds?(ts, bounds) and
      status_match?(event, filters) and
      Filters.match_string(event[:signal_type], filters[:signal_type]) and
      Filters.match_string(event[:agent_id], filters[:agent_id]) and
      Filters.match_string(event[:project_id], filters[:project_id]) and
      Filters.match_string(event[:user_id], filters[:user_id]) and
      Filters.match_string(event[:trace_id], filters[:trace_id]) and
      Filters.match_string(event[:incident_id], filters[:incident_id]) and
      query_match?(event, filters[:query])
  end

  defp status_match?(event, %{error_only: true}),
    do: normalize_optional_string(event[:status]) == "error"

  defp status_match?(event, %{status: "all"}), do: is_map(event)

  defp status_match?(event, %{status: status}) do
    normalize_optional_string(event[:status]) == normalize_optional_string(status)
  end

  defp status_match?(_event, _), do: true

  defp query_match?(_event, nil), do: true

  defp query_match?(event, query) do
    query_text = String.downcase(to_string(query || ""))

    [
      event[:event_name],
      event[:signal_type],
      event[:trace_id],
      event[:agent_id],
      event[:request_id],
      event[:workflow_id],
      event[:action],
      inspect(event[:metadata] || %{}, limit: 40)
    ]
    |> Enum.map(&to_string(&1 || ""))
    |> Enum.join(" ")
    |> String.downcase()
    |> String.contains?(query_text)
  end

  defp signal_time(event) when is_map(event) do
    event[:ts] || event[:timestamp_ms] || 0
  end

  defp signal_time(_), do: 0

  defp by_field(items, field) do
    items
    |> Enum.reduce(%{}, fn item, acc ->
      key = normalize_optional_string(item[field]) || "unknown"
      Map.update(acc, key, 1, &(&1 + 1))
    end)
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(8)
  end

  defp normalize_signal_id(id) when is_integer(id) and id > 0, do: id

  defp normalize_signal_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> value
      _ -> nil
    end
  end

  defp normalize_signal_id(_), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_), do: nil
end
