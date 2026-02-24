# Page Contracts Spec

## Purpose
Define the minimum contract for each top-level page so information architecture remains coherent as features grow.

## Shared Contract (All Pages)
1. Title and subtitle must answer the primary page question.
2. Scope context (`runtime`, `node`) must be visible and preserved.
3. Scope complexity is progressive: runtime summary first, node controls in Advanced Scope.
4. Empty states must be explicit and actionable.
5. Errors must include a next action link.
6. No page should require deep technical knowledge for its primary action.

## Home
Primary question: Are my Agents healthy right now?

Required sections:
- Fleet health summary cards
- Attention needed list with actionable links
- Setup assistant entry/completion state
- Quick actions to Agents, Activity, Diagnostics

Must not contain:
- raw trace tables as primary content

## Guide
Primary question: How do I get productive quickly in this product?

Required sections:
- tour flow cards with duration and clear outcome
- start/resume/replay controls
- discovery glossary (discovered modules vs running/active instances)
- starter module CTA that opens Agents with explicit start confirmation
- explicit scope-preserving workflow framing

Must not contain:
- hidden auto-launch behavior without an opt-in control

## Agents
Primary question: Which Agents are running and what should I do next?

Required sections:
- Discovered modules/running/active counts
- inventory explainer clarifying module vs instance model
- Fast path into instance manager
- Basic View default for first interaction loop
- Advanced View toggle for full workbench controls
- starter agent card with “why this starter” reason
- Internal vs product grouping where applicable
- Source App metadata for discovered module ownership
- Follow behavior for active instances

Must not contain:
- deep trace explorer as default list content

## Catalog
Primary question: What can my Agents do?

Required sections:
- discoverable tabs (`Agents`, `Actions`, `Sensors`, `Plugins`)
- searchable list
- readable summary + schema hint/details

Must not contain:
- runtime incident feed as primary content

## Activity
Primary question: What happened recently?

Required sections:
- timeline of recent operations
- grouped summaries by severity/source
- direct links to deeper diagnostics routes

Must not contain:
- full configuration management controls

## Diagnostics
Primary question: Why did this fail?

Required sections:
- deep links to traces/actions/workflows/signals
- runtime diagnostics summary (scope connectivity, data source health)
- advanced views area (timeline, correlation tools)

Must not contain:
- onboarding as primary top-level content

## Settings
Primary question: How is Studio configured?

Required sections:
- current scope and runtime config status
- setup assistant re-entry
- persistence/realtime/tracing/evals settings summary

Must not contain:
- dense incident timeline

## About
Primary question: What is this product and where can I go next?

Required sections:
- product narrative aligned to first principles
- links: docs, community, website, GitHub, support contact
- runtime version information

Must not contain:
- operational controls

## Cross-Page Navigation Rules
1. Top nav order is fixed and stable.
2. Scope state survives navigation.
3. Diagnostic pages are reachable from any warning card within one click.
4. Every page provides at least one clear "next action" affordance.

## Acceptance Criteria
1. Primary user can explain each page purpose from title/subtitle alone.
2. Operator can complete the main task per page without opening code.
3. Deep technical tooling remains available but is not required for primary flows.
