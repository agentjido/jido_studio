defmodule JidoStudio.TraceFilter do
  @moduledoc false

  @default_entity_types ~w(agent model tool middleware scheduler sensor other)a

  @spec apply([map()], keyword()) :: [map()]
  def apply(events_or_spans, opts \\ [])

  def apply(events_or_spans, opts) when is_list(events_or_spans) and is_list(opts) do
    hide_internal? =
      case Keyword.fetch(opts, :hide_internal) do
        {:ok, value} -> truthy?(value)
        :error -> hide_internal_default?()
      end

    entity_type_filter = normalize_entity_type(Keyword.get(opts, :entity_type))
    status_filter = normalize_status(Keyword.get(opts, :status))
    stream_only? = truthy?(Keyword.get(opts, :stream_only, false))
    query = normalize_query(Keyword.get(opts, :query))

    Enum.filter(events_or_spans, fn item ->
      map = normalize_map(item)

      internal_ok = not hide_internal? or not internal?(map)
      entity_ok = entity_type_filter == nil or event_entity_type(map) == entity_type_filter
      status_ok = status_filter == nil or normalize_status(map_status(map)) == status_filter
      stream_ok = not stream_only? or streaming_chunk?(map)
      query_ok = is_nil(query) or query_match?(map, query)

      internal_ok and entity_ok and status_ok and stream_ok and query_ok
    end)
  end

  def apply(_, _), do: []

  @spec hide_internal_default?() :: boolean()
  def hide_internal_default? do
    :jido_studio
    |> Application.get_env(:tracing, [])
    |> Keyword.get(:hide_internal_default, true)
    |> truthy?()
  end

  @spec max_span_rows() :: pos_integer()
  def max_span_rows do
    :jido_studio
    |> Application.get_env(:tracing, [])
    |> Keyword.get(:max_span_rows, 5_000)
    |> normalize_limit(5_000)
  end

  defp map_status(map) do
    Map.get(map, :status) || Map.get(map, "status")
  end

  defp event_entity_type(map) do
    value =
      Map.get(map, :entity_type) ||
        Map.get(map, "entity_type") ||
        infer_entity_type(Map.get(map, :event_prefix) || Map.get(map, "event_prefix"))

    normalize_entity_type(value) || :other
  end

  defp infer_entity_type(prefix) when is_list(prefix) do
    parts = Enum.map(prefix, &to_string/1)

    cond do
      Enum.member?(parts, "tool") -> :tool
      Enum.member?(parts, "middleware") -> :middleware
      Enum.member?(parts, "scheduler") -> :scheduler
      Enum.member?(parts, "sensor") -> :sensor
      Enum.member?(parts, "ai") -> :model
      Enum.member?(parts, "agent") -> :agent
      true -> :other
    end
  end

  defp infer_entity_type(_), do: :other

  defp internal?(map) do
    value = Map.get(map, :internal) || Map.get(map, "internal")
    truthy?(value)
  end

  defp streaming_chunk?(map) do
    chunk_index = Map.get(map, :chunk_index) || Map.get(map, "chunk_index")
    chunk_count = Map.get(map, :chunk_count) || Map.get(map, "chunk_count")

    cond do
      is_integer(chunk_index) and chunk_index >= 0 -> true
      is_integer(chunk_count) and chunk_count > 1 -> true
      true -> false
    end
  end

  defp query_match?(map, query) do
    [
      Map.get(map, :event_name),
      Map.get(map, "event_name"),
      Map.get(map, :entity_id),
      Map.get(map, "entity_id"),
      map_status(map),
      Map.get(map, :trace_id),
      Map.get(map, :span_id),
      inspect(Map.get(map, :metadata) || Map.get(map, "metadata") || %{}, limit: 15)
    ]
    |> Enum.map(&to_string_safe/1)
    |> Enum.join(" ")
    |> String.downcase()
    |> String.contains?(query)
  end

  defp to_string_safe(nil), do: ""
  defp to_string_safe(value) when is_binary(value), do: value
  defp to_string_safe(value), do: to_string(value)

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("1"), do: true
  defp truthy?(1), do: true
  defp truthy?(_), do: false

  defp normalize_entity_type(nil), do: nil

  defp normalize_entity_type(value) when is_atom(value) do
    if value in @default_entity_types, do: value, else: nil
  end

  defp normalize_entity_type(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "agent" -> :agent
      "model" -> :model
      "tool" -> :tool
      "middleware" -> :middleware
      "scheduler" -> :scheduler
      "sensor" -> :sensor
      "other" -> :other
      _ -> nil
    end
  end

  defp normalize_entity_type(_), do: nil

  defp normalize_status(nil), do: nil
  defp normalize_status(value) when value in [:running, :ok, :error], do: value

  defp normalize_status(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "running" -> :running
      "ok" -> :ok
      "error" -> :error
      _ -> nil
    end
  end

  defp normalize_status(_), do: nil

  defp normalize_query(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      query -> query
    end
  end

  defp normalize_query(_), do: nil

  defp normalize_limit(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_limit(_value, default), do: default

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_), do: %{}
end
