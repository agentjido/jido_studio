defmodule JidoStudio.Observability.Correlation do
  @moduledoc false

  @canonical_keys [
    :trace_id,
    :span_id,
    :parent_span_id,
    :agent_id,
    :agent_module,
    :action,
    :workflow_id,
    :signal_type,
    :request_id,
    :project_id,
    :user_id,
    :ts,
    :incident_id
  ]

  @type record :: map()

  @spec canonical_keys() :: [atom()]
  def canonical_keys, do: @canonical_keys

  @spec normalize(record()) :: record()
  def normalize(record) when is_map(record) do
    metadata = normalize_map(fetch(record, :metadata))
    scope = merged_scope(fetch(record, :scope), metadata)

    trace_id = normalize_optional_string(fetch(record, :trace_id) || fetch(metadata, :trace_id))

    span_id =
      normalize_optional_string(
        fetch(record, :span_id) || fetch(metadata, :span_id) || fetch(metadata, :jido_span_id)
      )

    parent_span_id =
      normalize_optional_string(
        fetch(record, :parent_span_id) || fetch(metadata, :parent_span_id) ||
          fetch(metadata, :jido_parent_span_id)
      )

    agent_id =
      normalize_optional_string(
        fetch(record, :agent_id) || fetch(record, :instance_id) || fetch(metadata, :agent_id) ||
          fetch(metadata, :instance_id)
      )

    agent_module =
      normalize_optional_string(
        fetch(record, :agent_module) || fetch(metadata, :agent_module) || fetch(metadata, :module)
      )

    action =
      normalize_optional_string(
        fetch(record, :action) || fetch(metadata, :action) || fetch(metadata, :action_name) ||
          fetch(metadata, :tool_name) ||
          action_from_entity(fetch(record, :entity_type), fetch(record, :entity_id))
      )

    workflow_id =
      normalize_optional_string(
        fetch(record, :workflow_id) || fetch(metadata, :workflow_id) ||
          fetch(metadata, :workflow_run_id)
      )

    signal_type =
      normalize_optional_string(
        fetch(record, :signal_type) || fetch(metadata, :signal_type) ||
          fetch(metadata, :signal)
      )

    request_id =
      normalize_optional_string(
        fetch(record, :request_id) || fetch(metadata, :request_id) || fetch(record, :call_id) ||
          fetch(metadata, :call_id)
      )

    project_id =
      normalize_optional_string(
        fetch(record, :project_id) || fetch(scope, :project_id) || fetch(metadata, :project_id)
      )

    user_id =
      normalize_optional_string(
        fetch(record, :user_id) || fetch(scope, :user_id) || fetch(metadata, :user_id)
      )

    ts =
      normalize_timestamp(
        fetch(record, :ts) || fetch(record, :timestamp_ms) || fetch(metadata, :timestamp_ms)
      )

    normalized_scope =
      scope
      |> maybe_put(:project_id, project_id)
      |> maybe_put(:user_id, user_id)

    base =
      record
      |> Map.put(:trace_id, trace_id)
      |> Map.put(:span_id, span_id)
      |> Map.put(:parent_span_id, parent_span_id)
      |> Map.put(:agent_id, agent_id)
      |> Map.put(:agent_module, agent_module)
      |> Map.put(:action, action)
      |> Map.put(:workflow_id, workflow_id)
      |> Map.put(:signal_type, signal_type)
      |> Map.put(:request_id, request_id)
      |> Map.put(:project_id, project_id)
      |> Map.put(:user_id, user_id)
      |> Map.put(:ts, ts)
      |> Map.put(:scope, normalized_scope)

    incident_id = normalize_optional_string(fetch(record, :incident_id)) || incident_id_from(base)
    Map.put(base, :incident_id, incident_id)
  end

  def normalize(other), do: %{ts: now_ms(), incident_id: nil, raw: other}

  @spec incident_id(record()) :: String.t() | nil
  def incident_id(record) when is_map(record) do
    record
    |> normalize()
    |> Map.get(:incident_id)
  end

  def incident_id(_), do: nil

  defp incident_id_from(record) when is_map(record) do
    request_id = normalize_optional_string(fetch(record, :request_id))
    trace_id = normalize_optional_string(fetch(record, :trace_id))
    workflow_id = normalize_optional_string(fetch(record, :workflow_id))
    call_id = normalize_optional_string(fetch(record, :call_id))

    cond do
      is_binary(request_id) ->
        "req:" <> request_id

      is_binary(workflow_id) and is_binary(trace_id) ->
        "wf:" <> workflow_id <> ":" <> trace_id

      is_binary(trace_id) ->
        "trace:" <> trace_id

      is_binary(call_id) ->
        "call:" <> call_id

      true ->
        nil
    end
  end

  defp incident_id_from(_), do: nil

  defp action_from_entity(entity_type, entity_id) do
    if normalize_optional_string(entity_type) in ["tool", "action"] do
      normalize_optional_string(entity_id)
    else
      nil
    end
  end

  defp merged_scope(scope, metadata) do
    metadata_scope =
      metadata
      |> Map.take([:project_id, "project_id", :user_id, "user_id"])
      |> Enum.reduce(%{}, fn
        {:project_id, value}, acc ->
          maybe_put(acc, :project_id, normalize_optional_string(value))

        {"project_id", value}, acc ->
          maybe_put(acc, :project_id, normalize_optional_string(value))

        {:user_id, value}, acc ->
          maybe_put(acc, :user_id, normalize_optional_string(value))

        {"user_id", value}, acc ->
          maybe_put(acc, :user_id, normalize_optional_string(value))

        _, acc ->
          acc
      end)

    metadata_scope
    |> Map.merge(normalize_scope(scope))
  end

  defp normalize_scope(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      value = normalize_optional_string(value)

      if is_binary(value) do
        case key do
          :project_id -> Map.put(acc, :project_id, value)
          "project_id" -> Map.put(acc, :project_id, value)
          :user_id -> Map.put(acc, :user_id, value)
          "user_id" -> Map.put(acc, :user_id, value)
          _ -> acc
        end
      else
        acc
      end
    end)
  end

  defp normalize_scope(list) when is_list(list) do
    list
    |> Map.new()
    |> normalize_scope()
  end

  defp normalize_scope(_), do: %{}

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_), do: %{}

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp fetch(_, _), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_), do: nil

  defp normalize_timestamp(value) when is_integer(value) and value > 0, do: value
  defp normalize_timestamp(_), do: now_ms()

  defp now_ms, do: System.system_time(:millisecond)
end
