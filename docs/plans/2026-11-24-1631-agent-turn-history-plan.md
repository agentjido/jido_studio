---
title: Open an agent and examine its turn history
type: implementation-plan
date: 2026-11-24
last_reviewed: 2026-11-24
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Open an agent and examine its turn history

## Goal Capsule

An operator opens an agent by path and selects a past turn to examine its outcome and identifiers. Add the routes and a bounded reader in Studio. Use the local playground for verification. The implementation ends after the browser and repository checks pass. The local implementer owns these steps.

## Product Contract

### Summary

Give Agent instances a URL with the ID in the path. Give each instance a turn history that an operator can open from its detail page.

### Problem Frame

Studio currently links to `/agents/instance?id=…`. The instance view can show the result of its last Studio dispatch in that LiveView connection.

### Actors

A Studio operator with read access to the host-selected Jido runtime and partition.

### Requirements

- **R1** Open an agent at `/agents/:agent_id` and preserve existing query links through a redirect.
- **R2** Open the agent's turn history and select a completed turn to examine the signal, outcome, time, and available trace evidence.
- **R3** Verify the path and history in a browser against the running playground.

### Key Flows

Overview or Agents → agent → Turn history → select a turn. An old instance link redirects before it loads the agent.

### Acceptance Examples

`/studio/agents/instance?id=demo-counter` opens `/studio/agents/demo-counter`. Two counter turns appear at `/studio/agents/demo-counter/turns`. Selecting the older turn shows its own IDs and outcome after a browser reload. A second partition's agent with the same ID has a separate history.

### Success Criteria

The browser resolves the new routes, displays separate turns newest first, and can reopen one turn by URL. An empty history has a visible empty state.

### Scope Boundaries

The view covers recent settled turns for the running agent on the Studio node. Durable and cross-node history, action payloads, and full trace timelines require separate work.

### Key Decisions

Use the mount's existing read access and runtime selection for both pages. Preserve the immediate result on the agent page.

### Rejected Alternatives

The public `Jido.turn_result/3` API requires an exact turn ID and a retained durable result. It does not supply enumeration for this view.

### Dependencies

The playground uses Jido `3.0.0-beta.3` and Phoenix LiveView. The Jido worker emits the `[:jido, :agent_server, :turn, :settled]` event synchronously.

### Outstanding Questions

No additional product decision is required for this local history. The roadmap retains the decision about durable trace storage.

### Sources

[Current routes](../../lib/jido_studio/router.ex) · [Current signal capture](../../lib/jido_studio/turn_trace.ex) · [Playground lock](../../studio_playground/mix.lock) · [Decision roadmap](../roadmaps/jido-studio-v3.csv)

## Planning Contract

### Product Contract Preservation

The plan preserves the direct request. It defines bounded retention and keeps the old agent URL available.

### Current System

`JidoStudio.Mount` supplies the trusted scope. `AgentReads` resolves an agent in that scope. `TurnTrace` captures one Studio dispatch. The pinned Jido status API supplies the latest outcome and no history list.

### Target System

Both inventory links use a shared path formatter. Studio reads settled turn metadata by the PID of the agent it resolves in the trusted scope. A history link opens the list with an optional selected turn in the query.

### Key Technical Decisions

- **KTD1** Encode each ID as one path segment. Escape dot segments and distinguish literal escape prefixes so browsers preserve the ID. The legacy query URL redirects through the same formatter.
- **KTD2** Use a supervised in-memory buffer of up to 512 settled turns on the node. Filter by the exact resident worker PID and show the most recent 50 matches. Store only event metadata needed by the view. Restart or reactivation can remove access to previous entries.
- **KTD3** Select a turn through a query parameter. Search only the history returned for the current agent. Display an explicit state when the requested turn is unavailable.

### System Boundaries and Change Surface

| Surface | Planned change | Compatibility |
| --- | --- | --- |
| Studio routes and links | Add path-based agent and history URLs | Redirect old agent links and preserve mount prefix |
| Jido runtime | Read settled events and resolve the resident worker | Use the pinned contract. No Jido dependency update |
| Playground | Update demo access hook and mockup links | Keep the demo signal path and definition mockup available |

### Implementation Units

- **U1** Address instances by path. Update Studio and playground links, preserve the legacy redirect, and test an ID with reserved characters and a nested host mount. Covers R1 and KTD1. Done when both generated and legacy links resolve the exact instance.
- **U2** Capture and view recent settled turns. Add the buffer, scoped read, and selectable history. Depends on U1 for agent path identity. Covers R2, KTD2, and KTD3. Done when browser reload preserves selection and tests prove partition isolation.
- **U3** Verify the integrated browser flow and run repository checks. Depends on U1 and U2. Covers R3. Done when the playground renders committed and earlier turns and the check commands pass.

### Work Graph

U1 → U2 → U3. U1 is the initial unit. U3 verifies the complete change.

### Verification Contract

| Gate | Evidence |
| --- | --- |
| R1 | Playground tests for redirects, path encoding, and scope |
| R2 | Playground tests for settled turns from the runtime, selection, and partition separation |
| R3 | Chromium against a local playground. Open the legacy URL, send demo turns, open history, and reload a selected turn |
| Repository | `mix test` and `mix compile --warnings-as-errors` in Studio. `mix precommit` in `studio_playground/` |

### Rollout and Recovery

Start a separate local playground for verification if the existing playground has active state. This change requires no migration. The old URL redirects within the existing authorization boundary.

### Risks and Assumptions

The settled event does not identify the runtime or partition in this Jido version. The callback executes in the emitting worker. If that identity contract changes, the history cannot safely use the event until Studio verifies the new source.

### Open Planning Decisions

Durable retention remains a roadmap decision. It does not block these units.

### Definition of Done

The old and new links reach the same agent, the history shows scoped turn evidence, and the browser and repository checks pass.

### Planning Sources

[Mount scope](../../lib/jido_studio/mount.ex) · [Agent reads](../../lib/jido_studio/agent_reads.ex) · [Playground tests](../../studio_playground/test/studio_playground_web/studio_agents_test.exs)

## Adapter Results

- Markdown is the canonical plan.
- HTML and Beadwork were not requested.
