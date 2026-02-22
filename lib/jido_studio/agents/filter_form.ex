defmodule JidoStudio.Agents.FilterForm do
  @moduledoc false

  @status_values ~w(all running idle interrupted error cancelled stopped offline available)
  @presence_values ~w(all has_viewers no_viewers)
  @sort_values ~w(last_activity viewers uptime name status)

  @type t :: %__MODULE__{
          status_filter: String.t(),
          presence_filter: String.t(),
          search_query: String.t(),
          sort_by: String.t()
        }

  defstruct status_filter: "all",
            presence_filter: "all",
            search_query: "",
            sort_by: "last_activity"

  @spec new(map() | keyword()) :: t()
  def new(overrides \\ %{}) do
    %__MODULE__{}
    |> Map.from_struct()
    |> Map.merge(normalize_map(overrides))
    |> normalize()
  end

  @spec parse(map() | keyword() | nil, t() | nil) :: t()
  def parse(params, defaults \\ %__MODULE__{})

  def parse(nil, %__MODULE__{} = defaults), do: defaults

  def parse(params, %__MODULE__{} = defaults) do
    source = normalize_map(params["filters"] || params)

    defaults
    |> Map.from_struct()
    |> Map.merge(%{
      status_filter: source["status_filter"] || source[:status_filter],
      presence_filter: source["presence_filter"] || source[:presence_filter],
      search_query: source["search_query"] || source[:search_query],
      sort_by: source["sort_by"] || source[:sort_by]
    })
    |> normalize()
  end

  def parse(_params, defaults), do: parse(nil, defaults || %__MODULE__{})

  @spec apply_filters([map()], t()) :: [map()]
  def apply_filters(rows, %__MODULE__{} = filters) when is_list(rows) do
    rows
    |> filter_status(filters.status_filter)
    |> filter_presence(filters.presence_filter)
    |> filter_search(filters.search_query)
    |> sort_rows(filters.sort_by)
  end

  def apply_filters(rows, _), do: rows

  @spec to_query_params(t(), t()) :: map()
  def to_query_params(%__MODULE__{} = filters, %__MODULE__{} = defaults) do
    %{}
    |> maybe_put("status_filter", filters.status_filter, defaults.status_filter)
    |> maybe_put("presence_filter", filters.presence_filter, defaults.presence_filter)
    |> maybe_put("search_query", filters.search_query, defaults.search_query)
    |> maybe_put("sort_by", filters.sort_by, defaults.sort_by)
  end

  def to_query_params(_, _), do: %{}

  defp normalize(data) when is_map(data) do
    %__MODULE__{
      status_filter:
        normalize_enum(data[:status_filter] || data["status_filter"], @status_values, "all"),
      presence_filter:
        normalize_enum(data[:presence_filter] || data["presence_filter"], @presence_values, "all"),
      search_query: normalize_query(data[:search_query] || data["search_query"]),
      sort_by: normalize_enum(data[:sort_by] || data["sort_by"], @sort_values, "last_activity")
    }
  end

  defp normalize(_), do: %__MODULE__{}

  defp normalize_enum(value, allowed, default) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    if normalized in allowed, do: normalized, else: default
  end

  defp normalize_enum(value, allowed, default) when is_atom(value) do
    normalize_enum(Atom.to_string(value), allowed, default)
  end

  defp normalize_enum(_value, _allowed, default), do: default

  defp normalize_query(value) when is_binary(value), do: String.trim(value)
  defp normalize_query(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_query(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_query(_), do: ""

  defp filter_status(rows, "all"), do: rows

  defp filter_status(rows, expected) do
    Enum.filter(rows, fn row ->
      status = row_status(row)
      status == expected
    end)
  end

  defp filter_presence(rows, "all"), do: rows

  defp filter_presence(rows, "has_viewers") do
    Enum.filter(rows, fn row -> normalize_viewer_count(row[:viewer_count]) > 0 end)
  end

  defp filter_presence(rows, "no_viewers") do
    Enum.filter(rows, fn row -> normalize_viewer_count(row[:viewer_count]) == 0 end)
  end

  defp filter_presence(rows, _), do: rows

  defp filter_search(rows, ""), do: rows

  defp filter_search(rows, query) do
    needle = String.downcase(query)

    Enum.filter(rows, fn row ->
      haystack =
        [
          row[:instance_id],
          row[:agent_slug],
          row[:agent_name],
          row[:status],
          row[:project_id],
          row[:user_id]
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&to_string/1)
        |> Enum.join(" ")
        |> String.downcase()

      String.contains?(haystack, needle)
    end)
  end

  defp sort_rows(rows, "viewers") do
    Enum.sort_by(rows, &normalize_viewer_count(&1[:viewer_count]), :desc)
  end

  defp sort_rows(rows, "uptime") do
    Enum.sort_by(rows, &normalize_uptime_sort_key/1, :asc)
  end

  defp sort_rows(rows, "name") do
    Enum.sort_by(rows, &String.downcase(to_string(&1[:agent_name] || "")), :asc)
  end

  defp sort_rows(rows, "status") do
    Enum.sort_by(rows, &status_sort_rank(row_status(&1)), :asc)
  end

  defp sort_rows(rows, _last_activity) do
    Enum.sort_by(rows, &last_activity_sort_key/1, {:desc, DateTime})
  end

  defp row_status(row) when is_map(row) do
    row
    |> Map.get(:status, "offline")
    |> to_string()
    |> String.downcase()
  end

  defp row_status(_), do: "offline"

  defp status_sort_rank("running"), do: 0
  defp status_sort_rank("idle"), do: 1
  defp status_sort_rank("interrupted"), do: 2
  defp status_sort_rank("error"), do: 3
  defp status_sort_rank("cancelled"), do: 4
  defp status_sort_rank("stopped"), do: 5
  defp status_sort_rank("available"), do: 6
  defp status_sort_rank(_), do: 7

  defp last_activity_sort_key(%{} = row) do
    case row[:last_activity_at] do
      %DateTime{} = dt -> dt
      _ -> ~U[1970-01-01 00:00:00Z]
    end
  end

  defp last_activity_sort_key(_), do: ~U[1970-01-01 00:00:00Z]

  defp normalize_uptime_sort_key(%{} = row) do
    case row[:started_at] do
      %DateTime{} = dt -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp normalize_uptime_sort_key(_), do: DateTime.utc_now()

  defp normalize_viewer_count(value) when is_integer(value) and value >= 0, do: value
  defp normalize_viewer_count(_), do: 0

  defp maybe_put(params, _key, value, default) when value == default, do: params
  defp maybe_put(params, _key, "", _default), do: params
  defp maybe_put(params, key, value, _default), do: Map.put(params, key, value)

  defp normalize_map(source) when is_map(source), do: source
  defp normalize_map(source) when is_list(source), do: Map.new(source)
  defp normalize_map(_), do: %{}
end
