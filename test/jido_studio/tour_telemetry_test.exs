defmodule JidoStudio.TourTelemetryTest do
  use JidoStudio.ConnCase, async: false

  test "guide emits additive tour telemetry events with flow metadata", %{conn: conn} do
    started_event = [:jido_studio, :tour, :started]
    viewed_event = [:jido_studio, :tour, :step_viewed]
    completed_event = [:jido_studio, :tour, :step_completed]
    dismissed_event = [:jido_studio, :tour, :dismissed]
    flow_completed_event = [:jido_studio, :tour, :completed]
    handler_id = "tour-telemetry-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [started_event, viewed_event, completed_event, dismissed_event, flow_completed_event],
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, view, _html} = live(conn, "/studio/guide")

    render_click(view, "tour_metric", %{
      "kind" => "started",
      "flow" => "first_5_minutes",
      "step_key" => "home_health_summary",
      "step_index" => "1",
      "total_steps" => "5",
      "mode" => "start"
    })

    assert_receive {:telemetry_event, ^started_event, %{count: 1}, started_metadata}
    assert started_metadata.flow == "first_5_minutes"
    assert started_metadata.step_key == "home_health_summary"
    assert started_metadata.step_index == 1
    assert started_metadata.total_steps == 5
    assert started_metadata.mode == "start"
    assert started_metadata.source == "guided_tour"

    render_click(view, "tour_metric", %{
      "kind" => "step_viewed",
      "flow" => "first_5_minutes",
      "step_key" => "home_attention_list",
      "step_index" => "2",
      "total_steps" => "5"
    })

    assert_receive {:telemetry_event, ^viewed_event, %{count: 1}, viewed_metadata}
    assert viewed_metadata.flow == "first_5_minutes"
    assert viewed_metadata.step_key == "home_attention_list"

    render_click(view, "tour_metric", %{
      "kind" => "step_completed",
      "flow" => "first_5_minutes",
      "step_key" => "home_attention_list",
      "step_index" => "2",
      "total_steps" => "5"
    })

    assert_receive {:telemetry_event, ^completed_event, %{count: 1}, completed_metadata}
    assert completed_metadata.flow == "first_5_minutes"
    assert completed_metadata.step_key == "home_attention_list"

    render_click(view, "tour_metric", %{
      "kind" => "dismissed",
      "flow" => "first_5_minutes",
      "step_key" => "agents_active_instances",
      "step_index" => "3",
      "total_steps" => "5",
      "status" => "dismissed"
    })

    assert_receive {:telemetry_event, ^dismissed_event, %{count: 1}, dismissed_metadata}
    assert dismissed_metadata.flow == "first_5_minutes"
    assert dismissed_metadata.status == "dismissed"

    render_click(view, "tour_metric", %{
      "kind" => "completed",
      "flow" => "incident_triage",
      "step_key" => "diagnostics_waterfall_root_cause",
      "step_index" => "4",
      "total_steps" => "4",
      "status" => "completed"
    })

    assert_receive {:telemetry_event, ^flow_completed_event, %{count: 1}, flow_completed_metadata}
    assert flow_completed_metadata.flow == "incident_triage"
    assert flow_completed_metadata.status == "completed"
  end

  def handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end
