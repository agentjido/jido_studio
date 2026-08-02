# Job 6: Understand an Unfamiliar Agent

## Status

**Hypothesis**

Current discovery, instance, catalog, and introspection code supports parts of
this job, but the repository has no direct customer evidence for the complete
experience. Use the shared readiness score and research rules in
[README.md](README.md).

## Priority and Hire Moment

- **Priority:** 6 of 8 — third core repeated-use job. It reduces the time needed
  before a developer can diagnose or reproduce behavior.
- **Hire moment:** A developer takes an on-call case, inherits a codebase, reviews
  a new agent, or returns to an agent after enough time to forget its contract.

## Job Statement

> When I take responsibility for an agent that I did not build or have not used
> recently, I want to see what exists, what is running, what it can accept and do,
> and where its limits are, so I can select a safe next action without first
> reading the full codebase.

## Successful Outcome

The developer can identify the module, its discovery source, its running
instances, its chat and non-chat capabilities, its input schemas, and its known
limits. The developer can distinguish static information from live runtime
evidence and can select one safe next action in the correct scope.

## Job Dimensions

### Functional

**Hypothesis:** The developer must find a module or instance, understand its
identity and runtime state, inspect accepted signals and actions, read the known
schemas and limits, and choose a next action.

### Emotional

**Hypothesis:** The developer wants to feel oriented instead of lost in source
code or runtime data. The developer wants explicit unknowns before taking an
action against an unfamiliar process.

### Social

**Hypothesis:** The developer wants to look prepared when responding to a team
request or incident. The developer must explain what is known without claiming
that static metadata proves live behavior.

## Forces

### Push

**Hypothesis:** An incident or handoff creates time pressure. Agent information
is split across source modules, tests, process state, routes, schemas, logs, and
the person who built the agent.

### Pull

**Hypothesis:** A single map of modules, instances, capabilities, schemas, limits,
and next actions can shorten the path to useful work.

### Anxiety

**Hypothesis:** The developer fears stale discovery data, a wrong node, confusion
between compiled and running code, incomplete schema information, and accidental
execution against a live instance.

### Habit

**Hypothesis:** The developer already searches source and tests, reads generated
documentation, inspects the supervision tree, uses `iex`, and asks a maintainer.
These methods are trusted because they expose the underlying implementation.

## Current Alternatives

All alternatives are hypotheses until research confirms past use.

- **Current product path:** Search Agents for running instances, open Catalog for
  discovered metadata and a schema hint, and open an agent instance for Basic or
  Advanced views. Advanced Interact shows static and runtime signal routes,
  actions, schema warnings, and chat or dispatch support. The developer must
  combine these views.
- **DIY path:** Search modules and tests with an editor or `rg`; call
  `Jido.Discovery`, `Jido.list_agents`, `Jido.AgentServer.status`, and router
  inspection functions in `iex`; then copy the findings into notes.
- **Indirect tools:** Use generated API documents, a process dashboard, logs, an
  observability service, or an architecture document.
- **Team path:** Ask the agent author which process is live and which input is
  safe.
- **Non-consumption:** Delay the task, avoid the unfamiliar agent, or wait for a
  maintainer to become available.

## Direct Simple Experience

### Entry Condition

The developer knows a module name, agent name, slug, instance ID, project or user
scope, or only that an agent needs attention.

### User Steps

1. Select the runtime and node scope. Search or filter the combined module and
   instance list by name, slug, module, instance, status, project, or user.
2. Open the agent identity. Review its module, name, description, slug, source
   application, category, tags, discovery source, and data freshness.
3. Review running instances. See the instance ID, node, status, start time, last
   activity, uptime, viewers, and known project or user scope. Select one exact
   instance when live detail is needed.
4. Review capabilities and limits. See chat support, consumed signals, action
   targets, route origins, entry and advanced routes, schemas, required fields,
   current runtime availability, and every introspection warning.
5. Select one next action: observe the instance, open scoped traces, inspect code
   or metadata, start an instance through a separate confirmation, or reproduce
   behavior through the guarded Job 5 path.

### Completion State

