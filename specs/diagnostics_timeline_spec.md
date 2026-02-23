# Diagnostics Timeline Spec

## Purpose
Define an advanced, OTEL-style timeline view for deep diagnostics without complicating primary operator workflows.

## Positioning
- Location: `Diagnostics` page advanced section.
- Audience: secondary and tertiary personas (developer, on-call).
- Default visibility: off/collapsed.

## User Value
1. Identify critical path quickly.
2. Visualize parallel vs serialized spans.
3. Spot retries, stalls, and long-running operations.
4. Correlate signals/actions/workflows/sub-agent work in time.

## Scope
v1 focuses on single-trace waterfall with rich drill-down.

Out of scope for v1:
- full cross-trace live streaming waterfall
- long-lived unlimited timeline canvas

## Route and Query Contract
- Entry route:
  - `<prefix>/diagnostics?view=timeline`
- Optional query:
  - `trace_id=<trace_id>`
  - `span_id=<span_id>`
  - `critical=0|1`
  - `entity_type=all|agent|model|tool|middleware|scheduler|sensor|other`
  - `hide_internal=0|1`
  - `runtime=<runtime_key>`
  - `node=<node_name>`

If `trace_id` is missing, show recent trace picker.
If `node=all`, timeline rendering is disabled and UI prompts the user to select a concrete node.

## Visual Model
Lanes grouped by:
1. agent/sub-agent
2. operation type (signal/action/tool/middleware/workflow)

Span bar fields:
- start time
- duration
- status
- label
- call/trace reference

Interactions:
- click span -> details side pane
- hover span -> quick metadata tooltip
- highlight critical path toggle

## Data Model
Required span fields:
- `id`
- `parent_id`
- `trace_id`
- `name`
- `start_ns|start_ms`
- `end_ns|end_ms|duration_ms`
- `status`
- `attributes` (source/type/call_id/task_id/scope)

## Performance Guardrails
1. Default span cap per trace (for example 2_000).
2. Progressive fetch for additional ranges.
3. Virtualized list/canvas rendering.
4. Pre-shaped server payload to avoid heavy client transforms.
5. Client warning when cap is reached.

## UX Guardrails
- Advanced label must be visible.
- Offer "Open standard trace view" escape hatch.
- Show explicit "insufficient data" state when timing fields are missing.

## Success Metrics
- Reduced median time from error signal to identified failing span.
- Higher trace-to-root-cause completion rate.
- Low UI jank under capped span load.

## Acceptance Criteria
1. User can load timeline for a selected trace and inspect span details.
2. Timeline remains responsive at configured span cap.
3. Critical path view identifies top contributors to latency.
4. Timeline can deep-link back to existing traces/actions/signals pages.

## V1 Implementation Notes (Current Branch)
1. Timeline remains in Diagnostics advanced mode only; Traces page remains canonical deep explorer.
2. Span cap reuses existing `TraceFilter.max_span_rows/0` with a hard upper bound of `2_000`.
3. Missing timing fields are handled explicitly:
   spans without usable timing are excluded from bars and reported in warnings.
4. `critical=1` enables critical-path emphasis and `critical=0` disables that emphasis.
