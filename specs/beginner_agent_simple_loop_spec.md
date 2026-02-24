# Beginner Agent Simple Loop Spec

## Purpose
Define the minimum user-friendly loop for a first-time operator using a simple deterministic agent (for example `JidoStudio.BeginnerAgent`) in Studio.

Primary question:
"Can I run one safe interaction, understand what changed, and find the trace in under 2 minutes?"

## Current Route Context
Example route today:
- `/studio/agents/:slug/:instance_id/play?panel=interact&runtime=<key>&node=<node>`
- concrete example from local run:
  - `/studio/agents/dZkOyn9f/019c8c39-4e18-751e-86a9-f7aa283eb518/play?node=nonode%40nohost&panel=interact`

View mode contract:
- `/studio/agents/:slug/:instance_id` defaults to `view=basic`
- `view=advanced` preserves full legacy workbench behavior
- legacy deep links with `panel`, `tab`, `/observe`, `/configure` continue to resolve advanced surfaces

## What Exists Today (Baseline)
For a basic agent, Studio already exposes:
1. Agent runtime process and instance lifecycle.
2. Signals consumed and actions discovered (introspection).
3. Guarded runner (`Arm Execute` then `Run`) with sync/async mode.
4. JSON payload editor and schema view toggle.
5. Runner result and recent run history.
6. Runtime messages panel.
7. Observe panels:
   - events
   - todos
   - thread context
   - thread events
8. Configure panels:
   - instance
   - sub_agents
   - tasks
   - tool insights
   - middleware
9. Summary rail with triage links and traces deep-link.
10. Trace and diagnostics pages with timeline/root-cause surfaces.
11. Workspace/thread persistence.

## Core Problem
The first-run interaction flow is technically complete but cognitively heavy.

Top friction points:
1. Payload input is raw JSON-first; no fast structured form path for beginners.
2. "What should I do first?" is not obvious once inside `Play -> Interact`.
3. Result interpretation is weak:
   - no clear state delta summary
   - no explicit "memory changed" explanation
4. Trace linkage exists but is not emphasized as the next step in the loop.
5. Plugin/memory surfaces are spread across panels and not framed as one beginner narrative.

## Scope (Phase 6.2)
In scope:
1. Beginner-first "simple loop" UX on top of current route/IA.
2. Better payload entry for deterministic actions/signals.
3. Explicit post-run explanation:
   - what changed
   - where memory lives
   - how to inspect trace/events next
4. Inline orientation for agent memory/plugins/actions/traces in one place.

Out of scope:
1. Route changes.
2. Auto-running actions without confirmation.
3. Host config mutation.
4. Re-architecture of all Observe/Configure panels.

## UX Contract (Simple Loop)
### Step 1: Pick starter interaction
At `Play -> Interact`, show a "Start here" block with:
1. 2-4 curated starter operations (for Beginner agent: `beginner.ping`, `beginner.add`, `beginner.tip`, `beginner.reset`).
2. One-click preset buttons that fill payload.
3. Plain-language goal text per operation.

### Step 2: Enter payload without JSON friction
For selected signal/action:
1. Default to generated field form when schema is convertible.
2. Keep raw JSON mode as explicit fallback.
3. Show validation errors inline per field and map to JSON when raw mode is active.

### Step 3: Run safely
Keep existing guardrails:
1. Explicit arm required.
2. Payload edits disarm execute.
3. No auto-dispatch.

### Step 4: Explain result
After run:
1. Show operation outcome badge (`success`/`error`).
2. Show concise state delta summary:
   - changed keys
   - previous -> new values (safe truncation)
3. Show explicit memory note:
   - "Agent memory/state updated in runtime process."

### Step 5: Guide next observation action
Immediately present links/buttons:
1. `View Instance Events` (Observe).
2. `View Thread Context` (Observe).
3. `Open Trace` (if trace id exists).
4. `Open Diagnostics Timeline` (if trace id exists).

## Data Model Additions (Additive)
1. `last_run_summary` view model in `AgentsLive`:
   - `dispatch_ref`
   - `status`
   - `trace_id` (if available)
   - `state_delta` (changed keys only)
   - `next_actions`
2. Optional `starter_operations` in interaction model:
   - ordered starter entries with label, rationale, and preset payload.

## Telemetry Additions (Additive)
1. `[:jido_studio, :onboarding, :starter_payload_prefilled]`
2. `[:jido_studio, :interaction, :state_delta_viewed]`
3. `[:jido_studio, :interaction, :next_action_opened]`

Metadata:
- `runtime`, `node`, `path`, `session_id`
- `agent_slug`, `dispatch_ref`, `mode`, `source`
- optional: `trace_id`, `next_action`

## Implementation Plan
1. Add beginner-first starter operation presenter.
2. Add schema-first form renderer to runner panel (preserve raw JSON toggle).
3. Add post-run state delta summarizer.
4. Add trace-aware next action cluster under run result.
5. Add additive telemetry around prefill, delta-view, and next-action click.
6. Add Guide section linking directly to this simple loop contract.

## Test Plan
1. `AgentsLive` integration:
   - starter operation buttons render
   - preset fills payload/form
   - execute remains gated by arm
2. Runner UX:
   - form mode and raw mode both supported
   - validation errors are actionable
3. Post-run summary:
   - state delta shown for successful deterministic actions
   - trace deep links present when trace exists
4. Telemetry:
   - prefill event fires once per click
   - next-action event carries action type + trace metadata
5. Regression:
   - existing interact/chat flows unchanged for non-beginner agents
   - no route/query contract breaks

## Acceptance Criteria
1. New user can complete one successful beginner interaction in <= 2 minutes.
2. User can explain where memory changed without reading code.
3. User can reach a trace/timeline view in one click from run result.
4. Existing power-user raw JSON flow still available.
