defmodule JidoStudio.Agents.InstanceIndexTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Agents.InstanceIndex

  test "builds rows from running instances and trace fallback metadata" do
    agents = [
      %{
        slug: "weather-agent",
        name: "weather_agent",
        module: Jido.AI.Examples.WeatherAgent,
        running_instances: [%{id: "inst-1", pid: nil}]
      }
    ]

    now = ~U[2026-02-22 12:00:00Z]

    rows =
      InstanceIndex.build_rows(agents,
        now: now,
        trace_events: [
          %{
            instance_id: "inst-1",
            timestamp_ms: DateTime.to_unix(~U[2026-02-22 11:30:00Z], :millisecond),
            scope: %{project_id: "p1", user_id: "u1"}
          },
          %{
            instance_id: "inst-1",
            timestamp_ms: DateTime.to_unix(~U[2026-02-22 11:45:00Z], :millisecond),
            scope: %{project_id: "p1", user_id: "u1"}
          }
        ],
        viewer_count_fun: fn "inst-1" -> 3 end
      )

    assert [%{instance_id: "inst-1"} = row] = rows
    assert row.status == "offline"
    assert row.viewer_count == 3
    assert row.project_id == "p1"
    assert row.user_id == "u1"
    assert %DateTime{} = row.last_activity_at
    assert row.uptime_ms == 1_800_000
  end
end
