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
- setup regression re-entry banner with local persistence
- setup/scope telemetry hooks for runtime, node, step, and profile changes

### Progress Notes (Current Branch)
- Added shared setup domain builder:
  - `lib/jido_studio/setup.ex`
- Added profile guidance module:
  - `lib/jido_studio/setup/profiles.ex`
- Wired Home + Settings to shared checks and profile guidance:
  - `lib/jido_studio/live/home_live.ex`
  - `lib/jido_studio/live/settings_live.ex`
- Added setup/scope telemetry wrapper and emissions:
  - `lib/jido_studio/telemetry.ex`
  - `lib/jido_studio/hooks.ex`
- Added local setup regression re-entry behavior:
  - `priv/static/jido_studio.js`
- Added additive coverage for setup logic, Home, Settings, and telemetry:
  - `test/jido_studio/setup_test.exs`
  - `test/jido_studio/home_live_test.exs`
  - `test/jido_studio/settings_live_test.exs`
  - `test/jido_studio/setup_telemetry_test.exs`

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

### Progress Notes (Current Branch)
- Added dedicated timeline shaping module:
  - `lib/jido_studio/diagnostics/timeline.ex`
- Extended Diagnostics route/query semantics:
  - `view`, `trace_id`, `span_id`, `critical`, `entity_type`, `hide_internal`
- Added concrete-node requirement for timeline mode:
  - `node=all` now shows explicit node-selection guidance.
- Added timeline controls and waterfall surface in `DiagnosticsLive`:
  - trace picker, lane filters, critical/hide toggles, span detail pane, deep links.
- Added timeline-focused test coverage:
  - `test/jido_studio/diagnostics_live_test.exs`
  - `test/jido_studio/diagnostics_timeline_test.exs`

### Gates
- payload cap and performance checks
- timeline interaction tests (select span, open details)
- diagnostics fallback states with sparse data

## Phase 5: Hardening and Adoption
### Deliverables
- polish copy across top pages using message hierarchy
- instrument north-star metrics
- finalize docs and examples for common deployment profiles

### Progress Notes (Current Branch)
- Added shared product metrics helper and session correlation metadata:
  - `lib/jido_studio/product_metrics.ex`
  - `lib/jido_studio/hooks.ex`
  - `lib/jido_studio/telemetry.ex`
- Added interaction, onboarding, triage, and next-step coverage event emissions:
  - `[:jido_studio, :interaction, :started]`
  - `[:jido_studio, :interaction, :completed]`
  - `[:jido_studio, :onboarding, :first_interaction_succeeded]`
  - `[:jido_studio, :triage, :warning_opened]`
  - `[:jido_studio, :triage, :root_cause_opened]`
  - `[:jido_studio, :incidents, :next_step_links_evaluated]`
- Added time-to-triage benchmark entrypoint:
  - `mix jido_studio.benchmark.triage`
  - `test/jido_studio/triage_benchmark_test.exs`
- Reduced duplicate collection/path-state logic:
  - `lib/jido_studio/cluster/collect.ex`
  - `lib/jido_studio/live/home_live/state.ex`

### Gates
- first-run success measurement instrumentation
- time-to-triage benchmark baseline
- regression suite green

## Phase 6: Guided Adoption and Tour UX
### Deliverables
- dedicated `/guide` page for first-run and triage workflows
- coachmark-style guided steps across Home, Agents, Diagnostics, and Settings
- persistent local progress with resume/replay controls
- additive tour telemetry events (`started`, `step_viewed`, `step_completed`, `dismissed`, `completed`)

### Phase 6.1: Beginner Onboarding and Agent Discovery Clarity
#### Deliverables
- bundled deterministic `JidoStudio.BeginnerAgent` starter path
- beginner visibility gate:
  - `config :jido_studio, :beginner_agent, enabled: true`
- starter selection service shared by Home/Agents/Guide
- Agents inventory explainer and Source App ownership column
- explicit starter deep-link flow (`/agents/:slug?start=1`) with modal-open but no auto-run
- additive onboarding telemetry:
  - `[:jido_studio, :onboarding, :starter_opened]`
  - `[:jido_studio, :onboarding, :starter_start_modal_opened]`

### Gates
- guide route and sidebar ordering tests
- guided flow definition tests with stable selector/path contracts
- telemetry coverage for tour lifecycle events

### Phase 6.1 Gates
- beginner action determinism tests
- registry visibility/source ownership tests
- starter picker fallback-order tests
- Agents/Guide/Home starter UX + deep-link tests

## Regression Guardrails
- Existing `agents_live`, `observability`, `delegation`, `threads`, and cluster tests remain green.
- New scope/onboarding/timeline tests must be additive and non-breaking.

## Exit Criteria
1. Users can explain what each top-level page is for.
2. Scope controls feel simple by default and powerful when needed.
3. First successful interaction can be achieved quickly with setup guidance.
4. Diagnostic workflows shorten time to confident next action.
