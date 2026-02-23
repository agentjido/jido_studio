defmodule JidoStudio.Agents.Runner do
  @moduledoc false

  alias JidoStudio.AgentInteractions

  @type dispatch_mode :: :sync | :async

  @spec dispatch(pid(), map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def dispatch(pid, route_or_action_ref, payload, opts \\ [])

  def dispatch(pid, route_or_action_ref, payload, opts)
      when is_pid(pid) and is_map(route_or_action_ref) and is_map(payload) do
    mode = dispatch_mode(Keyword.get(opts, :dispatch_mode, :sync))

    timeout_ms =
      normalize_timeout(Keyword.get(opts, :timeout_ms, AgentInteractions.runner_timeout_ms()))

    with {:ok, dispatch_ref} <- normalize_dispatch_ref(route_or_action_ref),
         {:ok, payload} <- validate_payload(dispatch_ref, payload),
         {:ok, signal} <- build_signal(dispatch_ref, payload),
         {:ok, result} <- dispatch_signal(pid, signal, mode, timeout_ms) do
      {:ok,
       %{
         timestamp_ms: System.system_time(:millisecond),
         mode: mode,
         signal_type: signal.type,
         source: signal.source,
         payload: payload,
         result: result,
         status_snapshot: status_snapshot(pid),
         dispatch_ref: dispatch_ref
       }}
    end
  end

  def dispatch(_, _, _, _), do: {:error, :invalid_dispatch_request}

  defp normalize_dispatch_ref(%{kind: kind, signal_type: signal_type} = ref)
       when kind in [:signal, "signal"] and is_binary(signal_type) do
    {:ok,
     %{
       kind: :signal,
       signal_type: normalize_signal_type(signal_type),
       source: normalize_source(Map.get(ref, :source) || Map.get(ref, "source")),
       schema: Map.get(ref, :schema) || Map.get(ref, "schema")
     }}
  end

  defp normalize_dispatch_ref(%{kind: kind, primary_signal_type: signal_type} = ref)
       when kind in [:action, "action"] and is_binary(signal_type) do
    normalize_dispatch_ref(%{
      kind: :signal,
      signal_type: signal_type,
      source: Map.get(ref, :source) || Map.get(ref, "source"),
      schema: Map.get(ref, :schema) || Map.get(ref, "schema")
    })
  end

  defp normalize_dispatch_ref(%{"kind" => kind, "signal_type" => signal_type} = ref)
       when is_binary(kind) and is_binary(signal_type) do
    normalize_dispatch_ref(%{
      kind: kind,
      signal_type: signal_type,
      source: ref["source"],
      schema: ref["schema"]
    })
  end

  defp normalize_dispatch_ref(_), do: {:error, :unsupported_dispatch_target}

  defp build_signal(%{signal_type: signal_type, source: source}, payload) do
    Jido.Signal.new(signal_type, payload, source: source)
  rescue
    error ->
      {:error, {:invalid_signal, Exception.message(error)}}
  end

  defp dispatch_signal(pid, signal, :sync, timeout_ms) do
    try do
      case Jido.AgentServer.call(pid, signal, timeout_ms) do
        {:ok, result} -> {:ok, %{status: :ok, response: summarize_result(result)}}
        {:error, reason} -> {:error, reason}
      end
    rescue
      error ->
        {:error, {:dispatch_failed, Exception.message(error)}}
    catch
      :exit, reason ->
        {:error, {:dispatch_failed, inspect(reason)}}
    end
  end

  defp dispatch_signal(pid, signal, :async, _timeout_ms) do
    try do
      case Jido.AgentServer.cast(pid, signal) do
        :ok -> {:ok, %{status: :queued}}
        {:error, reason} -> {:error, reason}
      end
    rescue
      error ->
        {:error, {:dispatch_failed, Exception.message(error)}}
    catch
      :exit, reason ->
        {:error, {:dispatch_failed, inspect(reason)}}
    end
  end

  defp validate_payload(%{schema: nil}, payload), do: {:ok, payload}
  defp validate_payload(%{schema: []}, payload), do: {:ok, payload}

  defp validate_payload(%{schema: schema}, payload) do
    case Jido.Action.Schema.validate(schema, payload) do
      {:ok, validated} -> {:ok, normalize_validated_payload(validated)}
      {:error, reason} -> {:error, {:payload_validation_failed, reason}}
    end
  rescue
    error ->
      {:error, {:payload_validation_failed, Exception.message(error)}}
  end

  defp normalize_validated_payload(value) when is_map(value) do
    if Map.has_key?(value, :__struct__) do
      value
      |> Map.from_struct()
      |> stringify_map_keys()
    else
      stringify_map_keys(value)
    end
  end

  defp normalize_validated_payload(_), do: %{}

  defp stringify_map_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        case value do
          value when is_map(value) -> stringify_map_keys(value)
          value when is_list(value) -> Enum.map(value, &normalize_list_value/1)
          other -> other
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp stringify_map_keys(_), do: %{}

  defp normalize_list_value(value) when is_map(value), do: stringify_map_keys(value)

  defp normalize_list_value(value) when is_list(value),
    do: Enum.map(value, &normalize_list_value/1)

  defp normalize_list_value(value), do: value

  defp summarize_result(%{id: id, state: state}) do
    %{
      agent_id: normalize_optional_string(id),
      state_keys: state_keys(state)
    }
  end

  defp summarize_result(value) do
    %{
      value: inspect(value, limit: 30, printable_limit: 2_000)
    }
  end

  defp state_keys(state) when is_map(state) do
    state
    |> Map.keys()
    |> Enum.take(20)
    |> Enum.map(&to_string/1)
  end

  defp state_keys(_), do: []

  defp status_snapshot(pid) when is_pid(pid) do
    case Jido.AgentServer.status(pid) do
      {:ok, status} ->
        snapshot = status.snapshot

        %{
          status: snapshot.status,
          done?: snapshot.done?,
          queue_length: snapshot.details[:queue_length] || snapshot.details["queue_length"] || 0,
          iteration: snapshot.details[:iteration] || snapshot.details["iteration"]
        }

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp status_snapshot(_), do: nil

  defp dispatch_mode(:async), do: :async
  defp dispatch_mode("async"), do: :async
  defp dispatch_mode(_), do: :sync

  defp normalize_timeout(value) when is_integer(value) and value > 0, do: value
  defp normalize_timeout(_), do: AgentInteractions.runner_timeout_ms()

  defp normalize_signal_type(value) when is_binary(value), do: String.trim(value)
  defp normalize_signal_type(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_signal_type(_), do: "unknown.signal"

  defp normalize_source(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "/jido_studio/interact"
      normalized -> normalized
    end
  end

  defp normalize_source(value) when is_atom(value), do: "/jido_studio/" <> Atom.to_string(value)
  defp normalize_source(_), do: "/jido_studio/interact"

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_binary(value), do: value
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_), do: nil
end
