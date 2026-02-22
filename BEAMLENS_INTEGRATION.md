# Jido Studio x Beamlens Integration Plan

## Summary
Integrate Beamlens into Jido Studio as an optional incident-intelligence layer, without duplicating dashboards or introducing hard dependencies on beta UI internals.

Primary strategy:
1. Beamlens core telemetry + coordinator API first.
2. Studio-native UX first.
3. Beamlens Web deep-link optional.

## Why This Matters
Jido Studio already answers "what are my Agents doing?" Beamlens adds "why is the runtime unhealthy?" and "what investigation result should I trust?".

Combined promise:
1. Detect abnormal behavior quickly.
2. Run investigation from Studio.
3. Review insight + evidence in one place.

## Scope
In scope:
1. Optional Beamlens detection and activation.
2. Beamlens telemetry ingestion into Studio traces/activity.
3. Diagnostics actions to run Beamlens investigations.
4. Investigation summary cards and detail links.
5. Optional extension nav link to mounted Beamlens Web.

Out of scope (v1):
1. Rebuilding the full Beamlens Web dashboard in Studio.
2. Tight coupling to Beamlens Web ETS store internals.
3. New host-app adapters.

## Principles
1. Optional by default: if Beamlens is absent, Studio behavior is unchanged.
2. Telemetry-first contract: rely on event streams and documented APIs.
3. Graceful fallback: explicit "not available" states, never blank failures.
4. Scope-aware: honor Studio global `runtime` + `node` semantics.
5. Minimal config: no required new config for single-runtime installs.

## Compatibility Targets
1. Beamlens core: `~> 0.3` (validated against `0.3.1`).
2. Beamlens Web: optional, currently beta (`0.1.0-beta.4`), treated as external UI.
3. Phoenix/LiveView compatibility remains governed by Studio package constraints.

## Architecture
### Data sources (priority order)
1. Beamlens core telemetry events via `Beamlens.Telemetry.event_names/0`.
2. Direct Beamlens API calls for control-plane actions:
   - `Beamlens.Coordinator.status/1`
   - `Beamlens.Coordinator.run/2`
3. Optional deep-link to `beamlens_web` route if installed and mounted.

### Integration seams in Studio
1. `JidoStudio.TraceCatalog` for dynamic event registration.
2. `JidoStudio.TraceBuffer` for capture/storage/broadcast.
3. `JidoStudio.DiagnosticsLive` and `JidoStudio.ActivityLive` for user-facing surfaces.
4. `JidoStudio.Extension` registry for optional nav/routes.

## Public Interface and Config
No required config changes.

Optional additions:
1. `config :jido_studio, :beamlens, [enabled: true]`
2. `config :jido_studio, :beamlens, [run_timeout_ms: 120_000]`
3. `config :jido_studio, :beamlens, [web_path: "/beamlens"]`

Default behavior:
1. Auto-detect Beamlens with `Code.ensure_loaded?(Beamlens)`.
2. Auto-enable telemetry ingestion when available.
3. Hide Beamlens controls when unavailable.

## Implementation Phases
## Phase 1: Telemetry Bridge (Low Risk, High Value)
1. Add `JidoStudio.Beamlens` helper module:
   - `installed?/0`
   - `telemetry_events/0` (falls back to static prefixes if unavailable)
2. Extend `TraceCatalog.configured_events/0` to include Beamlens events when installed.
3. Ensure `TraceBuffer` normalizes Beamlens metadata safely (inspect large structs as needed).
4. Add source badges/filter labels (`beamlens`) in Activity/Diagnostics/Traces views.
5. Add tests for event registration + ingestion when Beamlens is present/absent.

Acceptance criteria:
1. Beamlens events appear in Studio streams with no runtime errors.
2. Studio still boots and functions with no Beamlens dependency installed.

## Phase 2: Investigation Runner in Diagnostics
1. Add Diagnostics action card: "Run Beamlens Investigation".
2. Add minimal form:
   - reason/context text
   - optional timeout
