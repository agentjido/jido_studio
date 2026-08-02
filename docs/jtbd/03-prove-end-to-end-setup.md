# Job 3: Prove End-to-End Setup

## Status

**Hypothesis**

This contract is not a validated customer job. The repository already has most
parts of a deterministic first interaction, but its setup result does not yet
prove that interaction.

The built-in `JidoStudio.BeginnerAgent` is enabled by default and has local
`ping`, `add`, `tip`, and `reset` signal routes. The current Setup Assistant says
that provider keys are optional. Its smoke check reports `pass` when any instance
is running. That check does not prove discovery, dispatch, state change, and result
rendering as one completed loop.

## Priority and Hire Moment

Priority: **3 of 8 — install and activation**.

The Big Hire occurs after install and safe mount, when the developer decides to
spend time on the first live runtime interaction.

The Little Hire occurs when the developer selects, confirms, and runs a real
interaction, then uses the visible result to trust the setup. It occurs again
when the developer repeats the smoke interaction after a configuration or
dependency change.

## Job Statement

> When I finish connecting an operations interface to my agent runtime, I want to run one deterministic interaction through the complete interface and runtime path, so I can know that the setup works before I use external credentials or a real workload.

## Successful Outcome

With all supported provider-key environment variables absent, the developer
discovers and starts the built-in beginner agent through the UI. The developer
runs `beginner.add` with `a = 25` and `b = 4`. The same page shows `Run
Succeeded`, result `29.0`, and the changed agent state. The Setup Assistant marks
the smoke interaction as passed only from this successful run evidence.

## Job Dimensions

### Functional

Prove discovery, instance start, payload validation, runtime dispatch, state
change, result rendering, and success measurement in one path.

### Emotional

Feel confident that the installation is operational before adding provider keys
or using a real agent.

### Social

Show a teammate a repeatable proof with known inputs, known output, source
revision, runtime, node, and instance identity.

All three dimensions are hypotheses. Customer research must validate them.

## Forces

- **Push hypothesis:** Readiness checks can look healthy while the first real
  dispatch still fails.
- **Pull hypothesis:** A bundled deterministic agent with sample inputs gives a
  fast and safe proof of the full loop.
- **Anxiety hypothesis:** The developer fears hidden provider costs, missing API
  keys, network calls, changes to a real agent, or a false positive from a shallow
  health check.
- **Habit hypothesis:** The developer stops after compilation, checks only that a
  page loads, calls an action directly in IEx, or waits for real provider
  credentials.

## Current Alternatives

- Check only that `/studio` renders.
- Check runtime connectivity and the count of running instances.
- Call a Jido action or agent directly from IEx.
- Run a provider-backed chat or weather example with an API key.
- **DIY:** Create a temporary test agent, route, payload, and result page in the
  host application.
- Ask a teammate to verify an existing real agent.
- **Non-consumption:** Accept compilation as proof, skip the interaction, and find
  setup defects during later work.

## Direct Simple Experience

### Entry Condition

Jobs 1 and 2 are complete. The user has `:all` access. A Jido runtime is
configured and reachable. The beginner agent is enabled. `ANTHROPIC_API_KEY`,
`CLAUDE_API_KEY`, `OPENAI_API_KEY`, and `GROQ_API_KEY` are absent or empty.

### User Steps

1. Open `/studio` and select `Run smoke interaction`. The Setup Assistant states
   that chat credentials are optional.
2. Open the built-in Starter Agent. If it is not running, review the generated
   instance ID and select `Start Instance`.
3. Select `Add`. Keep the sample inputs `25` and `4`.
4. Select `Confirm Inputs`, then select `Run Interaction`.
5. Verify `Run Succeeded`, result `29.0`, and the state change for
   `last_addition_result`.

### Completion State

The current setup session has a `Smoke Test Passed` result tied to the completed
`beginner.add` run. The proof identifies the locked source revision, runtime,
node, agent module, instance, signal type, completion time, and success status. A
running instance without a completed interaction remains `Ready`, not `Passed`.

