# Jido Studio Metrics

## Purpose
Define the additive telemetry contract used for product hardening metrics in Phase 5.

## Event Namespace
All metrics events are emitted under the `[:jido_studio, ...]` prefix.

## Events

### Interaction
- `[:jido_studio, :interaction, :started]`
- `[:jido_studio, :interaction, :completed]`

Use to measure first interaction success and completion rates for chat and non-chat workflows.

### Onboarding
- `[:jido_studio, :onboarding, :first_interaction_succeeded]`

Emitted once per Studio session when the first successful interaction completes.

### Triage
- `[:jido_studio, :triage, :warning_opened]`
- `[:jido_studio, :triage, :root_cause_opened]`

Use to measure warning-to-root-cause latency.

### Incident Actionability
- `[:jido_studio, :incidents, :next_step_links_evaluated]`

Use to track how many surfaced warnings include actionable next-step links.

## Measurements
Each event includes:
- `count`
- `timestamp_ms`

## Metadata Contract
Common keys:
- `runtime`
- `node`
- `path`
- `source`
- `session_id`

Event-specific keys:
- `mode`
- `status`
- `warning_kind`
- `trace_id`
- `span_id`
- `linked_count`
- `total_count`

## Benchmark
Run the time-to-triage baseline:

```bash
mix jido_studio.benchmark.triage
```

This benchmark computes and prints a baseline `time_to_triage_ms` from warning-opened to root-cause-opened telemetry.
