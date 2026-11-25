# Jido Studio v2 feature inventory

The [v3 decision roadmap](jido-studio-v3.csv) uses this inventory to decide
which operator workflows to restore and what evidence each one needs.
Use the [feature checklist](jido-studio-v2-features.md) to track individual
additions and the [visual reference](../archive/jido-studio-v2/README.md)
to compare the designs.

## Review basis

- **v2 evidence.** Archived source in `lib_old/`, archived tests in
  `test_old/`, and the assets and migration at base commit `b5aea45`.
  The archived tests show expected behavior. This review did not run them.
- **v3 baseline.** [The new router](../../lib/jido_studio/router.ex) mounts
  an Overview page and accepts host LiveView hooks. The
  [playground](../../studio_playground/README.md) starts Jido
  `3.0.0-beta.3`, as shown in its [lockfile](../../studio_playground/mix.lock).
- **Decision authority.** Mike Hostetler has already chosen a fresh v3
  implementation with a similar shell and a local playground. The priorities
  below are proposals. The CSV records the open decisions and their evidence.

## Features in the v2 code

Routes are relative to the Studio mount path. The decision IDs point to the
CSV. Some groups feed more than one decision.

| Area | What v2 provided | v3 decisions and source |
| --- | --- | --- |
| Mount and shell | A Phoenix macro, mount-prefix links, host `on_mount` hooks, inline Studio assets, a host script option, a collapsible sidebar, and a saved color theme. The router also accepted resolver, socket path, and CSP nonce options. See the access gap below. | D4, D6, D11. [Router](../../lib_old/jido_studio/router.ex), [layout](../../lib_old/jido_studio/layouts.ex), [hooks](../../lib_old/jido_studio/hooks.ex). |
| Home and Activity | Fleet health, attention items, recent failures and activity, and links to the agent and diagnostic views. Activity assembled signals, actions, workflow runs, and traces into an operational timeline. | D1, D3, D5. [Home](../../lib_old/jido_studio/live/home_live.ex), [Activity](../../lib_old/jido_studio/live/activity_live.ex), [incident query](../../lib_old/jido_studio/observability/incidents.ex). |
| Setup, Settings, and About | Home and Settings checked runtime connectivity, storage, real-time updates, chat credentials, and readiness for a smoke interaction. Settings let users rerun checks and select a configuration profile. About showed version, runtime information, and resource links. | D1, D11. [Setup](../../lib_old/jido_studio/setup.ex), [profiles](../../lib_old/jido_studio/setup/profiles.ex), [Settings](../../lib_old/jido_studio/live/settings_live.ex), [About](../../lib_old/jido_studio/live/about_live.ex). |
| Guide and starter agent | Guided first-run and triage flows, coachmarks with saved progress and resume or replay, and a bundled deterministic starter with sample operations. | D1, D7, D11. [Guide](../../lib_old/jido_studio/live/guide_live.ex), [tour client](../../priv/static/jido_studio.js), [starter](../../lib_old/jido_studio/beginner_agent.ex), [sample operations](../../lib_old/jido_studio/agents/starter_operations.ex). |
| Agent inventory | Discovered agent modules and running instances in one surface. Search and sort, internal and product tags, source app, status, uptime, last activity, follow and auto-follow, viewer counts, and a start form. | D2, D4, D7, D9. [Registry](../../lib_old/jido_studio/agent_registry.ex), [index view](../../lib_old/jido_studio/live/agents_live/render/index_view.ex), [LiveView handlers](../../lib_old/jido_studio/live/agents_live.ex), [inventory tests](../../test_old/jido_studio/agents_live_test.exs). |
| Agent workbench | Shareable instance routes, basic and advanced modes, and Play, Observe, and Configure sections. Panels showed instance details, messages, raw events, strategy TODOs, thread context, and thread events. Presenters adapted the view to the agent or strategy. | D2, D6, D8, D12. [Workbench contract](../../lib_old/jido_studio/live/agents_live/contracts.ex), [presenter contract](../../lib_old/jido_studio/agent_presenter.ex), [route tests](../../test_old/jido_studio/agents_instance_routes_test.exs). |
| Catalog | Search and details for discovered agents, actions, sensors, and plugins. The old `/registry` route redirected to `/catalog` and preserved query parameters. Catalog entries described available code, while the running inventory showed resident instances. | D2, D6. [Catalog](../../lib_old/jido_studio/live/catalog_live.ex), [redirect](../../lib_old/jido_studio/live/registry_live.ex), [route tests](../../test_old/jido_studio/ia_routes_test.exs). |
| Signal and action runner | Inspected signal routes and action schemas. Offered form and JSON inputs, an explicit arm step that reset on payload changes, sync and async dispatch, per-instance run history, and state changes for the sync path. | D4, D7. [Signal catalog](../../lib_old/jido_studio/agents/signal_catalog.ex), [action catalog](../../lib_old/jido_studio/agents/action_catalog.ex), [runner](../../lib_old/jido_studio/agents/runner.ex), [LiveView tests](../../test_old/jido_studio/agents_live_test.exs). |
| Chat and Threads | Chat capability detection, streaming replies and tool blocks, credential and timeout states, workspace drafts and saved conversations, and a searchable thread explorer with links to traces. Thread storage could use file, ETS, or the host's Jido storage. | D4, D8, D11. [Chat runtime](../../lib_old/jido_studio/chat/runtime.ex), [chat session](../../lib_old/jido_studio/chat/session.ex), [thread explorer](../../lib_old/jido_studio/live/threads_live.ex), [storage](../../lib_old/jido_studio/threads/storage.ex), [thread tests](../../test_old/jido_studio/threads_storage_test.exs). |
| Signals, Actions, and Workflows | Filtered lists of observed signals, action executions, and workflow runs. Action and workflow details linked to related traces and evidence. The workbench's action discovery and the execution history used different data. | D3, D5, D10. [Signals](../../lib_old/jido_studio/live/signals_live.ex), [Actions](../../lib_old/jido_studio/live/actions_live.ex), [Workflows](../../lib_old/jido_studio/live/workflows_live.ex), [query tests](../../test_old/jido_studio/observability_queries_test.exs). |
| Traces and Diagnostics | Trace filtering, incident context, event and error details, internal-span filtering, duration summaries, and rule-based eval history. Diagnostics showed node health and a single-node span waterfall with critical-path controls and links to related views. | D3, D5, D9, D12. [Traces](../../lib_old/jido_studio/live/traces_live.ex), [Diagnostics](../../lib_old/jido_studio/live/diagnostics_live.ex), [timeline tests](../../test_old/jido_studio/diagnostics_live_test.exs), [eval tests](../../test_old/jido_studio/evals_test.exs). |
| Trace collection and storage | An in-memory telemetry buffer and an ingestor that built trace, span, action, workflow, delegation, and incident records. Operational storage used ETS or optional Ecto/Postgres. The host could supervise the Studio runtime. | D3, D5, D11. [Buffer](../../lib_old/jido_studio/trace_buffer.ex), [ingestor](../../lib_old/jido_studio/ingestor.ex), [runtime](../../lib_old/jido_studio/runtime.ex), [storage](../../lib_old/jido_studio/persistence.ex), [Ecto migration](../../priv/ecto/migrations/20260215000000_create_jido_studio_persistence_tables.exs). |
| Delegation, tasks, and tools | Sub-agent details, delegation graphs, task lifecycle, tool runs, middleware snapshots, and trace links from captured events. | D3, D12. [Delegation](../../lib_old/jido_studio/delegation.ex), [workbench contract](../../lib_old/jido_studio/live/agents_live/contracts.ex), [delegation tests](../../test_old/jido_studio/delegation_test.exs). |
| Runtime and node scope | Selectors for runtime and node, scope in links, RPC collection across nodes, scoped PubSub subscriptions, polling fallback, and viewer presence. | D2, D3, D4, D9. [Runtime scope](../../lib_old/jido_studio/runtime_scope.ex), [RPC collection](../../lib_old/jido_studio/cluster/collect.ex), [Live Ops](../../lib_old/jido_studio/live_ops.ex), [scope tests](../../test_old/jido_studio/sidebar_scope_test.exs). |
| Optional extensions | Host extensions could provide routes and navigation. A built-in adapter could show rooms from `jido_messaging` or a configured provider. | D12. [Extensions](../../lib_old/jido_studio/extensions.ex), [rooms view](../../lib_old/jido_studio/live/messaging_rooms_live.ex), [extension tests](../../test_old/jido_studio/extensions_test.exs). |
| Product metrics | Telemetry for setup, first successful interaction, triage, and guide use. A Mix task measured time to triage in a benchmark. | D1, D11. [Metrics](../../lib_old/jido_studio/product_metrics.ex), [benchmark](../../lib_old/mix/tasks/jido_studio.benchmark.triage.ex), [metrics goals](../metrics.md). |

