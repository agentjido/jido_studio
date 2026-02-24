# Agent Runtime Mental Model

## Purpose
Provide a shallow, operator-friendly model for understanding what Studio shows on `Guide` and `Agents`.

Primary question:
"What am I looking at, and what should I do first?"

## Core Terms
1. `Discovered modules`
- Agent modules compiled/available in the selected runtime scope.
- High counts are expected in shared runtimes because installed packages may register many agent modules.
- A discovered module is not running yet.

2. `Running instances`
- Live processes started from a discovered module.
- Instances carry runtime state/memory and handle actual signals/actions.

3. `Active instances`
- Running instances after current scope/filter application.

4. `Memory / state`
- Runtime process state attached to an instance.
- Interactions may change this state; Studio surfaces state-delta summaries when available.

5. `Signals` and `actions`
- Signals are runtime inputs/routes.
- Actions are executable units bound to signal routes.
- In Basic View, users choose starter interactions and use schema-first payload fields where possible.

6. `Traces`
- Structured observability records for runs.
- Basic View provides direct next-action links into trace/diagnostic surfaces.

## Beginner Loop Contract
1. Open starter module.
2. Start instance explicitly (no auto-run).
3. Run one starter interaction from Basic View.
4. Review result + memory/state explanation.
5. Open an observation next action (events/context/trace/diagnostics).

## Why Counts Can Be High
1. Shared runtimes may include agents from multiple apps/packages.
2. Discovery is additive and scope-aware.
3. Studio distinguishes ownership via `Source App` metadata.

## Placement Contract
1. Definitions appear in `Guide` and `Agents` only (phase scope constraint).
2. Advanced internals remain available under `Advanced View`, not removed.
