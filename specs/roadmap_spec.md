# Roadmap Spec

## Purpose
Provide an implementation sequence that delivers a coherent operator-first product without stalling deep diagnostic power.

## Delivery Principles
1. Stabilize IA and scope semantics first.
2. Reduce cognitive load before adding advanced visualizations.
3. Keep compatibility routes and non-breaking defaults.
4. Gate each phase with observable acceptance tests.

## Phase 1: Scope and Navigation Coherence
### Deliverables
- Runtime + node scope model in shell
- Simple vs advanced scope controls
- canonical route propagation for `runtime` and `node`
- compatibility route checks (`/registry` -> `/catalog`)

### Gates
- scope persistence tests across main routes
- invalid scope fallback tests
- no regressions in existing route suite

## Phase 2: Onboarding and Profiled Setup
### Deliverables
- setup assistant on Home + Settings entry
- setup checks (runtime, persistence, realtime, chat keys, smoke test)
- config profile snippets and status badges

### Gates
- onboarding completion flow tests
- check-state rendering tests (pass/warn/fail)
- docs updates with profile guidance

## Phase 3: Agents Instance Manager Polish
### Deliverables
- lock stable 3-rail instance layout behavior
- clarify Play/Observe/Configure copy and panel contracts
- strengthen non-chat default flows
- improve actionable error states

### Progress Notes (Current Branch)
- Added route/panel contract extraction (`contracts.ex`, `routes.ex`).
- Added state-focused modules (`index_state.ex`, `show_state.ex`, `runner_state.ex`, `observability_state.ex`, `errors.ex`).
- Added dedicated render modules (`render/index_view.ex`, `render/instance_view.ex`).
- Added workspace/chat state modules (`workspace_state.ex`, `chat_state.ex`) and delegated `AgentsLive` flow/event logic.
- Added route/layout regression coverage (`agents_instance_routes_test.exs`, `agents_instance_layout_test.exs`).
- Reduced `AgentsLive` to orchestration and achieved sub-900 LOC target.

### Gates
- section/panel route and persistence tests
- visual stability tests for summary rail
- guarded runner behavior tests remain green

## Phase 4: Diagnostics Advanced Timeline
### Deliverables
- timeline view under Diagnostics advanced mode
- single-trace waterfall with critical path highlight
- deep links to traces/actions/signals pages

### Gates
- payload cap and performance checks
- timeline interaction tests (select span, open details)
- diagnostics fallback states with sparse data

## Phase 5: Hardening and Adoption
### Deliverables
- polish copy across top pages using message hierarchy
- instrument north-star metrics
- finalize docs and examples for common deployment profiles

### Gates
- first-run success measurement instrumentation
- time-to-triage benchmark baseline
- regression suite green

## Regression Guardrails
- Existing `agents_live`, `observability`, `delegation`, `threads`, and cluster tests remain green.
- New scope/onboarding/timeline tests must be additive and non-breaking.

## Exit Criteria
1. Users can explain what each top-level page is for.
2. Scope controls feel simple by default and powerful when needed.
3. First successful interaction can be achieved quickly with setup guidance.
4. Diagnostic workflows shorten time to confident next action.
