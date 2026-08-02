# Job 5: Reproduce Behavior Safely

## Status

**Hypothesis**

Current code supports parts of the non-chat and chat paths, but the repository
has no direct customer evidence for the complete job. Use the shared readiness
score and research rules in [README.md](README.md).

## Priority and Hire Moment

- **Priority:** 5 of 8 — second core repeated-use job. It follows diagnosis when
  the next action is to verify a behavior.
- **Hire moment:** A developer must repeat a failure, verify a fix, learn how an
  agent responds, or compare an actual result with an expected result.

## Job Statement

> When I need to verify or repeat an agent behavior in a live or controlled
> runtime, I want to send one known input with clear safety checks and compare the
> result with the prior state, so I can confirm the behavior without causing an
> unintended action.

## Successful Outcome

The developer runs one chat or non-chat interaction against the intended
instance. The input is valid for the known contract. The developer explicitly
arms the exact input and target before execution. The result shows the response,
the before-and-after state delta, and links to trace, event, tool, and thread
evidence. Unknown or pending data has an explicit label.

## Job Dimensions

### Functional

**Hypothesis:** The developer must choose the correct instance and interaction
type, validate a known input, run it once, compare state, and open the evidence
that proves what occurred.

### Emotional

**Hypothesis:** The developer wants confidence that a test will not run against
the wrong process or with stale input. The developer also wants a clear result
when execution times out or only queues work.

### Social

**Hypothesis:** The developer wants to show a teammate that the reproduction was
controlled, repeatable, and linked to evidence. The record must not expose a
secret or imply more safety than the runtime provides.

## Forces

### Push

**Hypothesis:** Temporary scripts, manual calls, and chat tests can lose the exact
input, state, or trace. A failure can be difficult to repeat after the first
incident ends.

### Pull

**Hypothesis:** One guarded loop for chat and non-chat agents can make a
reproduction faster and easier to review. Guided fields, state deltas, and
evidence links can reduce custom debug code.

### Anxiety

**Hypothesis:** The developer fears a wrong instance, invalid payload, duplicate
dispatch, destructive side effect, secret exposure, hidden timeout, or result
that looks complete while work is still queued.

### Habit

**Hypothesis:** The developer already uses `iex`, unit tests, temporary scripts,
direct signal calls, a chat client, and log comparison. These paths give full
control, even when they take more time.

## Current Alternatives

All alternatives are hypotheses until research confirms past use.

- **Current product path:** Chat sends a non-empty message and can show streamed
  text, tool events, and trace links. Interact selects a signal or action,
  supports guided fields or raw JSON, validates a known action schema, requires
  confirmation, supports sync and async dispatch, captures sync state snapshots,
  and links to Events, Thread Context, Traces, and Diagnostics. These two paths
  do not yet use one complete safety and result contract.
- **DIY path:** Open `iex`, call the agent API, send a signal, write a one-off Mix
  task, or add a temporary test with copied incident data.
- **Indirect tools:** Use an API client, an LLM chat tool, a queue console, or a
  general process inspector.
- **Team path:** Ask the agent author to run the input in a known environment.
- **Non-consumption:** Avoid the reproduction because the only available
  instance can change production data, or wait until a local setup is ready.

## Direct Simple Experience

### Entry Condition

The developer has selected a discovered agent and a running instance. The entry
can also come from a diagnosis with preserved scope, evidence IDs, and a sample
input.

### User Steps

1. Confirm the runtime, node, instance, current status, and interaction type:
   Chat or Signal/Action. Review the source incident or trace if one exists.
2. Enter the message or payload. Use guided fields for a supported schema or raw
   JSON for a complex schema. Review validation results and the exact normalized
   input.
3. Arm one run. The confirmation names the target, input, dispatch mode, and
   known side-effect limit. Any change disarms the run.
4. Run once. Show Waiting for a sync or chat request and Queued for async
   dispatch. Prevent a second dispatch from the same arm state.
5. Review the final status, response, state delta, and evidence links. To repeat
   the interaction, review the current state and arm a new run.

### Completion State

The developer has a reproduction record with target, input, time, dispatch mode,
status, response, before-and-after state result, and available evidence IDs. The
record distinguishes Completed, Failed, Queued, Timed out, and Unknown. The
developer can compare the result with the expected behavior or open the linked
evidence.

