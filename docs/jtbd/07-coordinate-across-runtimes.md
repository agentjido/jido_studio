# Job 7: Coordinate Across Runtimes

## Status

**Hypothesis**

No customer interview evidence supports this contract yet.

The shared JTBD contract score is **6/10**, as stated in the JTBD index. Research
must validate the job dimensions, the four forces, the alternatives, and the
separate hire moments.

The current repository gives these implementation facts:

- Runtime selection uses configured runtime keys. Node selection uses `node=all` or one connected node name.
- Navigation links keep the `runtime` and `node` query values.
- An invalid runtime or node produces a warning and a fallback scope.
- Cluster RPC calls keep a result for each node. Some list collectors remove failed-node results and return only successful rows.
- Live Ops can show viewer counts. When Presence is not available, some count functions return `0`.
- The default observability adapter is ETS. The optional Ecto adapter stores trace data in Postgres.
- Thread storage can use ETS, a file adapter, or the host Jido storage adapter.

These facts show possible product gaps. They do not prove customer demand.

## Priority and Hire Moment

Priority: **7 of 8 — scale and lifecycle**. The first six jobs must work before a team can depend on shared, cross-runtime operations.

**Big Hire hypothesis:** A team decides to use one operations surface for a system that has more than one configured runtime, more than one node, or more than one operator.

**Little Hire hypothesis:** During each incident or handoff, an operator decides to use a scoped link and stored evidence instead of a screenshot, a log paste, or a verbal update.

## Job Statement

> When a live agent issue can span several runtimes or nodes and more than one operator must work on it, I want to identify and share the exact operational scope and durable evidence, so I can coordinate a correct next action without losing context.

## Successful Outcome

Two authorized operators can open one link and identify the same runtime, node scope, record, filters, and evidence time. Each result shows its source node and its storage state. Durable evidence remains available for the stated retention period.

If a runtime, node, record, or coordination service is not available, the page shows the exact unavailable state and a safe recovery action. It does not show a blank result or an incorrect zero.

## Job Dimensions

### Functional

The operator must select the correct runtime and node scope, follow evidence across nodes, keep that scope in links, and give another operator a stable evidence reference.

### Emotional

The operator wants to feel certain that the page does not mix data from the wrong runtime, hide a failed node, or lose evidence during a handoff.

### Social

The operator wants teammates to see a careful and verifiable handoff. The operator does not want to look careless because a link opened a different scope or an empty page.

Customer evidence for all three dimensions is missing.

## Forces

- **Push hypothesis:** Teams lose time when they compare screenshots, terminal output, and several node-specific views during one incident.
- **Pull hypothesis:** A visible scope, a stable evidence record, and a link that keeps context can make a handoff faster and easier to verify.
- **Anxiety hypothesis:** Operators fear that an all-node view is incomplete, that a link exposes sensitive values, that another person sees a different result, or that ETS data disappears before review.
- **Habit hypothesis:** Teams continue to use IEx, logs, APM links, screenshots, chat messages, and one expert who remembers the node layout.

All four forces are hypotheses. Research must find them in past behavior.

## Current Alternatives

The following alternatives are hypotheses until interviews and artifacts confirm them.

- **Direct alternative:** Operators use an existing runtime dashboard or observability tool that can filter by service, node, trace, and time.
- **Indirect alternative:** Operators use log search, APM traces, remote shells, deployment consoles, or incident chat to reconstruct one shared view.
- **DIY alternative:** A team builds an admin page, adds node names to log fields, writes RPC scripts, and copies URLs and screenshots into a runbook.
- **Non-consumption:** One operator keeps the investigation private, the team waits for the issue to occur again, or the team accepts that old evidence is gone.

## Direct Simple Experience

### Entry Condition

An authorized operator has a specific incident, agent instance, trace, or time range to share. At least one runtime is configured. The system knows the selected runtime, node scope, evidence source, and storage mode.

### User Steps

1. Open the incident or evidence record. Confirm the visible runtime, node scope, source node, evidence time, and durability state.
2. Change the runtime or node scope if it is wrong. Keep the selected record and compatible filters. Show each unavailable node in the result.
3. Review the evidence and its freshness. Select a durable record or create a durable handoff record when the current source is temporary.
4. Copy one canonical link. The link includes the runtime key, node scope, record identifier, view, filters, and fixed time range that are safe to share.
5. Send the link. The next authorized operator opens the same scope and record, sees other active viewers when Presence is available, and confirms the next action.

### Completion State

