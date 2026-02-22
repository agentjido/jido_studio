# Jido Studio First Principles

## Elevator Pitch
Jido Studio is the operations cockpit for Agents. It turns live runtime behavior into clear status, safe interaction controls, and fast diagnostics so teams can run Agents confidently.

## Product Promise
When an Agent misbehaves, Jido Studio gets you from "what happened?" to a confident next action in minutes.

## Moment of Need
The product should feel indispensable when a user thinks:
- "I need to know if my Agents are okay right now."
- "Something broke and I need to understand why, quickly."
- "I want to test this Agent safely without writing debug code first."

## Persona Hierarchy
1. Primary: Agent Operator
Can be non-technical. Needs plain-language health, safe controls, and guided next steps.

2. Secondary: Elixir Developer
Needs deep introspection, runtime detail, and trace-level debugging.

3. Tertiary: On-call Responder
Needs fast triage and reliable paths from incident signal to root cause.

## Differentiation
- Unified operations surface for runtime health, interaction, and diagnostics.
- First-class support for both chat and non-chat Agents.
- Safe-by-default interaction model with explicit guardrails.
- Honest observability: explicit "not available" states instead of silent blanks.

## Product Boundaries
Jido Studio is not a model playground and not a replacement for app business analytics. It is an Agent operations and debugging surface.

## Message Hierarchy
- Headline: "Operations cockpit for Agents."
- Primary value: "Understand status, safely interact, and diagnose quickly."
- Outcome promise: "From symptom to confident next action in minutes."
- Trust statement: "Guarded execution, explicit unknowns, no silent failure."
- Boundary statement: "Operations/debugging, not general BI or model benchmarking."

## Jobs To Be Done
1. Know what is running right now.
The user wants a clear answer to: Which Agents are online, healthy, and active?

2. Understand what each Agent can do.
The user wants a capability view: signals consumed, actions available, schemas, and constraints.

3. Try an Agent safely.
The user wants one guided interaction surface for both chat and non-chat Agents, with guardrails before execution.

4. See what happened after an interaction.
The user wants immediate feedback: messages, events, TODOs, tool/middleware activity, and recent state.

5. Diagnose issues quickly.
The user wants to jump from high-level symptom to detailed traces without losing context.

6. Operate across environments and nodes.
The user wants cluster scope controls and reliable behavior in single-node or multi-node setups.

7. Build trust over time.
The user wants repeatable workflows, persisted context/history, and explicit "not available" states instead of silent gaps.

## Experience Model
1. Home
Answer: "Are my Agents okay?" with health, attention items, and quick links.

2. Agents
Answer: "What is running and how do I interact now?" with direct entry to instance-level play/observe/configure.

3. Catalog
Answer: "What can these Agents do?" with capabilities in readable language and schema details.

4. Activity
Answer: "What just happened?" with operational timeline and incident-oriented summaries.

5. Diagnostics
Answer: "Why did this fail?" with deep technical tools, traces, and runtime diagnostics.

6. Settings/About
Answer: "How is Studio configured and what is this product?" with operational controls and product narrative.

## Design Principles
- Agents-first language. Avoid "bots".
- Progressive disclosure. Plain-language first, technical depth one click away.
- No dead ends. Every warning/error should offer a clear next action.
- Stable layout. Avoid jarring page reflow between adjacent workflows.
- Safe by default. Guard execution and validate payloads before dispatch.
- Honest data. Show explicit unavailable states rather than blank panels.
- Context preservation. Keep scope, selected instance, and history while navigating.

## Feature Coherence Rules
- Every new feature must attach to a primary JTBD.
- Every page must answer one primary question before secondary detail.
- If a feature is "cool" but not tied to a JTBD, park it behind diagnostics or remove it.
- Prefer unification over proliferation: fewer surfaces, clearer transitions.

## What "Delight" Means Here
- Time-to-first-success in under 2 minutes for a new user.
- A non-chat Agent is still runnable and understandable without reading code.
- A failed interaction tells the user what to do next, not just what broke.
- Navigation feels predictable: Home -> Agents -> Instance -> Observe/Configure -> Diagnostics.

## Reset Plan (From First Principles)
1. Clarify promise in UI copy.
Update top-level page subtitles and helper text to align with the jobs above.

2. Harden primary interaction loop.
Ensure every instance has a clear primary action and guided fallback for non-chat capability.

3. Tighten IA consistency.
Keep top-level pages question-driven; move secondary/experimental controls behind Diagnostics.

4. Improve incident workflow.
Make "attention needed" items actionable with direct links into the exact filtered diagnostic view.

5. Define and track product metrics.
Measure first-run success, time-to-triage, and interaction completion rates.

## North-Star Metrics
- First interaction success rate (new workspace)
- Median time from warning to root-cause view
- Share of non-chat Agents successfully executed through Interact
- Percentage of incidents with a clear next-step link
- Retention of users after first week of installation