## Experience Rules

- Show the selected runtime, node, module, and instance ID next to the run
  controls. Do not let a scope change remain hidden.
- Use the same safety contract for chat and non-chat execution. A chat submit is
  an execution and must have explicit arming.
- For chat, require a non-empty message and show configured input and timeout
  limits. Mark provider or model controls as UI-only when they do not change the
  runtime strategy.
- For non-chat input, require a JSON object. Validate it against the action
  schema when a schema exists. State `No schema validation available` when it
  does not exist.
- Guided fields support the simple top-level types that the current form can
  convert: string, number, integer, and boolean. Use raw JSON for nested or other
  complex schemas. Do not call raw JSON validated unless schema validation ran.
- The arm state must cover the runtime, node, instance, interaction target,
  message or payload, schema version or source, and dispatch mode. Any change to
  one of these values must disarm execution.
- Recheck the live instance and capability immediately before dispatch. One arm
  state permits exactly one dispatch.
- For sync and completed chat work, capture state before and after the run. Show
  changed, added, and removed fields. If a snapshot is unavailable, say `State
  delta unavailable`; do not say `No change`.
- For async dispatch, `Queued` is not `Completed`. Do not show a final state
  delta until runtime evidence confirms completion.
- Keep trace, event, call, task, tool, and thread links with the original runtime,
  node, agent, instance, and incident context.
- Show the active timeout before execution. Do not retry automatically after a
  timeout or error.
- Redact configured sensitive fields before display or persistence. Do not store
  a full input or response only to calculate product metrics.

## Failure and Recovery States

- **No running instance:** Disable arming. Offer Select an instance or Start an
  instance. Keep the prepared input only if access rules allow it.
- **Chat is unsupported:** Explain the missing chat contract. Offer a known
  signal or action in Interact when one is available.
- **No dispatchable signal or action:** Show discovered static capabilities and
  explain that no runtime route is available. Offer read-only inspection.
- **Invalid field or JSON:** Keep the input, show the exact field or parse error,
  and keep execution disarmed. Offer raw JSON only when it is a valid recovery.
- **Input changed after arming:** Disarm immediately and state which part changed.
- **Instance or scope changed after arming:** Cancel the arm state. Require a new
  review against the new target.
- **Instance stopped before dispatch:** Do not send. Offer Refresh instances and
  Select another instance.
- **Timeout:** Mark the execution result as Unknown unless evidence proves a
  final state. Offer Open Traces, Refresh State, and Copy run reference. Do not
  issue an automatic retry.
- **Async work queued:** Show that no final response or state delta is available.
  Link to events or traces that can confirm completion.
- **Dispatch or credential error:** Show a plain-language error and the technical
  detail. Keep the input for correction, and require a new arm state.
- **State snapshot unavailable:** Show the response and evidence links, but label
  the state delta as unavailable.
- **No trace ID:** Link to the scoped events and thread context that exist. State
  that trace evidence was not captured.

## Acceptance Criteria

- Given a chat-capable running instance and a valid message, when the developer
  submits without arming, then no request starts.
- Given a chat or non-chat input that is armed, when the message, payload, target,
  dispatch mode, runtime, node, or instance changes, then execution becomes
  disabled until the developer arms it again.
- Given a non-chat action with required schema fields, when one field is invalid,
  then the page shows the field error and dispatch count remains zero.
- Given a nested schema, when guided fields cannot represent it, then the page
  explains the limit and offers raw JSON without claiming that the raw input is
  schema-valid.
- Given one valid arm state, when the developer runs the interaction twice, then
  only the first event dispatches.
- Given an instance that stops between arming and execution, when the developer
  selects Run, then the product reports the stopped instance and sends nothing.
- Given a completed sync or chat interaction with readable state, when the result
  loads, then it shows the response and an accurate before-and-after state delta.
- Given an unavailable state snapshot, when the result loads, then it says `State
  delta unavailable` and does not say `No change`.
- Given async dispatch, when the runtime only accepts the work, then the result
  says `Queued` and does not report completion or a final state delta.
- Given a run with trace or tool evidence, when the developer opens an evidence
  link, then the linked page keeps the full scope and reproduction context.
- Given a configured sensitive field, when a reproduction record is shown or
  saved, then the sensitive value is absent or redacted.
