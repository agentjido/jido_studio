# Job 4: Diagnose an Agent Failure

## Status

**Hypothesis**

The repository has product principles and technical support for this job, but it
has no direct customer evidence. Use the shared readiness score and research
rules in [README.md](README.md).

## Priority and Hire Moment

- **Priority:** 4 of 8 — first core repeated-use job. This job is the main
  product promise after installation and activation.
- **Hire moment:** A developer gets an alert, a failed interaction, an error
  trace, or a user report and must decide what to do next.

## Job Statement

> When an agent fails or gives an unexpected result, I want to connect the first
> symptom to the most useful evidence, so I can take a confident next action
> without losing the runtime context.

## Successful Outcome

The developer can explain what failed, where it failed, which evidence supports
that conclusion, and what action comes next. The path keeps the selected
runtime, node, time range, agent or instance, incident, trace, and related IDs.
It marks missing or incomplete evidence. It does not change runtime state.

## Job Dimensions

### Functional

**Hypothesis:** The developer must correlate an incident, its events, related
traces, failed spans, and affected entities. The developer must then select a
specific next action.

### Emotional

**Hypothesis:** The developer wants to feel calm and in control. The developer
does not want to wonder if a wrong node, a short time range, or missing telemetry
caused a false conclusion.

### Social

**Hypothesis:** The developer wants to give teammates a short explanation with
evidence. The explanation must show responsible action and must not assign blame
without proof.

## Forces

### Push

**Hypothesis:** A warning only says that something is wrong. The current path can
require movement between Home, Activity, Diagnostics, and Traces, with manual
correlation at each page.

### Pull

**Hypothesis:** One ordered path from symptom to evidence can reduce search time.
Preserved scope and direct links can make the next action easier to trust.

### Anxiety

**Hypothesis:** The developer fears an incorrect cause, incomplete telemetry, a
wrong runtime or node, and an accidental change to a live process.

### Habit

**Hypothesis:** The developer already uses logs, `iex`, telemetry queries, an
observability service, and help from the person who built the agent. These tools
are familiar even when manual correlation is slow.

## Current Alternatives

All alternatives are hypotheses until research confirms past use.

- **Current product path:** Open an attention item, scan the combined Activity
  list, open Diagnostics, select a concrete node, select a recent trace, and then
  use the Traces, Actions, Signals, or Workflows pages. Many links keep `runtime`
  and `node`, but the developer can still need to restore the incident and trace
  context.
- **DIY path:** Search application logs, copy trace IDs, query telemetry data,
  inspect processes in `iex`, and write a temporary script or test.
- **Indirect tools:** Use a general error tracker, an application performance
  monitor, a process dashboard, or a team runbook.
- **Team path:** Ask the agent author or the on-call expert to investigate.
- **Non-consumption:** Restart the process, wait for another failure, ignore a
  low-impact warning, or avoid a risky investigation.

## Direct Simple Experience

### Entry Condition

The developer opens a warning, failed interaction, error trace, or copied deep
link. The entry contains at least one symptom identifier or a scoped time range.

### User Steps

1. Open the symptom. See its time, status, selected runtime and node, affected
   agent or instance, and all known incident, request, trace, call, and task IDs.
2. Review one ordered evidence timeline. It combines the incident events and
   related trace spans. It marks the first error and the most likely cause as
   candidates, not as facts.
3. Refine the time, status, or entity filter if needed. If the scope has all
   nodes, select one node for trace detail without losing the other context.
4. Select an event or span. Review its error, timing, upstream and downstream
   links, related entity, evidence source, and data limits.
5. Select one safe next action: reproduce the behavior, inspect the current
   instance, open a filtered evidence view, or copy an evidence reference.

### Completion State

The developer has a cause candidate, supporting evidence, remaining unknowns,
and one selected next action. The next action keeps the full scope and evidence
context. Any action that can change state starts a separate guarded flow.

## Experience Rules

- Keep `runtime` and `node` in every link. Also keep the time range and all known
  project, user, agent, instance, incident, request, trace, call, and task IDs.
- Show the active scope at all times. Do not silently replace an unavailable
  runtime or node.
- Use one time order for incident events and trace evidence. Show the timestamp
  source and timezone.
- Separate a symptom, a cause candidate, confirmed evidence, and an unknown.
  Do not label a selected span as the root cause only because the user opened it.
- Show evidence source and availability. Use explicit text such as `not
  captured`, `expired`, `filtered out`, or `truncated`; do not show a blank panel.
- Keep read-only diagnosis separate from execution. A link to reproduction must
  use the guarded experience in Job 5.
- Make all filtered views and selected evidence copyable as a stable URL.
- Keep technical detail one step away from the plain-language summary.

## Failure and Recovery States

- **No incident or trace correlation:** Show the identifiers that are present.
  Offer a wider time range and a filtered Activity view. Do not state that no
  failure occurred.
- **All nodes selected:** Explain that trace timelines need one concrete node.
  Let the developer select a node and keep all incident and filter values.
- **Node unreachable or RPC timeout:** Name the affected node. Keep available
  evidence, and offer Retry, Select another node, and Copy identifiers.
