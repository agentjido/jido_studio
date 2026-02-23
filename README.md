# Jido Studio

Embeddable agent studio for Phoenix applications — a standalone LiveView dashboard for managing and debugging [Jido](https://github.com/agentjido/jido) AI agents.

Inspired by [Mastra Studio](https://mastra.ai/docs/getting-started/studio) and modeled after [Oban Web](https://hex.pm/packages/oban_web), Jido Studio is a self-contained Hex package that mounts directly into your Phoenix router with zero asset pipeline integration.

## Product Direction

Use the first-principles product doc as the reference for roadmap and UX decisions:

- `docs/first_principles.md`

## Installation

Add `jido_studio` to your dependencies:

```elixir
def deps do
  [
    {:jido_studio, "~> 0.1.0"}
  ]
end
```

## Quick Start

Mount the studio in your Phoenix router:

```elixir
# lib/my_app_web/router.ex
import JidoStudio.Router

scope "/" do
  pipe_through [:browser, :require_authenticated_user]
  jido_studio "/studio"
end
```

Start your server and visit `/studio`.

## Full Host Playground App

For a full Phoenix host-app setup (router/session/endpoint parity), use:

```bash
cd dev/studio_playground
mix deps.get
mix phx.server
```

Then open `http://localhost:4702/studio`.

Notes:

- Host app depends on this package via local path (`{:jido_studio, path: "../.."}`)
- A local Jido instance (`StudioPlayground.Jido`) is started in supervision
- Demo agents are auto-seeded at boot for immediate Studio interaction, including non-chat signal-first examples

## Optional Extensions

Studio supports optional package-specific admin pages through extensions.
Built-in extension routes are only compiled when their backing package is available.

Current built-in extension:

- `jido_messaging` -> `Messaging / Rooms` page

Optional extension modules can also be registered from the host app:

```elixir
config :jido_studio,
  extension_modules: [MyAppWeb.Studio.Extensions.Custom]
```

For `jido_messaging` room listing, you can provide an explicit provider if your API differs:

```elixir
config :jido_studio,
  messaging_room_provider: {MyApp.MessagingAdmin, :list_rooms}
```

## Setup

Use this sequence for a clean first-time setup.

### 1. Install the dependency

```elixir
def deps do
  [
    {:jido_studio, "~> 0.1.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

### 2. Configure Studio

Set your Jido supervisor module so Studio can show running instances (without this, Studio still shows discovered modules only):

```elixir
# config/config.exs
config :jido_studio,
  jido_instance: MyApp.Jido
```

Optional override for multi-runtime installs:

```elixir
config :jido_studio, :jido_instances, [
  %{key: "primary", module: MyApp.Jido, label: "Primary"},
  %{key: "batch", module: MyApp.BatchJido, label: "Batch Runtime"}
]
```

When `:jido_instances` is present, Studio shows a runtime selector in the sidebar.
When it is absent, Studio derives a single runtime from `:jido_instance` and keeps the UI simplified.

Default observability persistence is ETS and needs no extra setup:

```elixir
config :jido_studio, :persistence,
  adapter: JidoStudio.Persistence.ETS,
  opts: []
```

Optional next-wave debug/observability defaults:

```elixir
config :jido_studio,
  live_ops: [
    enabled: true,
    auto_follow_default: true,
    scope_keys: [:project_id, :user_id],
    event_stream_limit: 100,
    agent_list_poll_ms: 2_000,
    viewer_tracking: true
  ],
  delegation: [
    enabled: true
  ],
  tracing: [
    hide_internal_default: true,
    chunk_span_sampling: 1.0,
    max_span_rows: 5_000
  ],
  evals: [
    enabled: true,
    rule_sets: [:default]
  ],
  agent_interactions: [
    enabled: true,
    default_tab: :auto,
    runner_timeout_ms: 5_000,
    runner_history_limit: 20,
    internal_agent_tags: ["internal"]
  ]
```

Studio now ships a built-in Presence default (`JidoStudio.Presence`) so viewer tracking works out-of-the-box.
If your host app already has its own Presence module, you can override it:

```elixir
config :jido_studio,
  pubsub: MyApp.PubSub,
  live_ops: [
    enabled: true,
    viewer_tracking: true,
    presence_module: MyApp.Presence
  ]
```

### Setup Assistant and Profiles

After mount, Studio surfaces a Setup Assistant on `Home` with a re-entry card in `Settings`.
Checks cover:

- runtime connectivity/reachability
- persistence durability mode
- realtime event-driven vs polling fallback
- optional chat provider key presence
- smoke-path readiness

Profiles are guidance-only presets shown in-app:

- `Local Dev Fast Start`
- `Chat Demo Showcase`
- `Team Durable Ops`

`Apply profile snippet` means show/copy snippet text with "What changes?" and rollback notes.
Studio does not mutate host config files.

### Beginner Agent and Discovery Model

Studio includes a bundled deterministic starter agent by default:

```elixir
config :jido_studio, :beginner_agent,
  enabled: true
```

Starter details:

- module: `JidoStudio.BeginnerAgent`
- purpose: first-run onboarding without provider keys or LLM dependencies
- startup behavior: explicit only; opening starter links can pre-open Start modal (`start=1`), but users still confirm `Start Instance` manually

Set `enabled: false` to hide the beginner agent from discovery lists when it is not running.
If a beginner instance is already running, Studio keeps it visible so operators can inspect or stop it safely.

Discovery glossary in product terms:

- `Discovered modules`: compiled agent modules visible in the selected runtime
- `Running instances`: currently started agent processes
- `Active instances`: running instances after current scope/filter application

### Product Metrics Events

Studio emits additive telemetry events under `[:jido_studio, ...]` for Phase 5 hardening:

- `[:interaction, :started]`
- `[:interaction, :completed]`
- `[:onboarding, :first_interaction_succeeded]`
- `[:onboarding, :starter_opened]`
- `[:onboarding, :starter_start_modal_opened]`
- `[:triage, :warning_opened]`
- `[:triage, :root_cause_opened]`
- `[:incidents, :next_step_links_evaluated]`
- `[:tour, :started]`
- `[:tour, :step_viewed]`
- `[:tour, :step_completed]`
- `[:tour, :dismissed]`
- `[:tour, :completed]`

Common metadata keys include `runtime`, `node`, `path`, `source`, and `session_id`.
Event-specific metadata can include `mode`, `status`, `warning_kind`, `trace_id`, `span_id`, `linked_count`, and `total_count`.

Run the time-to-triage baseline benchmark with:

```bash
mix jido_studio.benchmark.triage
```

### 3. Mount in the Phoenix router

```elixir
# lib/my_app_web/router.ex
import JidoStudio.Router

scope "/" do
  pipe_through [:browser, :require_authenticated_user]
  jido_studio "/studio"
end
```

### 4. (Optional) Use Postgres persistence for traces/spans

Switch the persistence adapter:

```elixir
config :jido_studio, :persistence,
  adapter: JidoStudio.Persistence.Ecto,
  opts: [repo: MyApp.Repo, prefix: "public"]
```

Copy the provided migration template into your host app and run:

```bash
mix ecto.migrate
```

Template:

- `priv/ecto/migrations/20260215000000_create_jido_studio_persistence_tables.exs`

### 5. Run and verify

Start Phoenix and open `/studio`. For MVP pages, verify:

- `Home` (fleet health overview)
- `Guide` (opt-in guided tours with resume/replay)
- `Agents` (live runtime and debug toggle)
- `Catalog` (discovery catalog)
- `Activity` (operational timeline)
- `Diagnostics` (deep tooling + cluster health)
- `About` (links and product context)

## Runtime Installation Modes

### Mode 1: Auto Runtime (default)

No extra setup required. `JidoStudio.Application` starts the Studio runtime automatically.

### Mode 2: Host-supervised Runtime

Disable auto-start and supervise Studio runtime explicitly in your host app:

```elixir
# config/config.exs
config :jido_studio, auto_start_runtime: false
```

```elixir
# lib/my_app/application.ex
children = [
  MyAppWeb.Telemetry,
  {Phoenix.PubSub, name: MyApp.PubSub},
  MyAppWeb.Endpoint,
  {JidoStudio.Runtime, []}
]
```

Use this mode when you want explicit startup ordering and restart behavior in the host supervision tree.

## Thread Persistence

Studio chat/thread workspace persistence is enabled by default and uses `Jido.Storage` adapters.

```elixir
config :jido_studio,
  thread_persistence: true,
  thread_storage: {Jido.Storage.File, path: "priv/jido_studio/storage"},
  thread_storage_mode: :studio,
  thread_retention_days: 30,
  persist_strategy_context: :summary
```

### Ephemeral dev mode (not restart-safe)

```elixir
config :jido_studio,
  thread_storage: {Jido.Storage.ETS, table: :jido_studio_threads}
```

### Reuse host Jido storage

```elixir
config :jido_studio,
  thread_storage_mode: :inherit_jido_instance
```

Notes:

- ETS is fast but all workspace data is lost on BEAM restart.
- File/custom adapters are restart-safe.
- Studio persistence is for developer workflow context; application business persistence should remain in your app domain.

## Features

- **Home** — Fleet health cards, attention cues, and quick links
- **Agents** — Active instance index with follow/unfollow, auto-follow targets, filter/sort, viewer counts, uptime, and last activity
- **Catalog** — Discovery-powered catalog of agents/actions/sensors/plugins (canonical route `/catalog`; `/registry` remains compatible)
- **Activity** — Cross-surface operational timeline and plain-language summaries
- **Diagnostics** — Deep technical routing into traces/actions/workflows/signals/threads with node health summaries
- **Dual Interaction Surface** — Chat-first UX for chat-capable agents plus an `Interact` workbench for non-chat/runtime-driven interaction
- **Signal/Action Introspection** — Hybrid runtime+static consumed-signal routes, route origins, action targets, and schema extraction with safe fallbacks
- **Guarded Runner** — Explicit arm-before-run execution, sync/async dispatch, payload JSON validation, and per-instance run history persistence
- **Internal Agents by Tags** — Discovered agents are split into `Product Agents` and `Internal Agents` using `agent_interactions.internal_agent_tags`
- **Smart Scope Selector** — Runtime summary by default, optional runtime selector for multi-runtime installs, and advanced node scope (`node=all` or `node=<name>`) on demand
- **Live Ops** — Event-driven updates with polling fallback, scoped subscriptions, and viewer presence topics
- **Messages/Events/TODOs** — Runtime thread message snapshots, merged event stream with expandable raw payloads, and strategy TODO visibility
- **Delegation/Tasks** — Sub-agent detail tabs (config/messages/middleware/tools/events) and task lifecycle visibility
- **Tool/Middleware Insights** — Runtime summaries, config snapshots, and trace deep links
- **Threads** — Inspect persisted thread/memory entries
- **Traces** — Trace list, span timeline, internal-span filtering, and eval history
- **Settings** — Configure runtime behavior
- **About** — Official links, version info, and support/docs pointers

## Non-Chat Example Recipes

Studio Playground seeds non-chat examples under `dev/studio_playground/lib/studio_playground/demo_agents/non_chat_agents.ex`:

- `StudioPlayground.DemoAgents.SignalRunnerAgent` — Signal-first route execution example for introspection and guarded dispatch
- `StudioPlayground.DemoAgents.DeviceControlAgent` — Schema-driven control flows with richer action payloads

These examples are registered in `dev/studio_playground/lib/studio_playground/demo_agents.ex` so they appear in the active/discovered lists by default.

## Smart Defaults

- No new required config keys are needed for existing installs.
- Scope defaults to `All Nodes` and a single derived runtime.
- Runtime query support: `runtime=<runtime_key>` (propagated across Studio navigation).
- Node query support remains: `node=all|<node_name>`.
- Advanced node controls are collapsed by default and remembered locally in the browser.

## Observability Persistence

Trace and span observability data is stored via the Studio persistence adapter.

Default (zero setup):

```elixir
config :jido_studio, :persistence,
  adapter: JidoStudio.Persistence.ETS,
  opts: []
```

Optional Ecto/Postgres adapter:

```elixir
config :jido_studio, :persistence,
  adapter: JidoStudio.Persistence.Ecto,
  opts: [repo: MyApp.Repo, prefix: "public"]
```

Migration template:

- `priv/ecto/migrations/20260215000000_create_jido_studio_persistence_tables.exs`

## Access Control

Use a resolver module to control access:

```elixir
defmodule MyApp.StudioResolver do
  @behaviour JidoStudio.Resolver

  @impl true
  def resolve_user(conn), do: conn.assigns[:current_user]

  @impl true
  def resolve_access(%{role: :admin}), do: :all
  def resolve_access(%{role: :dev}), do: :read_only
  def resolve_access(_), do: {:forbidden, "/login"}
end

jido_studio "/studio", resolver: MyApp.StudioResolver
```

## License

Apache-2.0 — see [LICENSE](LICENSE).
