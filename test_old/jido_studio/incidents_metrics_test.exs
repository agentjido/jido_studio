defmodule JidoStudio.IncidentsMetricsTest do
  use JidoStudio.ConnCase, async: false

  test "home emits next-step link coverage telemetry" do
    event = [:jido_studio, :incidents, :next_step_links_evaluated]
    handler_id = "incidents-metrics-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, _view, _html} = live(build_conn(), "/studio")

    assert_receive {:telemetry_event, ^event, measurements, metadata}

    assert measurements.count == 1
    assert is_integer(metadata.linked_count)
    assert is_integer(metadata.total_count)
    assert metadata.linked_count <= metadata.total_count
    assert metadata.source == "home_attention"
    assert metadata.node == "all"
  end

  def handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end
