defmodule JidoStudio.Agents.RunSummary do
  @moduledoc false

  @max_delta_entries 10
  @max_value_chars 120

  @spec build_success(map(), map(), keyword()) :: map()
  def build_success(result, dispatch_ref, opts \\ [])

  def build_success(result, dispatch_ref, opts) when is_map(result) and is_map(dispatch_ref) do
    before_state = normalize_state(result[:state_before])
    after_state = normalize_state(result[:state_after])
    delta = state_delta(before_state, after_state)

    %{
      status: :success,
      dispatch_ref: dispatch_ref,
      signal_type:
        dispatch_ref[:signal_type] || dispatch_ref[:primary_signal_type] || "unknown.signal",
      dispatch_mode: result[:mode] || :sync,
      trace_id: normalize_optional_string(Keyword.get(opts, :trace_id) || result[:trace_id]),
      changed_keys: Enum.map(delta, & &1.key),
      state_delta: delta,
      state_changed?: delta != [],
      memory_note: "Agent memory/state updated in the runtime process."
    }
  end

  def build_success(_result, _dispatch_ref, opts) do
    %{
      status: :success,
      dispatch_ref: %{},
      signal_type: "unknown.signal",
      dispatch_mode: :sync,
      trace_id: normalize_optional_string(Keyword.get(opts, :trace_id)),
      changed_keys: [],
      state_delta: [],
      state_changed?: false,
      memory_note: "Agent memory/state may have changed in the runtime process."
    }
  end

  @spec build_error(term(), map() | nil, keyword()) :: map()
  def build_error(reason, dispatch_ref \\ nil, opts \\ []) do
    %{
      status: :error,
      error: summarize(reason),
      dispatch_ref: if(is_map(dispatch_ref), do: dispatch_ref, else: %{}),
      signal_type:
        if(is_map(dispatch_ref),
          do:
            dispatch_ref[:signal_type] || dispatch_ref[:primary_signal_type] || "unknown.signal",
          else: "unknown.signal"
        ),
      dispatch_mode: Keyword.get(opts, :dispatch_mode, :sync),
      trace_id: normalize_optional_string(Keyword.get(opts, :trace_id)),
      changed_keys: [],
      state_delta: [],
      state_changed?: false,
      memory_note: "No state delta captured for this run."
    }
  end

  @spec latest_trace_id([map()]) :: String.t() | nil
  def latest_trace_id(events) when is_list(events) do
    events
    |> Enum.find_value(fn event ->
      normalize_optional_string(
        event[:trace_id] || event["trace_id"] ||
          get_in(event, [:metadata, :trace_id]) ||
          get_in(event, [:metadata, "trace_id"])
      )
    end)
  end

  def latest_trace_id(_), do: nil

  defp state_delta(before_state, after_state) do
    keys =
      (Map.keys(before_state) ++ Map.keys(after_state))
      |> Enum.uniq()
      |> Enum.sort()

    keys
    |> Enum.reduce([], fn key, acc ->
      before_value = Map.get(before_state, key)
      after_value = Map.get(after_state, key)

      if before_value != after_value do
        [
          %{
            key: key,
            previous: summarize(before_value),
            current: summarize(after_value)
          }
          | acc
        ]
      else
        acc
      end
    end)
    |> Enum.reverse()
    |> Enum.take(@max_delta_entries)
  end

  defp normalize_state(%{} = state) do
    state
    |> from_struct_if_needed()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_state(_), do: %{}

  defp from_struct_if_needed(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp from_struct_if_needed(map), do: map

  defp summarize(value) when is_binary(value) do
    value
    |> normalize_wrapped_json_string()
    |> trim_value()
  end

  defp summarize(value) do
    value
    |> inspect(limit: 30, printable_limit: 2_000, pretty: true)
    |> trim_value()
  end

  defp normalize_wrapped_json_string(value) when is_binary(value) do
    normalized = String.trim(value)

    if String.starts_with?(normalized, "\"") and String.ends_with?(normalized, "\"") do
      case Jason.decode(normalized) do
        {:ok, decoded} when is_binary(decoded) -> decoded
        _ -> value
      end
    else
      value
    end
  end

  defp trim_value(value) when is_binary(value) and byte_size(value) > @max_value_chars do
    String.slice(value, 0, @max_value_chars) <> "..."
  end

  defp trim_value(value), do: value

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil
end
