# Jido Studio Spec Suite

## Goal
This folder is the source of truth for product and UX direction. It translates first principles into concrete route, page, interaction, and delivery contracts.

## How to Use
1. Start with `docs/first_principles.md`.
2. Use `specs/view_route_hierarchy.md` for navigation and canonical route decisions.
3. Use page and feature specs below to implement or review changes.
4. Reject any feature or UI change that does not map to a documented job-to-be-done.

## Spec Index
- `specs/view_route_hierarchy.md`
Canonical route tree, IA, and navigation behavior.

- `specs/scope_model.md`
Runtime scope model (`runtime` + `node`), including default vs advanced controls.

- `specs/onboarding_setup_spec.md`
First-run setup assistant, configuration checks, and guided completion flow.

- `specs/page_contracts.md`
Top-level page purpose, required sections, and minimum interaction contracts.

- `specs/agents_instance_manager_spec.md`
Instance-level Play/Observe/Configure behavior and panel contracts.

- `specs/diagnostics_timeline_spec.md`
Advanced OTEL-style timeline (waterfall) design and performance guardrails.

- `specs/config_profiles_spec.md`
Recommended configuration profiles and progressive setup guidance.

- `specs/roadmap_spec.md`
Phased implementation plan with acceptance gates and regression requirements.

## Decision Discipline
- Prefer canonical routes and stable URL semantics.
- Keep primary UX operator-friendly; place deep technical controls behind advanced paths.
- Preserve explicit unknown/unavailable states; never hide missing data with blank UI.
