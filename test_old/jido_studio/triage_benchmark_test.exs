defmodule JidoStudio.TriageBenchmarkTest do
  use JidoStudio.ConnCase, async: false

  alias JidoStudio.Persistence

  @tag :benchmark
  test "captures warning-to-root-cause baseline in milliseconds", %{conn: conn} do
    warning_event = [:jido_studio, :triage, :warning_opened]
    root_event = [:jido_studio, :triage, :root_cause_opened]
    handler_id = "triage-benchmark-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [warning_event, root_event],
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, home_view, _html} = live(conn, "/studio")

    render_click(home_view, "open_attention_item", %{
      "path" => "/studio/activity",
      "kind" => "benchmark_warning"
    })

    {trace_id, span_id} = seed_benchmark_trace()
    node_param = URI.encode_www_form(to_string(Node.self()))

    {:ok, diagnostics_view, _html} =
      live(conn, "/studio/diagnostics?view=timeline&trace_id=#{trace_id}&node=#{node_param}")

    diagnostics_view
    |> element("button[phx-click='select_timeline_span'][phx-value-span_id='#{span_id}']")
    |> render_click()

    warning_ts = telemetry_timestamp_for(warning_event)
    root_ts = telemetry_timestamp_for(root_event)

    time_to_triage_ms = max(root_ts - warning_ts, 0)
    median_ms = median([time_to_triage_ms])

    IO.puts("time_to_triage_ms baseline: #{median_ms}")

    assert is_integer(median_ms)
    assert median_ms >= 0
  end

  defp telemetry_timestamp_for(expected_event) do
    receive do
      {:telemetry_event, ^expected_event, measurements, _metadata} ->
        measurements.timestamp_ms
    after
      1_000 ->
        flunk("missing telemetry event #{inspect(expected_event)}")
    end
  end

  defp median(values) when is_list(values) and values != [] do
    sorted = Enum.sort(values)
    count = length(sorted)

    if rem(count, 2) == 1 do
      Enum.at(sorted, div(count, 2))
    else
      lower = Enum.at(sorted, div(count, 2) - 1)
      upper = Enum.at(sorted, div(count, 2))
      div(lower + upper, 2)
    end
  end

  defp seed_benchmark_trace do
    trace_id = "triage-benchmark-trace-#{System.unique_integer([:positive])}"
    span_id = "triage-benchmark-span-#{System.unique_integer([:positive])}"
    base = System.system_time(:millisecond) - 2_000

    assert :ok =
             Persistence.put_doc("traces", trace_id, %{
               trace_id: trace_id,
               started_at: base,
               duration_ms: 250,
               span_count: 1,
               status: "error",
               agent_id: "calculator-benchmark"
             })

    span_doc = %{
      trace_id: trace_id,
      span_id: span_id,
      event_name: "agent.run",
      parent_span_id: nil,
      started_at: base,
      ended_at: base + 250,
      duration_ms: 250,
      entity_type: "agent",
      entity_id: "calculator-benchmark",
      status: "error",
      critical_path: true
    }

    assert :ok = Persistence.put_doc("spans", "#{trace_id}:#{span_id}", span_doc)

    on_exit(fn ->
      _ = Persistence.delete_doc("traces", trace_id)
      _ = Persistence.delete_doc("spans", "#{trace_id}:#{span_id}")
    end)

    {trace_id, span_id}
  end

  def handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end