## Experience Rules

- The smoke path must not require an LLM, a provider key, a provider adapter, or an
  external network call.
- Missing provider keys are information only. They are not a warning or failure
  for this job.
- The built-in beginner agent is the default smoke target when it is enabled.
- Instance start remains explicit. Opening a starter link can open the start
  modal, but it must not start an instance without user confirmation.
- The standard proof uses `beginner.add` with `25` and `4` and expects `29.0`.
- A unit call to `Actions.Add.run/2` is not end-to-end proof.
- A running process, agent count, reachable runtime, or rendered page is readiness
  evidence only. None of these states can produce `Smoke Test Passed`.
- The completed path must include UI discovery, UI start, signal selection, sample
  payload, guarded dispatch, the live agent process, state readback, visible
  result, and completion measurement.
- The selected runtime and node scope must stay fixed through start, dispatch, and
  proof display.
- The user-visible state model must distinguish `Blocked`, `Ready`, `Running`,
  `Passed`, and `Failed`.
- A pass record must come from a successful completed interaction. It must not
  come from a page view or a predicted path.
- The proof must not store provider keys, host secrets, arbitrary user payloads,
  or full agent state. The fixed smoke identifiers and result are sufficient.
- A repeated run must make a new result. A stale pass must show its time and source
  revision.

## Failure and Recovery States

| Failure state | User-visible result | Recovery |
| --- | --- | --- |
| No Jido runtime is configured | The smoke state is `Blocked` and names `config :jido_studio, jido_instance: MyApp.Jido` | Add the runtime configuration, start it, and select `Re-test` |
| The runtime is unreachable | The smoke state is `Blocked` and names the selected runtime and node | Fix runtime or node connectivity, then retry in the same scope |
| The beginner agent is disabled | The smoke state explains that the deterministic starter is unavailable | Set `config :jido_studio, :beginner_agent, enabled: true` and re-test |
| The instance cannot start | The start modal keeps the entered ID and shows the exact start error | Change a conflicting ID or fix runtime start configuration, then retry |
| The payload is invalid | Field-level errors appear and the run stays unarmed | Correct the values, confirm them again, and retry |
| Dispatch times out or the instance exits | The run is `Failed`; no pass record is written | Restart the instance or fix the runtime, then rerun the same sample |
| The run returns success but no expected state or result appears | The smoke state is `Failed` and links to events or diagnostics | Inspect the correlated run, fix state readback or rendering, and rerun |
| Provider keys are absent | The page states `Chat credentials optional`; the Interact path stays enabled | Continue with the deterministic smoke interaction |
| A prior pass used another revision or scope | The old proof is labeled stale for the current setup | Run the smoke interaction again in the current revision and scope |

## Acceptance Criteria

- [ ] An integration test removes all four supported provider-key environment
      variables before the first page request.
- [ ] The test enters through `/studio`, follows the `Run smoke interaction` path,
      and uses the built-in beginner agent.
- [ ] The test starts the beginner instance through the LiveView start event. It
      does not call `Jido.start_agent/3` as test setup.
- [ ] Before dispatch, a reachable runtime or running instance produces `Ready` or
      `Running`, never `Passed`.
- [ ] The test selects the `Add` starter operation and verifies the sample payload
      contains `a = 25` and `b = 4`.
- [ ] The test confirms inputs, dispatches through the guarded runner, and receives
      a successful completed interaction.
- [ ] The rendered result contains `Run Succeeded`, `beginner.add`, `29.0`, and a
      `last_addition_result` state change from `0.0` to `29.0`.
- [ ] The agent process snapshot after the run contains
      `last_addition_result: 29.0`.
- [ ] The Setup Assistant changes to `Smoke Test Passed` only after the completed
      run evidence is available for the current session and scope.
- [ ] The run emits `[:jido_studio, :interaction, :started]`, a successful
      `[:jido_studio, :interaction, :completed]`, and
      `[:jido_studio, :onboarding, :first_interaction_succeeded]` with correlated
      runtime, node, path, and session metadata.