The developer can answer these questions: What is this module? Is an instance
running? Where is it running? What inputs can it accept? What can it do? Which
facts are static, live, limited, or unknown? The selected next action keeps the
same scope and cannot execute without its own confirmation.

## Experience Rules

- Treat the discovered module and the running instance as separate objects. Show
  the relation between them without merging their evidence labels.
- Label every fact as static metadata, live runtime data, observed telemetry, or
  inferred fallback. Show the source node and freshness for live data.
- `Static route` means that code declares a route. It does not mean that the
  selected instance can receive it now. `Runtime route` means that inspection
  found the route on the selected live instance.
- A module can be discovered with no running instances. A running process can
  also exist without complete discovery metadata. Show both cases.
- Keep each instance node-specific. A cluster-level module row must not imply
  that each route or instance exists on every node.
- Separate chat support from chat availability. Module functions can show
  support while a missing process, runtime setting, or credential prevents use.
- For each signal, show its type, source or origins, target, priority, matcher
  presence, entry or advanced class, runtime availability, and last-seen time
  when known.
- For each action, show its label, document text, source, primary signal type,
  schema, required fields, and schema conversion warning.
- State all introspection limits. A missing schema is not an empty schema. A
  static route is not proof of dispatch. An offline status is not proof that the
  module is absent.
- Use explicit `not available` or `unknown` text instead of blank values.
- Keep `runtime`, `node`, project, user, module, and instance context in every
  next-action link.
- Make Observe and Inspect read-only. Start, Chat, Signal, and Action must use a
  separate confirmation or guarded execution flow.
- Show plain-language identity and purpose first. Keep raw metadata, state, route
  targets, and schemas available as deeper detail.

## Failure and Recovery States

- **No Jido runtime configured:** Show discovered modules only. Explain that live
  instance management is unavailable and link to the exact configuration need.
- **Discovery unavailable:** Show running instances and inferred module identity
  when possible. Mark missing catalog data and offer Retry or Inspect code.
- **One or more nodes unreachable:** Keep results from reachable nodes, list each
  unavailable node, and do not present the partial count as a cluster total.
- **No running instance:** Mark the module as Available, not Running. Offer
  read-only capabilities and a separate Start instance action.
- **Running-only module:** Show the process and module identity. Mark description,
  category, tags, or schema as unknown when discovery cannot provide them.
- **Instance stopped during inspection:** Mark the live data as stale, disable
  execution actions, and offer Refresh instances or Select another instance.
- **Runtime route inspection failed:** Keep static routes, show the inspection
  error, and do not label those routes as dispatchable.
- **Schema missing or complex:** Show the action and the limit. State that Guided
  Fields are unavailable and that raw JSON does not add a missing contract.
- **Chat supported but unavailable:** State the current reason, such as no live
  instance or missing credential, and offer non-chat capabilities when present.
- **Filters return no result:** Keep the query visible. Offer Clear filters or
  Widen node scope without silently changing scope.

## Acceptance Criteria

- Given a discovered module with no process, when the developer opens it, then
  the page says Available, shows static capabilities, and shows no live-state
  claim.
- Given a running process with incomplete discovery metadata, when the developer
  opens it, then the page shows the instance and module and labels the missing
  metadata as unknown.
- Given the same module on two nodes, when the developer opens the module, then
  each instance keeps its node and node-specific status.
- Given one static route and one inspected runtime route, when capabilities load,
  then each route has the correct source and dispatch-availability label.
- Given an action with a supported schema, when the developer opens it, then the
  page shows field types, required fields, and the primary signal type.
- Given a missing or complex schema, when the developer opens the action, then
  the page shows the limit and does not call the input contract complete.
- Given a chat-capable module with no live process, when the developer opens it,
  then the page separates Chat supported from Chat unavailable.
- Given a node inspection error, when the page loads, then reachable data remains
  visible and the partial result and recovery action are explicit.
- Given a scoped module or instance, when the developer opens Observe, Traces,
  Start, or Reproduce, then the target retains the runtime, node, and entity
  context.
- Given only read-only exploration, when an automated test compares runtime state
  before and after the path, then the state is unchanged.
- Given a representative unfamiliar agent in a usability test, when a participant
  starts with its name or instance ID, then the participant selects a reasoned
  safe next action in no more than five user steps.

