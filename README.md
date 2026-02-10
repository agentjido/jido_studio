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

## Features

- **Agents** — Browse, inspect, and chat with running agents
- **Actions** — View registered actions and their schemas
- **Workflows** — Visualize and debug workflow execution
- **Signals** — Monitor signal routing and delivery
- **Traces** — View telemetry events with trace correlation
- **Settings** — Configure runtime behavior

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
