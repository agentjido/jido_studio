# AGENTS.md - Jido Studio

## Project Overview

Jido Studio is an embeddable, standalone LiveView dashboard for managing and debugging Jido AI agents. It follows the Oban Web architectural pattern: a self-contained Hex package that mounts into a Phoenix router with a single macro, inlining all CSS/JS assets at compile time.

## Common Commands

```bash
mix test                           # Run tests
mix compile --warnings-as-errors   # Compile with strict warnings
mix format                         # Format code
mix credo --min-priority higher    # Lint code
mix docs                           # Generate documentation
```

## Project Structure

```
jido_studio/
├── lib/
│   ├── jido_studio.ex              # Main module, version
│   └── jido_studio/
│       ├── application.ex          # Supervision tree (TraceBuffer)
│       ├── router.ex               # Router macro (jido_studio/2)
│       ├── resolver.ex             # Access control behaviour
│       ├── hooks.ex                # LiveView on_mount hooks
│       ├── layouts.ex              # Root layout with sidebar nav
│       ├── assets.ex               # Compile-time asset inlining
│       ├── trace_buffer.ex         # ETS ring buffer for telemetry
│       └── live/                   # LiveView pages
│           ├── agents_live.ex      # Agent browser + chat
│           ├── actions_live.ex     # Action catalog
│           ├── workflows_live.ex   # Workflow visualizer
│           ├── signals_live.ex     # Signal monitor
│           ├── traces_live.ex      # Telemetry trace viewer
│           └── settings_live.ex    # Runtime settings
├── priv/static/                    # Compiled CSS/JS (inlined at build)
├── test/
└── config/
```

## Architecture

### Embedding Pattern (Oban Web style)

1. Host app imports `JidoStudio.Router` in their router
2. `jido_studio "/studio"` macro expands into a `live_session` with routes
3. Routes point to LiveViews inside this package
4. Root layout (`JidoStudio.Layouts.studio/1`) provides shell + sidebar
5. CSS/JS inlined at compile time via `JidoStudio.Assets` — no asset pipeline

### Key Modules

| Module | Purpose |
|--------|---------|
| `JidoStudio.Router` | Router macro for mounting |
| `JidoStudio.Resolver` | Access control behaviour |
| `JidoStudio.Layouts` | Root layout with sidebar navigation |
| `JidoStudio.Assets` | Compile-time CSS/JS inlining |
| `JidoStudio.Hooks` | LiveView on_mount setup |
| `JidoStudio.TraceBuffer` | ETS telemetry ring buffer |

## Code Style

- Follow standard Elixir conventions
- Use `@moduledoc` for public modules
- Use `@doc` and `@spec` for public functions
- Handle missing Jido infrastructure gracefully
- Use HEEx templates for all rendering

## Git Commit Guidelines

- Use conventional commit format: `type(scope): description`
- Do not modify `CHANGELOG.md`; release notes are generated from Git history during release, so keep changes focused on proper Conventional Commits.
- Never add "ampcode" as a contributor