## Evidence that changes the v3 order

- **Access enforcement needs a new contract.** The v2 router and hooks
  passed the resolver to LiveView, and the resolver defined `:all`,
  `:read_only`, and forbidden access. The archived application code
  contains no calls to its access callbacks. The v3 shell accepts host
  hooks. Decide how the host grants read, dispatch, and sensitive-field
  permissions before Studio exposes runtime data. [Resolver](../../lib_old/jido_studio/resolver.ex), [Session hooks](../../lib_old/jido_studio/hooks.ex), [Safe access job](../jtbd/02-mount-with-safe-access.md).
- **Catalog entries, agent addresses, and activations are different.** In the
  pinned v3 source, `Jido.Catalog.Discovery` returns catalog entries.
  `Jido.list_agents/2` returns resident workers for the selected partition.
  `Jido.status/3` reads semantic status at an address, and
  `Jido.AgentServer.snapshot/2` reads committed state from a resident worker.
  The stable address includes namespace, partition, and ID. Verify what the UI
  can show for a passivated or unavailable agent before choosing a URL or a
  fleet count. Source paths in the installed Jido package are
  `lib/jido/catalog/discovery.ex`, `lib/jido/agent/address.ex`,
  `lib/jido.ex`, and `lib/jido/agent_server.ex`.
