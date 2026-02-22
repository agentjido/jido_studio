# Scope Model Spec

## Purpose
Define how users choose where data and actions apply in Jido Studio.

Scope is two-dimensional:
1. Runtime scope (`runtime`): which Jido runtime instance Studio talks to.
2. Node scope (`node`): which BEAM node(s) are queried.

## Why This Exists
- Users can run multiple Jido runtime instances in one host app.
- Users may run distributed nodes and need node-aware diagnostics.
- Most users should not need node details until they ask for them.

## UX Contract
### Default (Simple Scope)
- Always resolve a runtime.
- Show runtime selector only when multiple runtime options exist.
- Do not show node selector by default.
- Show a compact badge:
  - `Runtime: <label>`

### Advanced Scope
- Expandable control group (`Advanced Scope`).
- Shows both selectors:
  - Runtime selector
  - Node selector (`All Nodes` + concrete nodes)
- Shows full badge:
  - `Runtime: <label> | Node: <value>`

## URL Contract
- Query params:
  - `runtime=<runtime_key>`
  - `node=all|<node_name>`
- Rules:
  - both params propagate through nav and patches
  - invalid `runtime` falls back to default runtime
  - invalid/unreachable `node` falls back to `all` with warning

Example:
`/studio/agents/GcvZxo6L/calculator-demo/observe?runtime=primary&node=all&panel=events`

## Runtime Selector Model
### Proposed Config
Backwards-compatible:
- existing:
  - `config :jido_studio, :jido_instance, MyApp.Jido`
- new optional:
  - `config :jido_studio, :jido_instances, [`
  - `%{key: "primary", module: MyApp.Jido, label: "Primary Runtime"},`
  - `%{key: "sandbox", module: MyApp.SandboxJido, label: "Sandbox Runtime"}`
  - `]`

If `:jido_instances` is missing, Studio derives a single option from `:jido_instance`.

### Session/Assign Contract
- `:runtime_options` -> list of available runtimes
- `:runtime_key` -> selected runtime key (query-visible in multi-runtime mode)
- `:jido_instance` -> selected runtime module (resolved)
- `:runtime_scope_warning` -> invalid/unavailable runtime warning

## Node Selector Model
Use existing cluster model with progressive disclosure:
- `node=all` default
- node selector visible only in Advanced Scope mode
- advanced scope expansion persisted locally (browser storage)
- cluster warning surfaces explicitly when node is unavailable

## Data Access Contract
Every major data read/write path accepts scope context:
- runtime module from selected runtime
- node scope from selected node

Precedence:
1. selected runtime module
2. selected node scope
3. existing per-page filters

## Behavior Contract
1. Selecting runtime triggers refresh of page data.
2. Runtime and node selections persist in URL and cross-page navigation.
3. Runtime changes reset unsafe transient state (for example pending runner arm).
4. If runtime becomes unavailable, show warning and safe fallback state.
5. Agent instance links preserve current scope.

## Error/Warning States
- Runtime missing:
  - message: `Selected runtime is unavailable. Using default runtime.`
- Runtime has no reachable agents:
  - message: `No agents discovered in selected runtime.`
- Node unavailable:
  - message: `Selected node is unavailable. Showing all nodes.`
- Multi-runtime but no selection:
  - auto-select default, no hard error.

## Non-Goals
- No per-widget scope divergence in v1.
- No runtime-specific authentication model in this phase.
- No hidden auto-switching between runtimes without URL update.

## Acceptance Criteria
1. Users can switch runtimes without leaving current page context.
2. Users can optionally narrow node scope in advanced mode.
3. All main links preserve both `runtime` and `node`.
4. Invalid scope inputs degrade gracefully with explicit warnings.
5. Existing single-runtime installs work without config changes.
