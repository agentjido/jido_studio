# Agents Instance Manager Spec

## Purpose
Specify the instance-level interaction model for `Agents` so chat and non-chat workflows feel coherent and safe.

## Route Contract
- Base:
  - `<prefix>/agents/:slug/:instance_id`
- Canonical section routes:
  - `<prefix>/agents/:slug/:instance_id/play`
  - `<prefix>/agents/:slug/:instance_id/observe`
  - `<prefix>/agents/:slug/:instance_id/configure`
- Query:
  - `panel=<tab_id>`
  - `runtime=<runtime_key>`
  - `node=all|<node>`

## Layout Contract
Stable 3-rail layout:
1. Threads rail (left)
2. Section/panel content rail (center)
3. Summary/triage rail (right, persistent)

Summary rail must remain visible when switching sections/panels.

## Section Model
### Play
Purpose: run and test behavior

Panels:
- `chat`
- `interact`
- `messages`

Behavior:
- If chat unavailable, default to `interact` with clear explanation.
- Show payload guardrails before dispatch.

### Observe
Purpose: inspect what happened

Panels:
- `events`
- `todos`
- `thread_context`
- `thread_events`

Behavior:
- event stream cap and search
- explicit no-data states

### Configure
Purpose: inspect setup and runtime internals

Panels:
- `instance`
- `sub_agents`
- `tasks`
- `tool_insights`
- `middleware`

Behavior:
- config snapshots and runtime status
- deep links to diagnostics where available

## Interaction Safety Contract
1. Execution requires explicit arm/confirm step.
2. Payload changes invalidate previous arm state.
3. Sync mode is default; async opt-in.
4. Validation errors are field-specific when schema exists.
5. Missing schema falls back to raw payload mode with warning.

## Data Contract
Minimum assign/state expectations:
- selected section
- selected panel
- runtime messages snapshot
- event stream snapshot
- todos snapshot
- runner form/result/history
- summary metadata and triage links

## UX Contract
- Primary action in Play is always obvious.
- Non-chat agents remain first-class via Interact.
- All errors provide actionable next steps.
- No section switch should trigger disruptive layout jumps.

## Acceptance Criteria
1. Any running non-chat instance is usable without coding via `Play -> Interact`.
2. `Observe` supports quick event triage and thread context inspection.
3. `Configure` exposes instance internals without hiding summary rail.
4. Sharable URLs reopen same section/panel/scope.
