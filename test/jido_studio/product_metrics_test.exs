defmodule JidoStudio.ProductMetricsTest do
  use ExUnit.Case, async: false

  alias JidoStudio.ProductMetrics

  test "session_id/1 hashes stable non-empty tokens" do
    token = "abc123"

    assert ProductMetrics.session_id(token) == ProductMetrics.session_id(token)
    assert String.length(ProductMetrics.session_id(token)) == 16
    assert ProductMetrics.session_id("  ") == nil
    assert ProductMetrics.session_id(nil) == nil
  end

  test "interaction telemetry includes normalized metadata and omits nil values" do
    event = [:jido_studio, :interaction, :started]
    handler_id = "product-metrics-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        runtime_key: "primary",
        cluster_node_param: "all",
        current_path: "/studio/agents",
        metrics_session_id: "session123"
      }
    }

    :ok = ProductMetrics.interaction_started(socket, source: "agents_interact", mode: "interact")

    assert_receive {:telemetry_event, ^event, measurements, metadata}

    assert measurements.count == 1
    assert is_integer(measurements.timestamp_ms)

    assert metadata.runtime == "primary"
    assert metadata.node == "all"
    assert metadata.path == "/studio/agents"
    assert metadata.source == "agents_interact"
    assert metadata.mode == "interact"
    assert metadata.session_id == "session123"

    refute Map.has_key?(metadata, :payload)
  end

  test "maybe_emit_first_interaction_succeeded emits once per socket session" do
    event = [:jido_studio, :onboarding, :first_interaction_succeeded]
    handler_id = "product-metrics-first-success-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        runtime_key: "primary",
        cluster_node_param: "all",
        current_path: "/studio/agents",
        metrics_session_id: "session123",
        first_interaction_success_emitted?: false
      }
    }

    socket =
      ProductMetrics.maybe_emit_first_interaction_succeeded(socket,
        source: "agents_interact",
        mode: "interact"
      )

    assert_receive {:telemetry_event, ^event, _measurements, metadata}
    assert metadata.source == "agents_interact"
    assert socket.assigns.first_interaction_success_emitted? == true

    _socket =
      ProductMetrics.maybe_emit_first_interaction_succeeded(socket,
        source: "agents_interact",
        mode: "interact"
      )

    refute_receive {:telemetry_event, ^event, _measurements, _metadata}, 50
  end

  test "starter onboarding telemetry emits additive events with starter metadata" do
    opened_event = [:jido_studio, :onboarding, :starter_opened]
    modal_event = [:jido_studio, :onboarding, :starter_start_modal_opened]
    handler_id = "product-metrics-starter-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [opened_event, modal_event],
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        runtime_key: "primary",
        cluster_node_param: "all",
        current_path: "/studio/guide",
        metrics_session_id: "session123"
      }
    }

    :ok =
      ProductMetrics.onboarding_starter_opened(socket,
        source: "guide_starter_card",
        mode: "guide_card",
        starter_slug: "starter",
        starter_module: "JidoStudio.BeginnerAgent"
      )

    assert_receive {:telemetry_event, ^opened_event, %{count: 1}, opened_metadata}
    assert opened_metadata.source == "guide_starter_card"
    assert opened_metadata.mode == "guide_card"
    assert opened_metadata.starter_slug == "starter"

    :ok =
      ProductMetrics.onboarding_starter_start_modal_opened(socket,
        source: "agents_start_query",
        mode: "deep_link",
        starter_slug: "starter",
        starter_module: "JidoStudio.BeginnerAgent"
      )

    assert_receive {:telemetry_event, ^modal_event, %{count: 1}, modal_metadata}
    assert modal_metadata.source == "agents_start_query"
    assert modal_metadata.mode == "deep_link"
    assert modal_metadata.starter_module == "JidoStudio.BeginnerAgent"
  end

  def handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end