Both operators can state which runtime and nodes produced the evidence. They can see whether the evidence is live, temporary, or durable. They can open the same record and agree on the next action. If the record is not available, both operators see the same reason and recovery path.

## Experience Rules

- Show the runtime and node scope on every page that can change operational data or evidence.
- Treat `All Nodes` as an aggregation scope. Do not use it as a name for an unknown node.
- Add the source node to each aggregated result. Keep failed-node envelopes. Do not remove them from counts or lists.
- Show result coverage, such as `2 of 3 nodes responded`, when the scope contains more than one node.
- Never change an invalid or disconnected node to `All Nodes` without a visible warning.
- Keep the mount prefix, runtime key, node scope, selected record, filters, and view in a shareable link.
- Encode opaque path identifiers. An identifier that contains `/` must still open the same record.
- Do not put secrets, message content, access tokens, or unrestricted payload data in the URL.
- Apply the host resolver to every shared link. A link does not grant access.
- Label observability ETS data as temporary and restart-unsafe.
- Label Ecto observability data as durable only after the adapter and required tables pass a read and write check.
- Label thread ETS storage as temporary. A file adapter is restart-safe on its file system, but it is not automatically shared by all nodes.
- Show the retention period or the known expiry condition for durable evidence.
- Show viewer state as `available`, `not available`, or a verified count. Do not use `0 viewers` when Presence cannot supply a count.
- Keep the evidence capture time separate from the page refresh time.
- Preserve the current scope when the operator moves from a warning to agents, activity, diagnostics, traces, actions, signals, workflows, or threads.
- Do not use a blank table as an error state.

## Failure and Recovery States

| Failure state | User-visible result | Recovery |
|---|---|---|
| Requested runtime key is not configured | Name the requested key and the selected fallback | Select an available runtime or fix host configuration |
| Requested node is disconnected or unknown | Name the node and show that any fallback is a fallback | Retry the node, select another node, or open Diagnostics |
| Some nodes fail in an all-node query | Show each failed node, the reason, and result coverage | Retry failed nodes or narrow the scope to a responding node |
| Evidence exists only in ETS | Mark it temporary and show that a restart can remove it | Save a durable handoff record or configure the Ecto adapter |
| Durable adapter or tables are not available | Show the adapter check that failed | Open setup guidance, fix the adapter or migration, and test again |
| Shared record expired or was removed | Show `expired` or `removed`, not `not found` alone | Open the nearest durable trace, use the fixed time range, or ask the sender for a new record |
| Link points to a record on another node | Show the source node and current reachability | Connect to that node, use durable shared storage, or open the recorded summary |
| Presence is disabled or cannot start | Show `viewer status not available` | Continue without viewer data or configure PubSub and Presence |
| Access is forbidden | Do not show evidence or confirm that the record exists | Sign in with approved access or contact the host administrator |
| Link has unsafe or invalid filters | Ignore only the invalid values and name them | Reset the invalid filters while keeping the valid runtime and node scope |

## Acceptance Criteria

- Given a multi-runtime setup, when an operator changes the runtime, then the page header and all primary navigation links show the selected runtime key.
- Given a selected node, when an operator follows a deep link, then the link opens the same node scope and selected record.
- Given an identifier that contains `/`, when an operator copies and opens its link, then the path decoder returns the original identifier.
- Given an invalid runtime or node in a link, when the page opens, then it names the invalid value and any fallback. The page does not silently change scope.
- Given an all-node query with one failed node, when results render, then the page shows successful rows, the failed node, its error kind, and the exact response coverage.
- Given the same authorized link in two independent sessions, when both sessions open it before evidence expiry, then they show the same runtime, node scope, record identifier, fixed time range, and durable evidence revision.
- Given observability ETS, when the evidence view opens, then it states that data can disappear after a BEAM restart.
- Given the Ecto adapter with the required migration, when the process restarts, then an authorized user can open the same stored trace from the same link.
- Given thread file storage on one node, when the scope includes a different node without the same storage, then the page does not call the thread data cluster-shared.
- Given Presence is not available, when the agent list renders, then it shows `viewer status not available` and does not show a verified count of zero.
- Given an unauthorized session, when it opens a shared link, then the resolver denies access before the system reads or renders the evidence.
- Given a copied link, when its query is inspected, then it contains no configured secret key and no raw message or payload body.

## Job Metrics

### Big Hire

- **Hypothesis:** Percentage of eligible multi-runtime or multi-node teams that complete the Team Durable Ops readiness checks.
- **Hypothesis:** Percentage of first shared-operation setups that select a durable evidence adapter before a production incident.
- **Hypothesis:** Time from the decision to support shared operations to the first verified two-operator handoff.
- **Hypothesis:** Main reasons that a team keeps its current logs, shell scripts, or non-consumption behavior.