- [ ] A dispatch error emits the completed error result, does not emit first
      success, and does not create a pass record.
- [ ] A test provider adapter or network guard proves that the smoke path makes no
      provider or external network request.
- [ ] The failure tests preserve the selected runtime, node, operation, and safe
      sample inputs for a direct retry.

## Job Metrics

### Big Hire

- Percentage of completed installs that open the smoke path.
- Median time from first `/studio` load to an explicitly started beginner
  instance.
- Abandonment rate at runtime configuration, starter discovery, and instance
  start.
- Percentage of users who start with the deterministic path before they configure
  provider credentials.

### Little Hire

- Percentage of started smoke paths that produce a verified completed
  `beginner.add` interaction.
- Median time from instance start to the visible `29.0` proof.
- Failure rate by start, payload, dispatch, state readback, and result rendering.
- Percentage of passes that include correlated revision, scope, instance, and run
  evidence.
- Repeat success rate after a dependency or configuration change.
- False-pass rate from readiness-only states. The target value is zero.

Research must set the other target values after it measures a baseline.

## Research Questions

Ask only about past behavior:

- Walk me through the first real interaction that you ran after installing an
  operations tool.
- What did you check before you sent that interaction?
- Which provider keys were present at that time?
- What output convinced you that the full setup worked?
- Tell me about the last setup that passed a health check but failed on first use.
- Where did that failure occur between the UI, runtime, action, state, and result?
- What temporary agent or action did you create to test the setup?
- When did you stop after a page-load or process-count check? What happened next?
- Who needed to see proof of the first run, and what details did that person ask
  for?
- Tell me about the last time you repeated a smoke test after an upgrade or config
  change.

## Evidence Needed

- At least 10 timeline interviews with developers who recently completed or
  abandoned a first agent-tool interaction.
- Screen recordings or direct observations from install through visible result.
- The exact checks that gave false confidence in past setup attempts.
- Interaction logs that separate start, dispatch, state, and render failures.
- Baseline time and completion data for first and repeated smoke runs.
- Proof from a network guard that the deterministic path does not call a provider.
- Evidence for the emotional and social dimensions from customer words.
- Separate Big Hire and Little Hire measurements.

## Scope Boundaries

In scope:

- One local, deterministic, no-provider-key interaction with the built-in beginner
  agent.
- Discovery, explicit start, guarded dispatch, state readback, visible result,
  proof identity, and direct recovery.
- The current selected runtime and node scope.

Out of scope:

- Provider setup, chat completion, model quality, tool calling, and external
  network validation.
- Validation of a host application's business agents.
- Load, soak, failover, and multi-node consistency testing.
- Automatic start without user confirmation.
- Dependency installation and access policy design. Jobs 1 and 2 cover those
  outcomes.

## Research -> Plan -> Implement Cycle Gates

### Research Gate

- Complete at least 10 recent-event timeline interviews.
- Confirm or revise the job statement, all four forces, all three dimensions, and
  the current alternatives.
- Identify the proof that developers trusted and the shallow checks that produced
  false confidence.
- Record separate first-start and completed-interaction baselines.

### Plan Gate

- Define the smoke state model and the minimum evidence for `Passed`.
- Define how the current session, source revision, runtime, node, instance, and run
  identify one proof without storing sensitive data.
- Map each UI state, recovery state, metric, and automated test to an acceptance
  criterion.
- Confirm that the standard path cannot select a provider-backed interaction.

### Implement Gate

- The no-provider-key end-to-end integration suite and all failure tests pass.
- A running instance alone cannot produce a smoke pass.
- The standard run shows `29.0`, the state change, and the correlated pass record.
- A network guard proves that no provider request occurs.
- Big Hire and Little Hire measures are available without secrets or arbitrary
  payload data.
- Research participants complete the direct experience and understand the proof
  before the cycle closes.
