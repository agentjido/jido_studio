defmodule JidoStudio.ProductMetrics do
  @moduledoc false

  alias JidoStudio.Telemetry

  @type socket_like :: %{assigns: map()}

  @spec session_id(term()) :: String.t() | nil
  def session_id(value)

  def session_id(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" ->
        nil

      token ->
        :crypto.hash(:sha256, token)
        |> Base.encode16(case: :lower)
        |> binary_part(0, 16)
    end
  end

  def session_id(_), do: nil

  @spec interaction_started(socket_like(), keyword()) :: :ok
  def interaction_started(socket, opts \\ []) do
    emit(socket, [:interaction, :started], opts)
  end

  @spec interaction_completed(socket_like(), keyword()) :: :ok
  def interaction_completed(socket, opts \\ []) do
    emit(socket, [:interaction, :completed], opts)
  end

  @spec triage_warning_opened(socket_like(), keyword()) :: :ok
  def triage_warning_opened(socket, opts \\ []) do
    emit(socket, [:triage, :warning_opened], opts)
  end

  @spec onboarding_starter_opened(socket_like(), keyword()) :: :ok
  def onboarding_starter_opened(socket, opts \\ []) do
    emit(socket, [:onboarding, :starter_opened], opts)
  end

  @spec onboarding_starter_payload_prefilled(socket_like(), keyword()) :: :ok
  def onboarding_starter_payload_prefilled(socket, opts \\ []) do
    emit(socket, [:onboarding, :starter_payload_prefilled], opts)
  end

  @spec onboarding_starter_start_modal_opened(socket_like(), keyword()) :: :ok
  def onboarding_starter_start_modal_opened(socket, opts \\ []) do
    emit(socket, [:onboarding, :starter_start_modal_opened], opts)
  end

  @spec triage_root_cause_opened(socket_like(), keyword()) :: :ok
  def triage_root_cause_opened(socket, opts \\ []) do
    emit(socket, [:triage, :root_cause_opened], opts)
  end

  @spec interaction_state_delta_viewed(socket_like(), keyword()) :: :ok
  def interaction_state_delta_viewed(socket, opts \\ []) do
    emit(socket, [:interaction, :state_delta_viewed], opts)
  end

  @spec interaction_next_action_opened(socket_like(), keyword()) :: :ok
  def interaction_next_action_opened(socket, opts \\ []) do
    emit(socket, [:interaction, :next_action_opened], opts)
  end

  @spec tour_started(socket_like(), keyword()) :: :ok
  def tour_started(socket, opts \\ []) do
    emit(socket, [:tour, :started], opts)
  end

  @spec tour_step_viewed(socket_like(), keyword()) :: :ok
  def tour_step_viewed(socket, opts \\ []) do
    emit(socket, [:tour, :step_viewed], opts)
  end

  @spec tour_step_completed(socket_like(), keyword()) :: :ok
  def tour_step_completed(socket, opts \\ []) do
    emit(socket, [:tour, :step_completed], opts)
  end

  @spec tour_dismissed(socket_like(), keyword()) :: :ok
  def tour_dismissed(socket, opts \\ []) do
    emit(socket, [:tour, :dismissed], opts)
  end

  @spec tour_completed(socket_like(), keyword()) :: :ok
  def tour_completed(socket, opts \\ []) do
    emit(socket, [:tour, :completed], opts)
  end

  @spec incidents_next_step_links_evaluated(
          socket_like(),
          non_neg_integer(),
          non_neg_integer(),
          keyword()
        ) ::
          :ok
  def incidents_next_step_links_evaluated(socket, linked_count, total_count, opts \\ [])
      when is_integer(linked_count) and linked_count >= 0 and is_integer(total_count) and
             total_count >= 0 do
    emit(
      socket,
      [:incidents, :next_step_links_evaluated],
      Keyword.merge(opts,
        linked_count: linked_count,
        total_count: total_count
      )
    )
  end

  @spec maybe_emit_first_interaction_succeeded(socket_like(), keyword()) :: socket_like()
  def maybe_emit_first_interaction_succeeded(socket, opts \\ []) do
    if socket.assigns[:first_interaction_success_emitted?] do
      socket
    else
      :ok = emit(socket, [:onboarding, :first_interaction_succeeded], opts)

      Map.put(
        socket,
        :assigns,
        Map.put(socket.assigns, :first_interaction_success_emitted?, true)
      )
    end
  end

  defp emit(socket, event, opts) when is_map(socket) and is_list(event) and is_list(opts) do
    metadata = metadata(socket, opts)
    measurements = %{count: 1, timestamp_ms: System.system_time(:millisecond)}

    Telemetry.execute(event, measurements, metadata)
  end

  defp metadata(socket, opts) do
    base = %{
      runtime: normalize_optional_string(socket.assigns[:runtime_key]),
      node: normalize_optional_string(socket.assigns[:cluster_node_param]),
      path: normalize_optional_string(socket.assigns[:current_path]),
      source: normalize_optional_string(Keyword.get(opts, :source)),
      session_id: normalize_optional_string(socket.assigns[:metrics_session_id])
    }

    extra =
      opts
      |> Keyword.drop([:source])
      |> Enum.into(%{}, fn {key, value} ->
        {key, normalize_metadata_value(value)}
      end)

    base
    |> Map.merge(extra)
    |> Telemetry.compact_metadata()
  end

  defp normalize_metadata_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_metadata_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_metadata_value(value) when is_integer(value), do: value
  defp normalize_metadata_value(value) when is_float(value), do: value
  defp normalize_metadata_value(value) when is_boolean(value), do: value
  defp normalize_metadata_value(nil), do: nil
  defp normalize_metadata_value(value), do: inspect(value)

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil
end