### Little Hire

- **Hypothesis:** Percentage of copied incident links that another authorized operator opens with the same scope and record.
- **Hypothesis:** Median time from link open to confirmation of the evidence source and next action.
- **Hypothesis:** Rate of runtime or node scope mismatch during a handoff.
- **Hypothesis:** Percentage of all-node queries that report complete, partial, and unavailable coverage.
- **Hypothesis:** Percentage of temporary-evidence handoffs that fail because the record expires or a process restarts.
- **Hypothesis:** Recovery completion rate for disconnected nodes, missing evidence, and unavailable Presence.

Do not use page views alone as proof that this job is complete.

## Research Questions

- Tell me about the last incident that involved more than one runtime or node.
- What first showed you that the issue could be on a different runtime or node?
- How did you identify the runtime and node that produced the important evidence?
- What did you send to the next operator during the last handoff?
- What did the next operator see when that link, screenshot, or command output opened?
- Which details did the next operator have to ask for again?
- Tell me about a past case where an all-node result was incomplete.
- How did you notice the missing node in that case?
- Tell me about the last time evidence disappeared before the team reviewed it.
- Which storage system held the evidence, and what caused the loss?
- How did your team know that another person was already investigating the same agent instance?
- Tell me about the last time you chose not to share an operations view. What did you do instead?

Ask follow-up questions about exact times, tools, links, people, and decisions. Do not ask about future intent.

## Evidence Needed

- At least 10 timeline interviews with people who recently handled a multi-runtime, multi-node, or multi-operator incident.
- Evidence from more than one team and from both single-node-to-multi-node growth and established clusters.
- Real artifacts from past work, such as sanitized links, screenshots, log queries, RPC commands, incident notes, and handoff messages.
- A map of each first thought, active search, handoff, recovery, and outcome.
- Past examples of complete results, partial node failure, expired evidence, and non-consumption.
- Baseline time and error data for the current handoff method.
- Security review evidence for URL contents, resolver behavior, and stored evidence access.
- Usability tests in which two authorized people open one scoped record from separate sessions.
- Restart tests for ETS, file, host storage, and Ecto modes.

## Scope Boundaries

### In Scope

- Runtime and node identity.
- All-node result coverage and source-node labels.
- Shareable links for records, filters, views, and fixed time ranges.
- Temporary and durable evidence states.
- Basic active-viewer awareness for multi-operator work.
- Explicit unavailable, partial, expired, forbidden, and recovery states.

### Out of Scope

- Cluster creation, node discovery infrastructure, and deployment orchestration.
- A full incident management system, chat room, comment system, or task tracker.
- Automatic replication of host data between nodes.
- Bypass of the host resolver or host security policy.
- Deployment and package upgrade work, which belongs to the next job.
- Business analytics and long-term application data storage.

## Research -> Plan -> Implement Cycle Gates

### Research Gate

- Complete at least 10 interviews about recent past behavior.
- Reconstruct each timeline from the first signal through the handoff and outcome.
- Find evidence for all three job dimensions and all four forces.
- Confirm the direct, indirect, DIY, and non-consumption alternatives with artifacts.
- Record separate evidence for the Big Hire and the Little Hire.
- Measure the current handoff time, scope-error rate, and evidence-loss rate.

The gate fails if the team has only opinions, feature requests, or future-intent answers.

### Plan Gate

- Update this contract with supported findings and keep unsupported items as hypotheses.
- Define the smallest handoff record and canonical URL contract.
- Define the source-node, coverage, freshness, durability, retention, and Presence state models.
- Map every planned change to an acceptance criterion and a job metric.
- Complete access-control, sensitive-data, retention, and cross-node failure reviews.
- Define how the experience works with the current ETS, file, host, and Ecto adapters.

The gate fails if a design can hide a failed node, change scope without a warning, or put sensitive evidence in a URL.

### Implement Gate

- Build the five-step path and all listed recovery states.
- Add automated tests for scope links, opaque identifiers, partial node results, storage modes, resolver checks, and Presence states.
- Add telemetry for handoff creation, handoff open, scope mismatch, result coverage, evidence expiry, and recovery completion.
- Run a two-operator test with one healthy node, one failed node, and both temporary and durable evidence.
- Compare completion time and error rate with the recorded current alternative.
- Record the result and update this contract before more coordination features start.

The gate passes only when another authorized operator can open the same durable evidence, identify its exact scope, and recover from each tested unavailable state.