- **Trace not found or expired:** State the configured time window or retention
  limit. Keep the incident timeline and offer a query that uses its related IDs.
- **Trace is partial:** Show captured and expected counts when known. State the
  active span cap and missing timing fields. Offer narrower filters and the
  standard trace view.
- **Runtime is unavailable:** Keep the requested runtime in the warning. Do not
  use fallback data as if it came from the requested runtime.
- **Evidence supports more than one cause:** Show each candidate and the evidence
  for and against it. Ask for more evidence before a destructive next action.

## Acceptance Criteria

- Given an attention item with runtime, node, incident, and trace context, when
  the developer opens it, then the page and URL show and retain all four values.
- Given an incident with correlated agent, action, workflow, signal, request, and
  trace IDs, when the timeline loads, then it shows the events in one time order
  and provides direct links for each available entity.
- Given an all-node scope, when the developer selects a node for trace detail,
  then the selected incident, trace, time range, and other filters do not change.
- Given a failed span, when the developer selects it, then the detail identifies
  the evidence source, error, timing, related IDs, and any unavailable fields.
- Given a missing trace, unreachable node, or span cap, when the page loads, then
  it shows the correct recovery state and no blank evidence panel.
- Given a cause candidate, when the developer selects a next action, then the
  target receives the same scope and correlation IDs.
- Given the diagnosis path, when an automated test records runtime state before
  and after the path, then the state is unchanged.
- Given a recent real incident in a usability test, when a participant starts at
  the symptom, then the participant reaches an evidence-supported next action in
  no more than five user steps.

## Job Metrics

### Big Hire

**Hypothesis metrics:**

- Percentage of evaluation workspaces that open one actionable incident path in
  the first seven days.
- Median time from activation to the first completed diagnosis.
- Percentage of attention items with a scope-preserving next-step link. The
  current `next_step_links_evaluated` event can provide a baseline.
- Percentage of evaluators who choose this path instead of their prior manual
  path for a second incident.

### Little Hire

**Hypothesis metrics:**

- Median time from warning open to an evidence-supported next action.
- Percentage of started diagnosis paths that reach the completion state.
- Percentage of paths that require the developer to restore runtime, node, or
  correlation filters.
- Percentage of paths blocked by missing, expired, or truncated evidence.
- Percentage of next actions that open the linked trace, instance, or guarded
  reproduction with context intact.
- Repeat use for a later incident. Track this separately from first use.

The current `triage_warning_opened` and `triage_root_cause_opened` events can
start the baseline. Research must confirm that the second event represents job
completion and not only a span selection.

## Research Questions

Ask only about past events.

- Tell me about the most recent agent failure that you had to investigate.
- What was the first symptom, and where did you see it?
- What did you open next, and why?
- How did you confirm the runtime, environment, and node?
- Which identifiers did you copy between tools?
- Which evidence changed your view of the cause?
- When did you stop searching and select a next action?
- What made you distrust or reject a piece of evidence?
- Tell me about the last time the needed trace or log data was missing.
- Who needed your explanation, and what did you show that person?
- Tell me about a failure that you did not investigate. What happened after that?

## Evidence Needed

- At least 10 timeline interviews with developers who investigated an agent
  failure in the recent past.
- The real sequence of tools, queries, copied IDs, waits, and handoffs for each
  incident.
- Baseline time from first symptom to selected next action.
- Examples of evidence that produced confidence and examples that caused doubt.
- Past use of DIY, indirect, team, and non-consumption alternatives.
- Evidence for the functional, emotional, and social dimensions and all four
  forces.
- Correlation coverage for incident, request, trace, agent, action, workflow,
  signal, project, and user IDs in representative runtime data.
- Failure samples from single-node and multi-node scopes, with expired, partial,
  and unavailable telemetry.

## Scope Boundaries

- This job diagnoses agent runtime behavior. It does not replace application
  business analytics or general infrastructure monitoring.
- This job selects an evidence-supported next action. It does not promise an
  automatic or certain root cause.
- The diagnosis path is read-only. Retry, signal dispatch, chat, reset, and other
  state changes belong to the guarded reproduction job.
- The product cannot show data that the host did not capture. It must describe
  the missing evidence and its effect on confidence.
- Current foundations have finite data windows and row caps. Defaults include a
  24-hour incident retention period, a 1-hour recent-trace picker, a 2,000-span
  timeline cap, and a 5,000-span standard trace limit. The experience must show
  the configured values when they affect the result.

## Research -> Plan -> Implement Cycle Gates

### Research Gate

Do not plan the solution until the team has the required interviews, a real
incident timeline for each interview, baseline completion time, past alternative
use, and evidence for all job dimensions and forces. Keep the status as
Hypothesis if these items are missing.

### Plan Gate

Do not implement until the plan defines the five-step path, the preserved scope
and correlation contract, the evidence model, each recovery state, privacy and
access rules, job-completion telemetry, and a test for every acceptance
criterion. Map each proposed change to this job.

### Implement Gate

Do not mark the cycle complete until automated tests prove context preservation,
read-only behavior, deep links, and recovery states. Run observed tests with
recent incident data. Compare completion time and confidence with the prior
alternative. Record the result and update the hypotheses before the next cycle.