- Given a supported chat or non-chat task in a usability test, when a participant
  starts at the selected instance, then the participant reaches a reviewable
  result in no more than five user steps.

## Job Metrics

### Big Hire

**Hypothesis metrics:**

- First guarded interaction success rate in a new workspace, split by chat and
  non-chat mode.
- Median time from activation to the first result with an evidence link.
- Percentage of first-time developers who complete the simple loop in less than
  two minutes. This target comes from the current product principles and needs
  research validation.
- Percentage of evaluators who use the guarded path instead of writing temporary
  debug code for the next reproduction.

### Little Hire

**Hypothesis metrics:**

- Interaction completion rate and median result time, split by chat, non-chat,
  sync, and async mode. The current `interaction_started` and
  `interaction_completed` events can provide a baseline.
- Validation-error recovery rate and median correction time.
- Count of dispatches without a valid arm state and count of duplicate dispatches
  from one arm state. Both counts must be zero.
- Percentage of completed runs with an available and viewed state delta. The
  current `interaction_state_delta_viewed` event can provide a baseline.
- Percentage of results with a usable trace, event, tool, or thread link.
- Percentage of next-action links opened with context intact. The current
  `interaction_next_action_opened` event can provide a baseline.
- Repeat guarded use for a later incident, separate from first success.

## Research Questions

Ask only about past events.

- Tell me about the most recent agent behavior that you tried to repeat.
- What caused you to start the reproduction?
- How did you select the runtime and process?
- What exact chat message, signal, action, or payload did you use?
- Where did that input come from, and how did you check it?
- What did you do before execution to prevent an unintended change?
- What result did you inspect first?
- How did you compare state before and after the run?
- Which trace, event, tool, or thread evidence proved the outcome?
- Tell me about the last timeout or queued action that was hard to interpret.
- Tell me about a reproduction that you did not run because it felt unsafe.
- Who reviewed or received the result, and what did you share?

## Evidence Needed

- At least 10 timeline interviews with developers who recently repeated an agent
  behavior, with both chat and non-chat cases.
- Real inputs, validation errors, confirmation steps, results, state checks, and
  evidence links, with sensitive values removed.
- Baseline task time and error rate for `iex`, temporary tests, scripts, chat
  tools, and the current product path.
- Past cases with sync completion, async queueing, timeout, process exit, missing
  schema, complex schema, and missing state or trace data.
- Past examples of unintended dispatch or a decision not to run.
- Evidence for the functional, emotional, and social dimensions and all four
  forces.
- Observed task tests against representative chat and non-chat agents in a
  controlled runtime.

## Scope Boundaries

- `Safe` means that the experience prevents accidental or unclear dispatch. It
  does not mean that an action has no external effect, runs in isolation, can be
  reversed, or is safe to repeat.
- This job does not create a production sandbox, transaction rollback, or action
  approval system. The host remains responsible for runtime access and business
  authorization.
- Schema validation checks the known input contract. It does not prove that the
  business effect is safe.
- A state delta is an observation. Concurrent work can also change state. The
  result must not claim causation when correlation is uncertain.
- Async acceptance does not prove completion. A later event or trace must confirm
  the final outcome.
- This job is for operations and debugging. It is not a general model playground
  or model benchmark.
- Current defaults include a 5-second non-chat runner timeout, a 30-second chat
  timeout, and 20 recent runner-history entries. These values can change by
  configuration, so the experience must show the active values.

## Research -> Plan -> Implement Cycle Gates

### Research Gate

Do not plan the solution until the team has the required interviews, separate
chat and non-chat timelines, baseline time and errors, past safety failures or
avoidance, alternative use, and evidence for all job dimensions and forces. Keep
the status as Hypothesis if these items are missing.

### Plan Gate

Do not implement until the plan defines one five-step loop, the full arm-state
contract, validation rules, sync and async status rules, state-delta semantics,
evidence links, redaction and persistence rules, recovery states, metrics, and a
test for every acceptance criterion.

### Implement Gate

Do not mark the cycle complete until automated tests prove zero dispatch before
arming, automatic disarm after each relevant change, one dispatch per arm state,
correct status and delta semantics, redaction, and context-preserving evidence
links. Run observed tests for chat and non-chat tasks. Compare results with the
prior alternatives and update the hypotheses.
