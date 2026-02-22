defmodule JidoStudio.Live.AgentsLive.RunnerState do
  @moduledoc false

  alias JidoStudio.AgentInteractions
  alias JidoStudio.Agents.RunnerForm

  def sync_runner_form(%RunnerForm{} = existing, interaction_model) do
    signals = interaction_model[:signals] || []
    actions = interaction_model[:actions] || []

    selected_signal_ok? =
      is_binary(existing.selected_signal_key) and
        Enum.any?(signals, &(&1[:key] == existing.selected_signal_key))

    selected_action_ok? =
      is_binary(existing.selected_action_key) and
        Enum.any?(actions, &(&1[:key] == existing.selected_action_key))

    cond do
      selected_signal_ok? or selected_action_ok? ->
        existing

      signals != [] ->
        existing
        |> RunnerForm.select_signal(hd(signals)[:key])
        |> maybe_apply_payload_template(interaction_model, {:signal, hd(signals)[:key]})

      actions != [] ->
        existing
        |> RunnerForm.select_action(hd(actions)[:key])
        |> maybe_apply_payload_template(interaction_model, {:action, hd(actions)[:key]})

      true ->
        RunnerForm.new()
    end
  end

  def sync_runner_form(_, interaction_model) do
    sync_runner_form(RunnerForm.new(), interaction_model)
  end

  def maybe_apply_payload_template(%RunnerForm{} = form, interaction_model, selection) do
    template = payload_template_for_selection(interaction_model, selection)

    if form.payload_json in [nil, "", "{}"] and template not in [nil, "{}", ""] do
      RunnerForm.parse(%{"payload_json" => template}, form)
    else
      form
    end
  end

  def payload_template_for_selection(interaction_model, {:signal, key}) do
    signals = interaction_model[:signals] || []
    signal = Enum.find(signals, &(&1[:key] == key))

    action =
      if signal do
        actions = interaction_model[:actions] || []
        Enum.find(actions, &(&1[:primary_signal_type] == signal[:signal_type]))
      else
        nil
      end

    payload_template_from_action(action)
  end

  def payload_template_for_selection(interaction_model, {:action, key}) do
    action = Enum.find(interaction_model[:actions] || [], &(&1[:key] == key))
    payload_template_from_action(action)
  end

  def payload_template_for_selection(_, _), do: "{}"

  def payload_template_from_action(nil), do: "{}"

  def payload_template_from_action(%{required_fields: fields}) when is_list(fields) do
    fields
    |> Enum.reduce(%{}, fn field, acc -> Map.put(acc, field, "<value>") end)
    |> Jason.encode!()
  rescue
    _ -> "{}"
  end

  def payload_template_from_action(_), do: "{}"

  def selected_dispatch_ref(socket) do
    case RunnerForm.selected_target(socket.assigns.runner_form) do
      {:signal, key} ->
        signal =
          socket.assigns.interaction_model.signals
          |> List.wrap()
          |> Enum.find(&(&1[:key] == key))

        if is_map(signal) do
          {:ok,
           %{
             kind: :signal,
             signal_type: signal[:signal_type],
             source: "/jido_studio/interact",
             schema: schema_for_signal(socket.assigns.interaction_model, signal[:signal_type])
           }}
        else
          {:error, :signal_not_found}
        end

      {:action, key} ->
        action =
          socket.assigns.interaction_model.actions
          |> List.wrap()
          |> Enum.find(&(&1[:key] == key))

        if is_map(action) and is_binary(action[:primary_signal_type]) do
          {:ok,
           %{
             kind: :action,
             primary_signal_type: action[:primary_signal_type],
             source: "/jido_studio/interact",
             schema: action[:schema]
           }}
        else
          {:error, :action_not_dispatchable}
        end

      _ ->
        {:error, :no_target_selected}
    end
  end

  def schema_for_signal(interaction_model, signal_type) when is_binary(signal_type) do
    interaction_model[:actions]
    |> List.wrap()
    |> Enum.find(&(&1[:primary_signal_type] == signal_type))
    |> case do
      %{schema: schema} -> schema
      _ -> nil
    end
  end

  def schema_for_signal(_, _), do: nil

  def decode_runner_payload(payload_json) when is_binary(payload_json) do
    case Jason.decode(payload_json) do
      {:ok, %{} = payload} -> {:ok, payload}
      {:ok, _other} -> {:error, :payload_must_be_json_object}
      {:error, error} -> {:error, {:invalid_json, Exception.message(error)}}
    end
  end

  def decode_runner_payload(_), do: {:error, :payload_must_be_json_object}

  def normalize_runner_history_entry(result, dispatch_ref) when is_map(result) do
    %{
      timestamp_ms: result[:timestamp_ms] || System.system_time(:millisecond),
      mode: result[:mode] || :sync,
      signal_type: dispatch_ref[:signal_type] || dispatch_ref[:primary_signal_type] || "unknown",
      status:
        result
        |> get_in([:result, :status])
        |> case do
          nil -> :ok
          value -> value
        end
    }
  end

  def normalize_runner_history_entry(_result, dispatch_ref) do
    %{
      timestamp_ms: System.system_time(:millisecond),
      mode: :sync,
      signal_type: dispatch_ref[:signal_type] || dispatch_ref[:primary_signal_type] || "unknown",
      status: :ok
    }
  end

  def prepend_runner_history(history, entry) do
    limit = AgentInteractions.runner_history_limit()
    [entry | List.wrap(history)] |> Enum.take(limit)
  end

  def update_interaction_history(history, instance_id, entries)
      when is_map(history) and is_binary(instance_id) do
    Map.put(history, instance_id, List.wrap(entries))
  end

  def update_interaction_history(history, _instance_id, _entries) when is_map(history),
    do: history

  def update_interaction_history(_, _instance_id, _entries), do: %{}

  def current_runner_history(socket, instance_id) when is_binary(instance_id) do
    socket.assigns[:interaction_history]
    |> case do
      history when is_map(history) -> Map.get(history, instance_id, [])
      _ -> []
    end
  end

  def current_runner_history(_, _), do: []
end
