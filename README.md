# Jido Studio

Embeddable agent studio for Phoenix applications — a standalone LiveView dashboard for managing and debugging [Jido](https://github.com/agentjido/jido) AI agents.

Inspired by [Mastra Studio](https://mastra.ai/docs/getting-started/studio) and modeled after [Oban Web](https://hex.pm/packages/oban_web), Jido Studio is a self-contained Hex package that mounts directly into your Phoenix router with zero asset pipeline integration.

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

Default observability persistence is ETS and needs no extra setup:

```elixir
config :jido_studio, :persistence,
  adapter: JidoStudio.Persistence.ETS,
  opts: []
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

- `Agents` (live runtime and debug toggle)
- `Registry` (discovery catalog)
- `Threads` (persisted thread/memory explorer)
- `Traces` (trace list + detail timeline)

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

- **Agents** — Browse, inspect, and chat with running agents
- **Registry** — Discovery-powered catalog of agents/actions/sensors/plugins
- **Threads** — Inspect persisted thread/memory entries
- **Traces** — Trace list + span timeline explorer
- **Settings** — Configure runtime behavior

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
