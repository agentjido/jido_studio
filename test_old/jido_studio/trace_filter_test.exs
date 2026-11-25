defmodule JidoStudio.TraceFilterTest do
  use ExUnit.Case, async: true

  alias JidoStudio.TraceFilter

  test "filters internal and entity type rows" do
    rows = [
      %{event_name: "agent", entity_type: "agent", internal: false},
      %{event_name: "tool", entity_type: "tool", internal: false},
      %{event_name: "internal", entity_type: "model", internal: true}
    ]

    assert [%{event_name: "tool"}] =
             TraceFilter.apply(rows, hide_internal: true, entity_type: "tool")
  end

  test "filters streaming chunk rows" do
    rows = [
      %{event_name: "chunked", chunk_index: 0, chunk_count: 2},
      %{event_name: "regular"}
    ]

    assert [%{event_name: "chunked"}] = TraceFilter.apply(rows, stream_only: true)
  end

  test "filters by query text" do
    rows = [
      %{event_name: "tool.execute", metadata: %{tool_name: "weather_lookup"}},
      %{event_name: "agent.tick", metadata: %{}}
    ]

    assert [%{event_name: "tool.execute"}] = TraceFilter.apply(rows, query: "weather_lookup")
  end
end
