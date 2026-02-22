# Jido Studio View and Route Hierarchy Spec

## Purpose
Define a clear, first-principles view/route hierarchy for Jido Studio so users can predict where to go, what each page is for, and what action to take next.

This spec aligns with:
- `docs/first_principles.md`
- Elevator pitch: operations cockpit for Agents
- Promise: symptom to confident next action in minutes

## IA Rules
1. Every top-level page answers one primary user question.
2. Primary navigation is for operators first; deep tools remain available for developers.
3. Canonical routes should be stable and human-readable.
4. Scope (`runtime` + `node`) must persist across all navigation.
5. Compatibility routes redirect to canonical routes.

## Global Shell Contract
- Mount prefix: `<prefix>` (typically `/studio`)
- Global query:
  - `runtime=<runtime_key>` (selected Jido runtime instance)
  - `node=all|<node_name>` (cluster scope)
- Shared shell behaviors:
  - runtime selector is global
  - cluster selector is available in Advanced Scope mode
  - sidebar order is fixed
  - page transitions preserve `runtime` and `node`

## Scope UX Model
### Default Scope (Simple)
- Show `Runtime` selector when more than one runtime is available.
- Hide node-level controls unless cluster mode is explicitly expanded.

### Advanced Scope
- Show both selectors:
  - Runtime (`runtime`)
  - Node (`node`)
- Show compact scope summary:
  - `Runtime: <runtime_key> | Node: <node>`

## Primary Navigation Hierarchy
1. `GET <prefix>/` -> `JidoStudio.HomeLive`
Primary question: Are my Agents healthy right now?

2. `GET <prefix>/agents` -> `JidoStudio.AgentsLive` (`:index`)
Primary question: Which Agents are running and what should I do next?

3. `GET <prefix>/catalog` -> `JidoStudio.CatalogLive`
Primary question: What can my Agents do?

4. `GET <prefix>/activity` -> `JidoStudio.ActivityLive`
Primary question: What happened recently?

5. `GET <prefix>/diagnostics` -> `JidoStudio.DiagnosticsLive`
Primary question: Why did this fail?

6. `GET <prefix>/settings` -> `JidoStudio.SettingsLive`
Primary question: How is Studio configured?

7. `GET <prefix>/about` -> `JidoStudio.AboutLive`
Primary question: What is Jido Studio and where do I go for help/community?

## Compatibility Routes
- `GET <prefix>/registry` -> compatibility route (`JidoStudio.RegistryLive`) that redirects to `<prefix>/catalog`, preserving query params (including `runtime` and `node`).

## Agent View Hierarchy
### Route Tree
1. `GET <prefix>/agents` -> fleet list and entry points.
2. `GET <prefix>/agents/:slug` -> module-level detail and instance launcher.
3. `GET <prefix>/agents/:slug/:instance_id` -> instance detail (canonical default section semantics).
4. `GET <prefix>/agents/:slug/:instance_id/:section` -> explicit section route.

### Canonical Sections
- `:section = play`
- `:section = observe`
- `:section = configure`

### Panel/Tab Query Contract
- Query key: `panel=<tab_id>` for workbench panel selection.
- Legacy keys may be accepted but normalized.

Section-to-panel mapping:
- `play`
  - `chat`
  - `interact`
  - `messages`
- `observe`
  - `events`
  - `todos`
  - `thread_context`
  - `thread_events`
- `configure`
  - `instance`
  - `sub_agents`
  - `tasks`
  - `tool_insights`
  - `middleware`

### Instance View Layout Contract
The instance page is a stable 3-rail manager:
1. left rail: thread/session list
2. center: section/panel content (Play/Observe/Configure)
3. right rail: persistent summary and triage shortcuts

The right summary rail must not disappear when switching sections.

## Deep Tool Routes (Secondary Navigation)
These remain first-class for technical workflows and deep links:
- `GET <prefix>/threads` -> `JidoStudio.ThreadsLive` (`:index`)
- `GET <prefix>/threads/:agent_slug/:instance_id/:thread_id` -> `JidoStudio.ThreadsLive` (`:show`)
- `GET <prefix>/traces` -> `JidoStudio.TracesLive` (`:index`)
- `GET <prefix>/traces/:trace_id` -> `JidoStudio.TracesLive` (`:show`)
- `GET <prefix>/signals` -> `JidoStudio.SignalsLive`
- `GET <prefix>/actions` -> `JidoStudio.ActionsLive` (`:index`)
- `GET <prefix>/actions/:id` -> `JidoStudio.ActionsLive` (`:show`)
- `GET <prefix>/workflows` -> `JidoStudio.WorkflowsLive` (`:index`)
- `GET <prefix>/workflows/:id` -> `JidoStudio.WorkflowsLive` (`:show`)

## Persona-to-Route Flows
### Primary: Agent Operator
1. `<prefix>/` (health and attention)
2. `<prefix>/agents`
3. `<prefix>/agents/:slug/:instance_id/play`
4. `<prefix>/agents/:slug/:instance_id/observe`
5. `<prefix>/diagnostics` (if needed)

### Secondary: Elixir Developer
1. `<prefix>/agents/:slug/:instance_id/configure`
2. `<prefix>/traces` or `<prefix>/traces/:trace_id`
3. `<prefix>/signals` / `<prefix>/actions` / `<prefix>/workflows`
4. back to instance routes for validation

### Tertiary: On-call Responder
1. `<prefix>/` (attention-needed summary)
2. `<prefix>/activity`
3. `<prefix>/diagnostics`
4. deep link to filtered traces/actions/signals
5. `<prefix>/agents/:slug/:instance_id/observe`

## Canonical Pathing Rules
1. Use `/catalog` in all UI copy and links; keep `/registry` as compatibility redirect only.
2. Use explicit instance section routes (`/play`, `/observe`, `/configure`) for sharable URLs.
3. Preserve `runtime` and `node` in every navigation path and push_patch.
4. Favor route semantics over hidden local state so links remain meaningful.

## Non-Goals
- Do not duplicate deep tooling into every page.
- Do not introduce new top-level pages without a first-principles primary question.
- Do not use route names that expose implementation detail to non-technical users.

## Acceptance Criteria
1. Any user can infer what each top-level page is for from title/subtitle alone.
2. Agent instance URLs are sharable and reopen in the same section/panel/scope.
3. Switching between Play/Observe/Configure preserves visual stability.
4. Runtime and node scope persist across all primary and deep routes.
5. `/registry` always lands on `/catalog` with equivalent query state.
