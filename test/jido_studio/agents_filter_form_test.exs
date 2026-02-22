defmodule JidoStudio.Agents.FilterFormTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Agents.FilterForm

  test "parse/apply filters status, presence, and search" do
    rows = [
      %{
        instance_id: "inst-running-weather",
        agent_slug: "weather",
        agent_name: "Weather Agent",
        status: "running",
        viewer_count: 2,
        last_activity_at: ~U[2026-02-22 10:00:00Z],
        started_at: ~U[2026-02-22 09:00:00Z]
      },
      %{
        instance_id: "inst-idle-router",
        agent_slug: "router",
        agent_name: "Router Agent",
        status: "idle",
        viewer_count: 0,
        last_activity_at: ~U[2026-02-22 09:30:00Z],
        started_at: ~U[2026-02-22 08:00:00Z]
      }
    ]

    filters =
      FilterForm.parse(
        %{
          "status_filter" => "running",
          "presence_filter" => "has_viewers",
          "search_query" => "weather",
          "sort_by" => "viewers"
        },
        FilterForm.new()
      )

    assert [%{instance_id: "inst-running-weather"}] = FilterForm.apply_filters(rows, filters)
  end

  test "default sort uses most recent activity first" do
    rows = [
      %{
        instance_id: "older",
        status: "running",
        viewer_count: 0,
        last_activity_at: ~U[2026-02-22 08:00:00Z]
      },
      %{
        instance_id: "newer",
        status: "running",
        viewer_count: 0,
        last_activity_at: ~U[2026-02-22 11:00:00Z]
      }
    ]

    sorted = FilterForm.apply_filters(rows, FilterForm.new())

    assert Enum.map(sorted, & &1.instance_id) == ["newer", "older"]
  end

  test "query params omit default values" do
    defaults = FilterForm.new()

    params =
      FilterForm.to_query_params(
        %FilterForm{defaults | status_filter: "running", search_query: "abc"},
        defaults
      )

    assert params == %{"status_filter" => "running", "search_query" => "abc"}
  end
end
