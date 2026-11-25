---
title: Jido Studio v2 feature checklist
status: active
last-reviewed: 2026-11-24
---

# Jido Studio v2 feature checklist

Use this checklist to select and verify small v3 additions. It records
operator features, host options, and support behavior found at v2 commit
`b5aea45`. The [inventory](jido-studio-v2-inventory.md) explains the feature
groups and the gaps in the v2 implementation. The
[visual reference](../archive/jido-studio-v2/README.md) shows the screens.

A checked item has matching evidence on `release/v3`. An open item is a
candidate. Select only the items approved for the current change. For each
restored item, record the v3 source, the supported user outcome, and a
playground check. Keep item IDs stable. Use the
[decision roadmap](jido-studio-v3.csv) for product and architecture decisions.

| Proposed order | Select from | Evidence for review |
| --- | --- | --- |
| Shell and components | MOUNT, LOOK | The v3 playground matches the selected v2 visual references with desktop and narrow layouts. |
| Read-only agent inspection | AGENT, BENCH, CATALOG | A host-approved viewer can distinguish catalog definitions from running agents and reopen a stable detail link. |
| Read-only diagnosis | HOME, ACT, SIGNAL, ACTION, FLOW, TRACE, DIAG | A deterministic failure leads to the available evidence. The UI states when evidence or permission is missing. |
| First-run tasks and reproduction | SETUP, GUIDE, RUN | The host selects which checks and operations to enable. A deterministic fixture proves the result. |
| Optional and operational features | CHAT, THREAD, DELEG, SCOPE, STORE, EXT, METRIC | Add one approved capability at a time with its data owner and support limits. |

## Embedded mount and host behavior

- [x] **MOUNT-01** Mount the Studio index with `jido_studio "/studio"` inside a host Phoenix browser scope.
- [x] **MOUNT-02** Let hosts pass LiveView `:on_mount` hooks.
- [x] **MOUNT-03** Preserve the configured mount prefix in Studio links. Use the shared path builder for new diagnostics and workbench routes.
- [x] **MOUNT-04** Preserve runtime and node query values in shell navigation and showcase tabs. Use the same query rules when a compatibility redirect is added.
- [x] **MOUNT-05** Supply scoped styles and shell behavior at the mount. The host provides the root layout and LiveView client.
- [x] **MOUNT-06** Let the host grant read-only or full access, or redirect a forbidden user. Check action access before a handler changes runtime or stored data.
- [x] **MOUNT-07** Use the host's LiveView socket and apply its CSP nonces to Studio assets.

[Old router](../../lib_old/jido_studio/router.ex) · [Old layout](../../lib_old/jido_studio/layouts.ex) · [Old resolver](../../lib_old/jido_studio/resolver.ex) · [v3 mount test](../../studio_playground/test/studio_playground_web/studio_mount_test.exs)

The v3 tests cover two mounts in one host, scope in links and LiveView
patches, host CSP nonce assigns, and forbidden access on initial and
connected mounts. [Host setup](../../README.md) · [Mount](../../lib/jido_studio/mount.ex) ·
[Access](../../lib/jido_studio/access.ex)

## Shell and UI components

- [x] **LOOK-01** Left sidebar with Studio brand, scope summary, primary routes, an optional section, and a clear active route. See EXT-01 for extension registration.
- [x] **LOOK-02** Collapse and expand the sidebar. Keep controls available in the collapsed state and remember the selection.
- [x] **LOOK-03** Dark and light themes. Restore the saved theme when Studio opens.
- [x] **LOOK-04** Shared page title, explanatory subtitle, and action area.
- [x] **LOOK-05** Shared cards, count cards, and dense tables with horizontal overflow when needed.
- [x] **LOOK-06** Status dots and badges with neutral, success, warning, error, and information treatments.
- [x] **LOOK-07** Primary, secondary, ghost, and destructive button treatments with focus and disabled states.
- [x] **LOOK-08** Linkable tabs, selected states, empty-state cards, and dialogs.
- [x] **LOOK-09** Page scroll and a reusable workbench layout with independent pane scroll on desktop.
- [x] **LOOK-10** Narrow viewport layouts with stacked cards and panes, scrollable tables, and visible focus.

[Old layout](../../lib_old/jido_studio/layouts.ex) · [Shared components](../../lib_old/jido_studio/components.ex) · [Source CSS](../../assets/jido_studio.css) · [Visual reference](../archive/jido-studio-v2/README.md)

