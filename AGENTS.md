# AGENTS.md - Jido Studio

## Project overview

Jido Studio is an embeddable Phoenix LiveView dashboard. On `release/v3`,
it provides a mount macro, a layout, and an Overview page. The host provides
the root layout and LiveView client. The local integration target is
`studio_playground/`, which runs Jido v3.

Use `lib/` and `test/` for the current Studio code. Use `lib_old/` and
`test_old/` as references for the previous implementation. Mix does not
compile or run the archived files.

## Common commands

- `mix test`
- `mix compile --warnings-as-errors`
- `mix format --check-formatted`
- `mix credo --min-priority higher`
- `mix docs`
- Run `mix precommit` from `studio_playground/` to check the mounted app.

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
