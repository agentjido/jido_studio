# Onboarding and Setup Assistant Spec

## Purpose
Make setup fast and obvious for both non-technical operators and developers by guiding users through a small number of high-impact checks.

## Entry Points
- Primary: `Home` page first-run card.
- Secondary: persistent `Setup` card in `Settings`.
- Re-entry: banner when critical setup regresses.

## UX Principles
- Checklist over documentation wall.
- Pass/warn/fail with one recommended next action.
- Copy-ready config snippets by profile.
- Dismissible but recoverable.
- "Apply profile snippet" is guidance-only (show/copy), never host file mutation.

## Setup Steps
1. Runtime connected
- Check that selected runtime module is configured and reachable.
- Result:
  - pass: runtime ready
  - fail: runtime missing/unreachable
- CTA:
  - `Open config snippet`
  - `Re-test`

2. Persistence selected
- Detect persistence mode:
  - ETS dev mode
  - durable mode (Ecto or file-backed thread storage)
- Result:
  - pass with durability label
  - warn for ephemeral mode
- CTA:
  - `Use durable profile`
  - `Keep dev mode`

3. Realtime enabled (recommended)
- Validate PubSub and Presence integration when configured.
- Result:
  - pass: event-driven updates
  - warn: polling fallback
- CTA:
  - `Enable realtime`
  - `Continue with polling`

4. Chat credentials (optional)
- Provider key checks only if user wants chat workflows.
- Result:
  - pass: provider key present
  - info: skipped (non-chat usage)
  - warn: key missing while chat is enabled
- CTA:
  - `Configure provider keys`
  - `Use Interact (non-chat)`

5. Smoke test
- Run a minimal end-to-end check:
  - discover runtime agents
  - open one instance route
  - optional safe runner dispatch
- Result:
  - pass/fail with links to failing section

## Setup Profiles
1. Local Dev
- Minimal setup with ETS and polling acceptable.

2. Chat Demo
- Runtime + LLM keys + basic persistence.

3. Team Durable Ops
- Runtime + durable persistence + realtime + scope controls.

## State and Persistence
- Save onboarding progress in local storage for this phase.
- Server-side user prefs are optional and deferred.
- Steps can be completed non-linearly.
- Show completion summary:
  - `Core Ready`
  - `Recommended Improvements`

## Copy Contract
- Plain language first.
- Avoid internal jargon in step titles.
- Every warning includes:
  - what it affects
  - how to fix
  - safe fallback path

## Acceptance Criteria
1. First-run user can reach a successful interaction in under 2 minutes.
2. Users can complete setup without reading external docs.
3. Missing chat keys do not block non-chat workflows.
4. Realtime and durability recommendations are visible but not required for basic usage.
5. Setup status remains accessible after dismissal.