- **Trace correlation has a scope gap in the pinned beta.** The v3 telemetry
  reference lists turn, commit, and effects events. Turn metadata includes
  agent, signal, turn, and trace identifiers. It has no instance, namespace,
  or partition fields. The trace context guide defines W3C trace IDs and parent
  span IDs on signals. Capture success and failure in the playground and
  verify how observations can be attributed to the correct address before
  offering partition-scoped history. Source paths in the installed package are
  `guides/reference/telemetry-event-reference.md`,
  `guides/data/trace-context.md`, and `lib/jido/telemetry/agent_server.ex`.
- **Workflow history has a separate owner.** The v2 Workflows page read
  telemetry records. Studio issue #115 tracks an optional Jizoku source for
  durable run state, history, recovery, and continuations. This is separate
  v3 work with its own acceptance conditions. [Studio issue #115](https://github.com/agentjido/jido_studio/issues/115).

## Proposed first review

Start with a host-approved, read-only path in one playground runtime.
Show a catalog entry and a resident agent. Open one failed turn and show the
stage, commit outcome, and available trace links. Use a deterministic agent
fixture so the result can be checked without provider credentials. Agree on
the treatment of missing scope or missing observations before testing a
second runtime or a partitioned host.

Decide the first milestone (D1), check the runtime read contracts (D2), and
capture v3 trace evidence (D3) first. These three decisions can advance
independently. Their results inform the access and retention decisions.
Guarded execution, chat, cluster views, and workflow integrations each
need their own evidence and approval before they join implementation scope.