The playground showcase exercises the shared components on one route with
sample data. [Open the showcase](http://localhost:4702/studio/components) ·
[v3 layout](../../lib/jido_studio/layouts.ex) · [Components](../../lib/jido_studio/components.ex) ·
[Showcase](../../lib/jido_studio/showcase_live.ex)

## Home

- [ ] **HOME-01** Show what Studio can do and link to Agents, Activity, and Diagnostics.
- [ ] **HOME-02** Show attention items with severity, summary, and an evidence link.
- [ ] **HOME-03** Show the setup status and recovery links when a check fails.
- [ ] **HOME-04** Show fleet counts, top agents, recent activity, and recent failures.
- [ ] **HOME-05** Show a starter recommendation with a link to start or open the agent.
- [ ] **HOME-06** Remember whether the setup and starter cards are hidden. Show setup again when its state regresses.

[Home](../../lib_old/jido_studio/live/home_live.ex) · [Home state](../../lib_old/jido_studio/live/home_live/state.ex) · [Home tests](../../test_old/jido_studio/home_live_test.exs)

## Setup, Settings, and About

- [ ] **SETUP-01** Check whether Studio can reach the selected Jido runtime.
- [ ] **SETUP-02** Report persistence readiness, adapter, and relevant storage configuration.
- [ ] **SETUP-03** Report live updates and presence readiness.
- [ ] **SETUP-04** Check whether a supported chat provider is configured. Show guidance for missing credentials without showing credential values.
- [ ] **SETUP-05** Check smoke-interaction readiness and link to a runnable target.
- [ ] **SETUP-06** Show pass, warning, failure, and information states with relevant recovery links.
- [ ] **SETUP-07** Let the operator rerun checks from Home and Settings.
- [ ] **SETUP-08** Show configuration snippets for Local Dev, Chat Demo, and Team Durable Ops.
- [ ] **SETUP-09** Summarize runtime configuration in Settings, including trace limits and event catalog, persistence, thread storage, live updates, and evals.
- [ ] **SETUP-10** Show Studio version, runtime details, and resource links in About.

[Checks](../../lib_old/jido_studio/setup.ex) · [Profiles](../../lib_old/jido_studio/setup/profiles.ex) · [Settings](../../lib_old/jido_studio/live/settings_live.ex) · [About](../../lib_old/jido_studio/live/about_live.ex)

## Guide and starter

- [ ] **GUIDE-01** Explain the difference between discovered agent modules and running instances.
- [ ] **GUIDE-02** Offer a deterministic starter agent when available and choose a suitable fallback.
- [ ] **GUIDE-03** Provide sample ping, addition, tip, and reset operations with initial inputs.
- [ ] **GUIDE-04** Offer First 5 Minutes, Setup + First Interaction, and Incident Triage tours.
- [ ] **GUIDE-05** Show the current step and highlight its target. Save progress and support resume, replay, and dismissal. The v2 script supplies the markup, but the shipped CSS lacks the highlight and overlay rules.

[Guide](../../lib_old/jido_studio/live/guide_live.ex) · [Tours](../../lib_old/jido_studio/guided_tour.ex) · [Starter operations](../../lib_old/jido_studio/agents/starter_operations.ex) · [Starter selection](../../lib_old/jido_studio/onboarding/starter_agent.ex)

## Agent inventory

- [ ] **AGENT-01** List running instances and discovered modules in separate parts of the page.
- [ ] **AGENT-02** Show instance ID, agent, node, status, uptime, last activity, and viewer count when available.
- [ ] **AGENT-03** Search and filter instances. Offer sort options.
- [ ] **AGENT-04** Show product and internal agent groups according to configured tags.
- [ ] **AGENT-05** Show where each agent module came from, including its source application.
- [ ] **AGENT-06** Open an agent module page from the inventory and list its instances.
- [ ] **AGENT-07** Follow or unfollow a selected instance.
- [ ] **AGENT-08** Allow automatic selection of an instance that matches a follow target.
- [ ] **AGENT-09** Offer manual refresh, event-driven refresh, and polling when live events are unavailable.
- [ ] **AGENT-10** Show the start-instance dialog with fields from the selected agent presenter.
- [ ] **AGENT-11** Report validation or start failure. On success, open the new instance.
- [ ] **AGENT-12** Link to the start dialog from the starter flow without automatic follow navigation.

[Registry](../../lib_old/jido_studio/agent_registry.ex) · [Instance index](../../lib_old/jido_studio/agents/instance_index.ex) · [Index UI](../../lib_old/jido_studio/live/agents_live/render/index_view.ex) · [LiveView](../../lib_old/jido_studio/live/agents_live.ex)

## Agent workbench

- [ ] **BENCH-01** Open an instance with a shareable URL. Encode IDs that contain slashes.
- [ ] **BENCH-02** Keep the view, section, and panel selection in the URL.
- [ ] **BENCH-03** Provide a Basic View with the starter loop, result, state change, and next action.
- [ ] **BENCH-04** Provide an Advanced View with Play, Observe, and Configure sections.
- [ ] **BENCH-05** Offer Chat, Interact, and Messages in Play when applicable.
- [ ] **BENCH-06** Offer Events, TODOs, Thread Context, and Thread Events in Observe.
- [ ] **BENCH-07** Offer Instance, Sub-Agents, Tasks, Tool Insights, and Middleware in Configure where evidence is available.
- [ ] **BENCH-08** Keep instance status, breadcrumbs, controls, and a trace link available in the workbench.
- [ ] **BENCH-09** Show current state and configuration with a presenter for the agent or strategy.
- [ ] **BENCH-10** Support default, ReAct, behavior tree, and WeatherAgent presentation in the v2 reference. Select only supported presenter equivalents for v3.
- [ ] **BENCH-11** Show runtime messages when a snapshot provides them.
- [ ] **BENCH-12** Merge instance and observed events, search events, and expand raw payloads.
- [ ] **BENCH-13** Show strategy TODOs and thread context when available.
- [ ] **BENCH-14** Display a clear fallback for offline, unsupported, or missing runtime data.
- [ ] **BENCH-15** Toggle debug mode and choose a debug level on supported running instances.
- [ ] **BENCH-16** Display timestamps in the selected timezone.

[Workbench sections](../../lib_old/jido_studio/live/agents_live/contracts.ex) · [Routes](../../lib_old/jido_studio/live/agents_live/routes.ex) · [Detail rendering](../../lib_old/jido_studio/live/agents_live/render/instance_view.ex) · [Presenter resolver](../../lib_old/jido_studio/presenter_resolver.ex) · [Handler](../../lib_old/jido_studio/live/agents_live.ex)

## Guarded signal and action run

- [ ] **RUN-01** List consumed signal routes and show route origins and target actions. Let the operator expand the advanced route list.
- [ ] **RUN-02** List available actions and retrieve input schemas when supported.
- [ ] **RUN-03** Build field inputs from the schema and let the operator use raw JSON when useful.
- [ ] **RUN-04** Apply suggested starter inputs and show the selected signal, action, and target instance.
- [ ] **RUN-05** Validate the payload and show an actionable error before dispatch.
- [ ] **RUN-06** Require an explicit arm step. Reset it when the target, dispatch mode, or payload changes.
- [ ] **RUN-07** Dispatch synchronously with a timeout or asynchronously with a separate queued result.
- [ ] **RUN-08** Show the result and, when available, the trace and before-and-after state.
- [ ] **RUN-09** Keep bounded per-instance run history and allow the operator to clear it.
- [ ] **RUN-10** Give the operator a link to inspect state changes or diagnose a result.

[Signal routes](../../lib_old/jido_studio/agents/signal_catalog.ex) · [Action schemas](../../lib_old/jido_studio/agents/action_catalog.ex) · [Runner](../../lib_old/jido_studio/agents/runner.ex) · [Workbench handler tests](../../test_old/jido_studio/agents_live_test.exs)

## Chat

- [ ] **CHAT-01** Detect chat support and switch to Interact when chat is unavailable.
- [ ] **CHAT-02** Offer a thread rail with new-thread and existing-thread selection.
- [ ] **CHAT-03** Save draft text and restore the selected thread for the instance.
- [ ] **CHAT-04** Show pending, streamed, completed, and failed assistant replies.
- [ ] **CHAT-05** Render assistant Markdown and expandable tool events.
- [ ] **CHAT-06** Report missing credentials, unsupported calls, timeouts, and provider errors.
- [ ] **CHAT-07** Clear workspace state with an explicit operator action.
- [ ] **CHAT-08** Display the agent's effective provider and model. v2 also offered provider and model selectors marked `UI-only`. Decide whether v3 needs controls that can change the effective values.

[Runtime adapter](../../lib_old/jido_studio/chat/runtime.ex) · [Chat session](../../lib_old/jido_studio/chat/session.ex) · [Chat UI](../../lib_old/jido_studio/components/chat_components.ex) · [Chat workspace tests](../../test_old/jido_studio/agents_live_test.exs)

## Catalog

- [ ] **CATALOG-01** Browse Agents, Actions, Sensors, and Plugins.
- [ ] **CATALOG-02** Search entries and preserve selected detail and search state in links.
- [ ] **CATALOG-03** Show entry metadata and available schemas.
- [ ] **CATALOG-04** Explain missing catalog data or a scope warning.
- [ ] **CATALOG-05** Redirect the historical `/registry` route to `/catalog` while preserving query parameters, if compatibility is approved.

[Catalog](../../lib_old/jido_studio/live/catalog_live.ex) · [Route tests](../../test_old/jido_studio/ia_routes_test.exs)

## Activity and incidents

- [ ] **ACT-01** Show counts and status summaries for observed operational activity.
- [ ] **ACT-02** Combine signals, actions, workflows, and traces in an operational timeline.
- [ ] **ACT-03** Group related evidence using incident and request identifiers when they exist.
- [ ] **ACT-04** Link an incident or event to its trace and related tool views while retaining scope.

[Activity](../../lib_old/jido_studio/live/activity_live.ex) · [Incidents](../../lib_old/jido_studio/observability/incidents.ex) · [Correlation](../../lib_old/jido_studio/observability/correlation.ex)

## Signal monitor

- [ ] **SIGNAL-01** Show a live signal stream with type, target agent, status, and timing.
- [ ] **SIGNAL-02** Filter by type, agent, project, user, status, range, text, and errors.
- [ ] **SIGNAL-03** Select a signal and inspect available metadata and correlation.
- [ ] **SIGNAL-04** Link to related traces, incidents, actions, or workflows when available.

[Signals page](../../lib_old/jido_studio/live/signals_live.ex) · [Signal query](../../lib_old/jido_studio/observability/signals.ex)

## Action execution

- [ ] **ACTION-01** List observed action executions and their status and timing.
- [ ] **ACTION-02** Filter by action, agent module, agent ID, status, project, user, text, and errors.
- [ ] **ACTION-03** Show a detail route with execution samples and failure samples.
- [ ] **ACTION-04** Open related trace, incident, and agent evidence from an action.

[Actions page](../../lib_old/jido_studio/live/actions_live.ex) · [Action query](../../lib_old/jido_studio/observability/actions.ex)

## Workflow runs

- [ ] **FLOW-01** List workflow runs derived from telemetry.
- [ ] **FLOW-02** Filter by workflow, agent, status, time range, project, user, text, errors, and stalls.
- [ ] **FLOW-03** Show the selected run's status, stalled indicator, and event timeline.
- [ ] **FLOW-04** Link to the trace, incident, agent-related evidence, and workflow-related signals.

[Workflows page](../../lib_old/jido_studio/live/workflows_live.ex) · [Workflow query](../../lib_old/jido_studio/observability/workflows.ex)

## Traces

- [ ] **TRACE-01** List trace runs with agent, status, duration, and event or span counts.
- [ ] **TRACE-02** Filter by agent, status, quick or custom time range, incident, request, project, user, text, and entity type.
- [ ] **TRACE-03** Toggle internal spans and streaming-related results.
- [ ] **TRACE-04** Open trace detail and keep supported filters in the link.
- [ ] **TRACE-05** Show correlation identifiers and incident context.
- [ ] **TRACE-06** Show a span timeline, event list, error payload, and duration summaries by entity.
- [ ] **TRACE-07** Run enabled trace eval rules and show their saved results and history.
- [ ] **TRACE-08** Explain missing traces, spans, or evidence explicitly.

[Trace views](../../lib_old/jido_studio/live/traces_live.ex) · [Trace query](../../lib_old/jido_studio/tracing.ex) · [Evaluation rules](../../lib_old/jido_studio/evals.ex) · [Trace filter tests](../../test_old/jido_studio/trace_filter_test.exs)

## Diagnostics

- [ ] **DIAG-01** Show cluster runtime status and node snapshots.
- [ ] **DIAG-02** Link to traces, actions, workflows, signals, and persisted threads.
- [ ] **DIAG-03** Open the advanced timeline and require one concrete node in the v2 scope model.
- [ ] **DIAG-04** Select a trace and filter lanes or span types. Hide internal spans or focus on the critical path.
- [ ] **DIAG-05** Draw spans as duration bars with relative positions and lane counts.
- [ ] **DIAG-06** Select a span and show identifiers, duration, status, and related views.
- [ ] **DIAG-07** Show when timings are absent or the span cap limits the result.

[Diagnostics](../../lib_old/jido_studio/live/diagnostics_live.ex) · [Waterfall components](../../lib_old/jido_studio/diagnostics/components.ex) · [Timeline model](../../lib_old/jido_studio/diagnostics/timeline.ex)

## Persisted threads

- [ ] **THREAD-01** List persisted threads and workspace checkpoints.
- [ ] **THREAD-02** Search threads and keep the search in detail and back links.
- [ ] **THREAD-03** Inspect checkpoint and entry metadata and recorded message or event content.
- [ ] **THREAD-04** Open linked traces from entries that carry trace IDs.
- [ ] **THREAD-05** Show distinct empty and unavailable states.

[Thread views](../../lib_old/jido_studio/live/threads_live.ex) · [Thread query](../../lib_old/jido_studio/threads.ex)

## Delegation, tasks, and tools

- [ ] **DELEG-01** List sub-agents and expand their details.
- [ ] **DELEG-02** Show sub-agent configuration, messages, middleware, tools, and events where available.
- [ ] **DELEG-03** Build parent-child delegation relationships from captured trace records.
- [ ] **DELEG-04** List task lifecycle records and their trace references.
- [ ] **DELEG-05** List tool runs and middleware snapshots with related event evidence.

[Delegation query](../../lib_old/jido_studio/delegation.ex) · [Configure panels](../../lib_old/jido_studio/live/agents_live/render/workbench_panels/configure.ex) · [Delegation tests](../../test_old/jido_studio/delegation_test.exs)

## Runtime and node scope

- [ ] **SCOPE-01** Show a summary for the selected runtime and a selector when multiple runtimes are configured.
- [ ] **SCOPE-02** Expand advanced scope to choose all nodes or a named node.
- [ ] **SCOPE-03** Carry runtime and node scope in links. Show a warning when a requested scope falls back.
- [ ] **SCOPE-04** Collect results across nodes and handle unavailable nodes without discarding successful responses.
- [ ] **SCOPE-05** Subscribe to scoped list and instance updates with fallback polling.
- [ ] **SCOPE-06** Track presence and viewer counts where configured.
- [ ] **SCOPE-07** Carry supported project and user context into scoped live updates and observations.

[Runtime scope](../../lib_old/jido_studio/runtime_scope.ex) · [Cluster collection](../../lib_old/jido_studio/cluster/collect.ex) · [Live Ops](../../lib_old/jido_studio/live_ops.ex)

## Capture, storage, and supervision

- [ ] **STORE-01** Start observation services with Studio or let the host supervise them.
- [ ] **STORE-02** Attach observation handlers to a configurable event catalog.
- [ ] **STORE-03** Keep a bounded, filterable in-memory buffer for recent telemetry.
- [ ] **STORE-04** Materialize traces, spans, actions, workflow runs, incidents, and delegation evidence from captured events.
- [ ] **STORE-05** Support local ETS storage for operational records.
- [ ] **STORE-06** Support optional Ecto/Postgres operational records with a host-run migration if approved.
- [ ] **STORE-07** Store thread entries and workspace checkpoints using file storage, ETS, or an inherited host storage adapter.
- [ ] **STORE-08** Preserve thread entry order, detect write conflicts, sanitize stored terms, and apply configured retention.

[Runtime](../../lib_old/jido_studio/runtime.ex) · [Buffer and catalog](../../lib_old/jido_studio/trace_buffer.ex) · [Ingestor](../../lib_old/jido_studio/ingestor.ex) · [Storage](../../lib_old/jido_studio/persistence.ex) · [Thread storage](../../lib_old/jido_studio/threads/storage.ex)

## Optional integrations

- [ ] **EXT-01** Allow host modules to add active Studio routes and navigation sections.
- [ ] **EXT-02** Show Messaging Rooms through the optional v2 `jido_messaging` extension or its configured room provider.
- [ ] **EXT-03** Show empty, unavailable, and provider error states. Refresh on an interval and on request.

[Extension registry](../../lib_old/jido_studio/extensions.ex) · [Room provider](../../lib_old/jido_studio/messaging.ex) · [Rooms view](../../lib_old/jido_studio/live/messaging_rooms_live.ex)

## Product measurements

- [ ] **METRIC-01** Emit setup, profile, and scope selection measurements.
- [ ] **METRIC-02** Measure first successful interaction, dispatch success or failure, and use of the state-change view.
- [ ] **METRIC-03** Measure triage links and the path from a warning to root-cause evidence.
- [ ] **METRIC-04** Measure tour start, progress, completion, and dismissal.
- [ ] **METRIC-05** Provide a repeatable time-to-triage benchmark.

[Product metrics](../../lib_old/jido_studio/product_metrics.ex) · [Telemetry](../../lib_old/jido_studio/telemetry.ex) · [Benchmark](../../lib_old/mix/tasks/jido_studio.benchmark.triage.ex)

## Separate v3 work

The optional Jizoku workflow inspection in
[Studio issue #115](https://github.com/agentjido/jido_studio/issues/115)
adds a source of durable workflow state and history. Review it through D10
in the decision roadmap. The v2 workflow checklist above describes telemetry
views from the archived code.
