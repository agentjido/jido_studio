# Configuration Profiles Spec

## Purpose
Define recommended configuration profiles and guidance so users can succeed quickly without reading deep docs first.

## Principles
1. Start with safe defaults.
2. Encourage durability and observability progressively.
3. Treat LLM credentials as optional unless chat is a goal.
4. Always provide a fallback workflow when optional config is missing.

## Core Required Config
1. Runtime module
- `config :jido_studio, jido_instance: MyApp.Jido`

2. Router mount
- `jido_studio "/studio"`

Without these, Studio is read-only discovery at best.

## Recommended Config Domains
1. Persistence
- observability adapter (ETS/Ecto)
- thread/workspace storage mode

2. Live ops
- event stream limit
- polling interval fallback
- viewer tracking and presence integration

3. Agent interactions
- runner timeout
- history limits
- internal tag classification

4. Cluster/runtime scope
- cluster enablement
- RPC timeout
- default node scope
- runtime options (single/multi-runtime)

5. Chat providers
- key detection and provider-specific guidance

## Profile Definitions
### Profile A: Local Dev Fast Start
- Runtime configured
- ETS persistence
- polling acceptable
- chat keys optional

Use when:
- one developer
- short-lived sessions
- iteration speed prioritized

### Profile B: Demo / Chat Showcase
- Runtime configured
- thread persistence enabled
- provider key configured
- basic event retention tuned

Use when:
- onboarding stakeholders
- validating chat scenarios

### Profile C: Team Durable Ops
- Runtime configured
- durable persistence (Ecto/file-backed thread storage)
- realtime presence when available
- scope controls and diagnostics enabled

Use when:
- multi-user operations
- incident response expectations

## UX Delivery
Setup assistant should expose:
1. Active profile badge
2. "Apply profile snippet" action
3. "What changes?" explanation
4. Safe rollback guidance

## LLM Key Guidance
- If chat is unavailable due to keys:
  - show concise warning
  - provide provider-specific key names
  - offer `Interact` fallback immediately

LLM keys should not block non-chat operations.

## Acceptance Criteria
1. Users can choose a profile in under 30 seconds.
2. Users can run at least one successful interaction without configuring optional domains.
3. Chat-only failures never block non-chat debugging workflows.