3. Execute on selected node/runtime via existing cluster/runtime scope helpers.
4. Render result summary:
   - insight count
   - top insight summary
   - trace IDs and timestamps
5. Show actionable failures:
   - coordinator not running
   - timeout
   - RPC unreachable

Acceptance criteria:
1. User can trigger investigation from Diagnostics in <= 2 clicks after entering reason.
2. Errors are explicit and non-fatal to page state.

## Phase 3: Investigation Surfaces
1. Add "Investigations" section to Diagnostics or Activity:
   - recent insights
   - recent notifications
   - correlation confidence
2. Link each investigation to:
   - trace details (Studio trace explorer)
   - related runtime events
3. Add lightweight filters:
   - status/severity
   - source operator/coordinator
   - node

Acceptance criteria:
1. On-call can go from symptom to a structured insight summary in one page flow.
2. Links to deeper traces and events are always available.

## Phase 4: Optional Beamlens Web Extension Link
1. Add extension module `JidoStudio.Extensions.Beamlens`:
   - `installed?/0` checks `BeamlensWeb.Router` availability.
   - nav item "Beamlens" under extension section.
2. Deep-link to configured `web_path` while preserving Studio scope query when possible.
3. Do not iframe or clone Beamlens Web in v1.

Acceptance criteria:
1. If Beamlens Web exists, user sees discoverable link from Studio.
2. If not installed, no nav noise is introduced.

## File-Level Change Map
New files:
1. `lib/jido_studio/beamlens.ex`
2. `lib/jido_studio/extensions/beamlens.ex` (optional phase 4)
3. `test/jido_studio/beamlens_test.exs`
4. `test/jido_studio/beamlens_telemetry_integration_test.exs`

Updated files:
1. `lib/jido_studio/trace_catalog.ex`
2. `lib/jido_studio/trace_buffer.ex`
3. `lib/jido_studio/live/diagnostics_live.ex`
4. `lib/jido_studio/live/activity_live.ex`
5. `lib/jido_studio/extensions.ex`
6. `README.md`
7. `specs/page_contracts.md` (if Investigations surface is promoted)

## Data and Error Contracts
1. Missing Beamlens module:
   - return `{:error, :beamlens_unavailable}` from helper functions.
2. Coordinator unavailable:
   - render "Coordinator not started" with suggested fix.
3. RPC timeout/unreachable node:
   - render node-scoped warning; do not crash LiveView.
4. Large metadata structs:
   - truncate/inspect for UI preview; keep raw event in trace buffer as map-safe data.

## Testing Strategy
Unit tests:
1. `Beamlens.installed?/0` and dynamic event discovery behavior.
2. Event normalization for representative Beamlens metadata payloads.
3. Failure mapping for coordinator/run timeouts and unavailable coordinator.

Integration/LiveView tests:
1. Diagnostics run action happy path (mocked Beamlens adapter).
2. Diagnostics run action failure states.
3. Activity/Traces show Beamlens source labels and filters.
4. No-Beamlens environment regression (all existing pages remain green).

Regression gate:
1. Existing observability suites remain green.
2. Existing cluster/runtime scope propagation remains green.

## Rollout Plan
1. Ship Phase 1 first (telemetry visibility only).
2. Add Phase 2 in next release with internal dogfooding.
3. Add Phase 3 only after real usage validates information density.
4. Keep Phase 4 optional due Beamlens Web beta status.

## Risks and Mitigations
1. Risk: Beamlens Web beta API churn.
   Mitigation: avoid direct dependency on Beamlens Web internal stores.
2. Risk: High event volume from telemetry.
   Mitigation: rely on existing trace buffer limits and source filtering.
3. Risk: User confusion between Agent observability and runtime investigations.
   Mitigation: clear copy in Diagnostics: "Agent execution" vs "Runtime investigation".

## Open Questions
1. Should investigation history live in existing trace/event pages only, or get a dedicated top-level route later?
2. Should Studio provide one-click "Investigate this failure" context transfer from Agent instance pages?
3. Do we want cost visibility (token/cost estimate) for Beamlens runs in Diagnostics?