## Job Metrics

### Big Hire

**Hypothesis metrics:**

- First-task success rate for finding a known module or instance and correctly
  stating whether its facts are static or live.
- Median time from activation to the first selected safe next action for an
  unfamiliar agent.
- Percentage of evaluators who can identify one capability and one limit without
  opening source code.
- Percentage of evaluators who use this path again for a second unfamiliar
  agent, separate from first use.

### Little Hire

**Hypothesis metrics:**

- Median time from search to a reasoned next action.
- Percentage of tasks in which the developer correctly identifies module,
  instance, node, capability source, schema status, and a known limit.
- Percentage of module and instance views with explicit source and freshness.
- Percentage of capabilities with a clear static, runtime, observed, or unknown
  label.
- Percentage of next actions that retain scope and entity context.
- Rate of fallback to source search, `iex`, or a maintainer before the developer
  selects a next action.
- Repeat use during a later handoff, review, or incident.

Do not treat a Catalog or Agents page view as job completion. Completion requires
a selected next action after the developer reviewed identity, runtime state,
capabilities, and limits.

## Research Questions

Ask only about past events.

- Tell me about the most recent agent that you had to understand but did not
  build.
- What caused you to take responsibility for it?
- What was the first question that you tried to answer?
- Where did you look first, and what did you open next?
- How did you identify the module and its running process?
- How did you confirm the environment or node?
- How did you learn which messages, signals, or actions it accepted?
- Where did you find the input schema and required fields?
- Which limit or unknown changed your next action?
- Tell me about a wrong assumption that you made about static or live behavior.
- When did you ask another person, and what information was missing?
- What safe next action did you take, and what evidence supported it?
- Tell me about a case that you delayed or stopped because the agent remained
  unfamiliar.

## Evidence Needed

- At least 10 timeline interviews with developers who recently inherited,
  reviewed, or operated an unfamiliar agent.
- The real order of source files, tests, commands, runtime tools, documents, and
  teammate questions used in each case.
- Baseline time and errors from the first question to a safe next action.
- Past examples of static-only modules, running-only modules, multi-node
  instances, missing metadata, failed introspection, and stale state.
- Representative chat and non-chat modules with simple, complex, and missing
  schemas.
- The terms that developers used for module, agent, instance, route, signal,
  action, schema, and status.
- Evidence for the functional, emotional, and social dimensions and all four
  forces.
- Observed tasks that test correct understanding, not only the ability to find a
  page.

## Scope Boundaries

- This job provides an operational map. It does not explain all source code,
  business rules, model behavior, or side effects.
- Discovery and runtime introspection show what their sources expose. They do not
  prove that a hidden or dynamic capability does not exist.
- This job does not start, stop, chat with, or dispatch to an instance. Those
  operations need their own access check and confirmation.
- This job does not replace generated API documents, source review, or tests when
  the developer needs implementation-level proof.
- Access remains subject to the host resolver and runtime permissions. A visible
  capability is not authorization to execute it.
- Current guided schema conversion supports only top-level string, number,
  integer, and boolean fields. Complex schemas require raw inspection and must
  keep an explicit limit label.
- Current discovery can combine `Jido.Discovery` metadata with live
  `Jido.list_agents` results and can collect results across nodes. The experience
  must keep the source and node of each fact after that merge.

## Research -> Plan -> Implement Cycle Gates

### Research Gate

Do not plan the solution until the team has the required interviews, real
orientation timelines, baseline time and errors, past alternative and
non-consumption behavior, terminology, and evidence for all job dimensions and
forces. Keep the status as Hypothesis if these items are missing.

### Plan Gate

Do not implement until the plan defines the combined module and instance model,
source and freshness labels, capability and schema rules, the five-step path,
all recovery states, read-only boundaries, preserved scope, completion telemetry,
and a test for every acceptance criterion.

### Implement Gate

Do not mark the cycle complete until automated tests cover static-only,
running-only, multi-node, stale, unavailable, simple-schema, complex-schema, and
chat-availability cases. Run observed tests with unfamiliar agents. Compare task
time and accuracy with source search, `iex`, and maintainer help. Record the
result and update the hypotheses.
