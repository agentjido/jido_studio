defmodule JidoStudio.Agents.StarterOperations do
  @moduledoc false

  alias JidoStudio.Beginner

  @beginner_signal_order [
    {"beginner.ping", "Ping",
     "Quick health check. Sends a short message and increments ping count.",
     %{"message" => "hello", "count" => 1}},
    {"beginner.add", "Add", "Adds two numbers and stores the latest addition result in state.",
     %{"a" => 25.0, "b" => 4.0}},
    {"beginner.tip", "Tip", "Calculates tip amount and total bill using amount + tip rate.",
     %{"amount" => 42.5, "rate_percent" => 20.0}},
    {"beginner.reset", "Reset", "Resets beginner state fields back to default values.", %{}}
  ]

  @spec list(map() | nil, map()) :: [map()]
  def list(agent, interaction_model) when is_map(interaction_model) do
    signals = List.wrap(interaction_model[:signals])
    actions = List.wrap(interaction_model[:actions])

    operations =
      if beginner_agent?(agent) do
        beginner_operations(signals, actions)
      else
        generic_operations(signals, actions)
      end

    Enum.reject(operations, &is_nil/1)
  end

  def list(_, _), do: []

  defp beginner_operations(signals, actions) do
    Enum.map(@beginner_signal_order, fn {signal_type, label, rationale, payload} ->
      signal = pick_signal(signals, signal_type)

      if is_map(signal) do
        operation_from_signal(signal, actions,
          id: "starter:#{signal_type}",
          label: label,
          rationale: rationale,
          payload: payload
        )
      end
    end)
  end

  defp generic_operations(signals, actions) do
    signals
    |> Enum.reject(&(&1[:advanced?] == true))
    |> Enum.sort_by(fn signal ->
      {
        String.downcase(to_string(signal[:signal_type] || "")),
        -(signal[:priority] || 0),
        String.downcase(to_string(signal[:key] || ""))
      }
    end)
    |> Enum.take(4)
    |> Enum.map(fn signal ->
      signal_type = to_string(signal[:signal_type] || "unknown.signal")
      label = signal_label(signal_type)

      operation_from_signal(signal, actions,
        id: "starter:#{signal_type}",
        label: label,
        rationale: "Starter entry signal discovered for this module in the current scope."
      )
    end)
  end

  defp operation_from_signal(signal, actions, opts) do
    payload =
      case Keyword.fetch(opts, :payload) do
        {:ok, %{} = provided} -> provided
        _ -> payload_from_action(actions, signal[:signal_type])
      end

    payload_json = Jason.encode!(payload)

    %{
      id: to_string(Keyword.get(opts, :id, signal[:signal_type] || signal[:key] || "starter")),
      label: to_string(Keyword.get(opts, :label, signal_label(signal[:signal_type]))),
      rationale: to_string(Keyword.get(opts, :rationale, "Starter operation.")),
      selection_kind: :signal,
      selection_key: signal[:key],
      signal_type: signal[:signal_type],
      payload: payload,
      payload_json: payload_json
    }
  end

  defp payload_from_action(actions, signal_type) when is_binary(signal_type) do
    actions
    |> Enum.find(&(&1[:primary_signal_type] == signal_type))
    |> case do
      %{required_fields: required_fields}
      when is_list(required_fields) and required_fields != [] ->
        Enum.reduce(required_fields, %{}, fn field, acc ->
          Map.put(acc, field, "<value>")
        end)

      _ ->
        %{}
    end
  end

  defp payload_from_action(_, _), do: %{}

  defp pick_signal(signals, signal_type) do
    signals
    |> Enum.filter(&(&1[:signal_type] == signal_type))
    |> Enum.sort_by(fn signal ->
      {signal[:route_available?] != true, -(signal[:priority] || 0),
       to_string(signal[:key] || "")}
    end)
    |> List.first()
  end

  defp beginner_agent?(%{module: module}) when is_atom(module), do: module == Beginner.module()
  defp beginner_agent?(_), do: false

  defp signal_label(signal_type) when is_binary(signal_type) do
    signal_type
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp signal_label(_), do: "Starter"
end
