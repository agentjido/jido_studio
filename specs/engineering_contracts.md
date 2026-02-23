# Engineering Contracts Spec

## Purpose
Define implementation-level contracts needed to realize the product specs while preserving backward compatibility.

## Backward Compatibility
1. Existing single-runtime installs must continue to work unchanged.
2. Existing `node` query behavior remains valid.
3. Existing deep routes remain available.
4. Existing panel query parsing remains tolerant of legacy values.

## Proposed Internal Additions
### Runtime Scope
- New internal module:
  - `JidoStudio.Runtime.Scope`
- Responsibilities:
  - runtime option discovery from config/session
  - runtime key normalization
  - runtime fallback/warning model
  - URL query encode/decode for `runtime`

### Hook Extension
- Extend `JidoStudio.Hooks` default mount:
  - parse `runtime` and `node` from params/query
  - assign selected runtime module + warning
  - keep existing cluster scope assignments

### URL Helpers
- Ensure link/path helpers include:
  - `runtime`
  - `node`
- Centralize query merge logic to avoid malformed URLs.

## Config Surface (Proposed)
- Keep:
  - `config :jido_studio, jido_instance: MyApp.Jido`
- Add optional:
  - `config :jido_studio, :jido_instances, [%{key:, module:, label:}]`
  - `config :jido_studio, :default_jido_instance_key, "<key>"`

If optional multi-runtime config is absent, derive one option from `:jido_instance`.

## Data Provider Contract
All provider entry points consuming runtime context should accept optional scope opts:
- `jido_instance: module`
- `scope: :all | {:node, node()}`

This is additive and should not break existing call sites.

## UI State Contract
Required shell assigns:
- `:jido_runtime_options`
- `:jido_runtime_key`
- `:runtime_scope_warning`
- existing cluster assigns (`:cluster_scope`, `:cluster_node_param`, `:cluster_scope_warning`)

## Testing Contract
Add/extend tests for:
1. runtime query parsing and fallback
2. scope propagation across nav links
3. multi-runtime selection affecting data source behavior
4. advanced scope UI visibility rules
5. compatibility with existing single-runtime setup

## Observability and Metrics
Instrument setup and scope events:
- runtime selected
- node selected
- setup step evaluated
- onboarding profile selected

These events support product metrics from first principles.

Instrument phase-5 product metrics:
- interaction started/completed
- first interaction succeeded
- warning opened
- root cause opened
- incident next-step links evaluated
