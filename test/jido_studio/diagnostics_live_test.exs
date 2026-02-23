defmodule JidoStudio.DiagnosticsLiveTest do
  use JidoStudio.ConnCase, async: false

  alias JidoStudio.Persistence

  test "diagnostics defaults to overview mode", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/diagnostics")

    assert html =~ "Cluster Runtime Status"
    assert html =~ "Deep Tools"
    assert html =~ "Overview"
  end

  test "timeline view requires a concrete node", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/studio/diagnostics?view=timeline&node=all")

    assert html =~ "Select a node for timeline"
    assert html =~ "Timeline requires a concrete node"
  end

  test "timeline view without trace_id shows trace picker", %{conn: conn} do
    {trace_id, _span_ids} = seed_timeline_trace()
    node_param = URI.encode_www_form(to_string(Node.self()))

    {:ok, _view, html} = live(conn, "/studio/diagnostics?view=timeline&node=#{node_param}")

    assert html =~ "Advanced Timeline Waterfall"
    assert html =~ "Select trace"
    assert html =~ trace_id
    assert html =~ "Choose a trace from the picker"
  end

  test "timeline trace view renders waterfall and supports span selection with deep links", %{
    conn: conn
  } do
    {trace_id, span_ids} = seed_timeline_trace()
    node_param = URI.encode_www_form(to_string(Node.self()))
    encoded_trace_id = URI.encode_www_form(trace_id)

    {:ok, view, html} =
      live(conn, "/studio/diagnostics?view=timeline&trace_id=#{trace_id}&node=#{node_param}")

    assert html =~ "Advanced Timeline Waterfall"
    assert html =~ "agent.run"
    assert html =~ "tool.add"

    view
    |> element("button[phx-click='select_timeline_span'][phx-value-span_id='#{span_ids.tool}']")
    |> render_click()

    rendered = render(view)
    assert rendered =~ "Span Details"
    assert rendered =~ "call-1"
    assert rendered =~ "task-1"

    assert has_element?(
             view,
             "a[href*='/studio/traces/#{encoded_trace_id}'][href*='node=#{node_param}']",
             "Open Trace Detail"
           )

    assert has_element?(
             view,
             "a[href*='/studio/actions'][href*='query=#{URI.encode_www_form(trace_id)}'][href*='node=#{node_param}']",
             "Open Actions"
           )

    assert has_element?(
             view,
             "a[href*='/studio/signals'][href*='query=#{URI.encode_www_form(trace_id)}'][href*='node=#{node_param}']",
             "Open Signals"
           )

    assert has_element?(
             view,
             "a[href*='/studio/workflows'][href*='query=#{URI.encode_www_form(trace_id)}'][href*='node=#{node_param}']",
             "Open Workflows"
           )
  end

  defp seed_timeline_trace do
    trace_id = "diag-timeline-#{System.unique_integer([:positive])}"
    base = System.system_time(:millisecond) - 5_000

    spans = %{
      root: "span-root-#{System.unique_integer([:positive])}",
      tool: "span-tool-#{System.unique_integer([:positive])}",
      middleware: "span-middleware-#{System.unique_integer([:positive])}"
    }

    assert :ok =
             Persistence.put_doc("traces", trace_id, %{
               trace_id: trace_id,
               started_at: base,
               duration_ms: 620,
               span_count: 3,
               status: "ok",
               agent_id: "calculator-demo"
             })

    span_docs = [
      %{
        span_id: spans.root,
        event_name: "agent.run",
        parent_span_id: nil,
        started_at: base,
        duration_ms: 620,
        ended_at: base + 620,
        entity_type: "agent",
        entity_id: "calculator-demo",
        status: "ok",
        critical_path: true
      },
      %{
        span_id: spans.tool,
        event_name: "tool.add",
        parent_span_id: spans.root,
        started_at: base + 120,
        duration_ms: 180,
        ended_at: base + 300,
        entity_type: "tool",
        entity_id: "Add",
        status: "ok",
        call_id: "call-1",
        task_id: "task-1",
        critical_path: true
      },
      %{
        span_id: spans.middleware,
        event_name: "middleware.audit",
        parent_span_id: spans.root,
        started_at: base + 80,
        duration_ms: 50,
        ended_at: base + 130,
        entity_type: "middleware",
        entity_id: "Audit",
        status: "ok",
        critical_path: false
      }
    ]

    Enum.each(span_docs, fn span ->
      assert :ok =
               Persistence.put_doc(
                 "spans",
                 "#{trace_id}:#{span.span_id}",
                 Map.put(span, :trace_id, trace_id)
               )
    end)

    on_exit(fn ->
      _ = Persistence.delete_doc("traces", trace_id)

      Enum.each(span_docs, fn span ->
        _ = Persistence.delete_doc("spans", "#{trace_id}:#{span.span_id}")
      end)
    end)

    {trace_id, spans}
  end
end
