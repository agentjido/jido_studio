---
title: Agent definition visual rules
status: proposed
last-reviewed: 2026-11-24
---

# Agent definition visual rules

Use the three examples below to compare simple and complex definitions. The
[playground canvas](../../studio_playground/lib/studio_playground_web/live/definition_mockup_live.ex)
is the first layout reference. The [agent definition](../../studio_playground/lib/studio_playground/demo_counter.ex),
[signal schema](../../studio_playground/lib/studio_playground/demo_counter/increment.ex),
and [action](../../studio_playground/lib/studio_playground/demo_counter/increment_action.ex)
define the behavior the prototype shows.

## Prototypes

The [Codex prototype](../prototypes/agent-definition-blocks.html) shows what
each entry point does, its result, and any follow-up. Open an entry point
to see one turn of work, its signal and schema, and the resources it uses.
Use **Sample trace** to review an example across turns. To compare a fixed
overview, use `agent=factory&theme=dark` in the query string. Add
`signal=factory.candidate.prepare` to open that entry point. The agent keys
are `counter`, `team`, and `factory`.

The [Claude comparison](../prototypes/agent-definition-blocks-claude.html)
groups entry points by purpose. Open a row for its blocks. A follow-up link
moves focus to the destination row. Open **Sample trace** for an example
across turns. Use `#factory` to open the Software Factory overview.

The [node graph prototype](../prototypes/agent-definition.html) applies
these rules to `demo-counter`. The single HTML file works offline. Node
selection and theme changes run in the browser. The palette shows the node
types.

- Open the file directly in a browser.
- Add `?node=` with `signal`, `route`, `action`, `state`, or `reply` to select
  a node. Add `theme=dark` or `theme=light` to set the theme. For example,
  use `agent-definition.html?node=action&theme=light`. By default, the
  prototype selects the action and follows the system theme.
- For a revision, copy the file to a new name, such as
  `agent-definition-rev-b.html`. Change one rule and the revision label in the
  header. Open both files with the same options and window size.

## Reference agents

These are the examples for future visual reviews. The Lab links refer to the
adjacent `jido_lab` checkout.

| Size | Agent and path to show first | What the design must show |
| --- | --- | --- |
| Small | `demo-counter` · Receive `demo.counter.increment`, run the increment action, and use its result for a state commit and a reply. [Definition](../../studio_playground/lib/studio_playground/demo_counter.ex) | One stack shows the complete route. Show `amount` as an integer from 1 to 10 with default `1`. Show `count` with initial value `0`, and show that the commit and reply use the same output. |
| Medium | Team Communication (`lab_team_communication`) · Answer a Telegram question with permitted evidence. [Definition and flow](../../../../jido_lab/lib/jido_lab/journeys/team_communication/agent.ex) · [Withdraw remembered evidence](../../../../jido_lab/lib/jido_lab/journeys/team_communication/cases/withdraw_evidence/README.md) | Show the Chat trigger, grant check, scoped Memory recall, AI answer, and Chat delivery. Keep the delivery completion and its stored receipt in a separate stack. Show the Realm copy and evidence indexing when the reader opens their details. Check both the valid and revoked grant paths. |
| Complex | Software Factory (`lab_software_factory`) · Recover a draft pull request after a lost publication reply. Open `factory.candidate.prepare` first. [Definition and flow](../../../../jido_lab/lib/jido_lab/journeys/software_delivery/agent.ex) · [Lost publication reply](../../../../jido_lab/lib/jido_lab/journeys/software_delivery/cases/lost_publication_reply/README.md) | Show Telegram intake, the Harness worker in Realm, parallel checks of the committed bytes and paths, and the Loom approval wait. Link to the approval and publish stacks. Show the GitHub Connect result and the saved Ash job during recovery. |

## Block view rules

Use the Scratch pattern of an event block above a vertical stack. Give each
signal route its own stack. Use Jido Studio colors, labels, and controls.
[Scratch Foundation block guide](https://cms.scratchfoundation.org/assets/ae40e87e-f5b1-42bc-bfd3-32a65e418500)

1. Give the actor one sentence that explains its job. Give each entry point
   an aligned summary of its trigger, work, and result. Link a wait or later
   signal from the result. Open the entry point to see its exact signal type,
   schema, route match, and the work within one turn.
2. Stack sequential steps in order. Use a group for parallel work and show
   where the results join. Show a durable wait with the signal or intent
   that lets the run continue. Let readers expand a named flow or tool to
   see its steps. Show asynchronous completions as linked stacks.
3. Put Chat connections, Memory collections and grants, Realm bindings, and
   other resources in a resource list. Indicate which ones each block uses.
   Show reads, writes, and sends at the step that does them. Show plugin
   declarations and host bindings in the resource details.
4. Show possible paths in the definition. When a trace is available,
   highlight the steps that ran for the selected signal. Show a related turn
   when a later signal continues the work. Keep receipt and retry outcomes
   with that trace.

The counter fits in one stack. Both outputs use the action result.

```text
When signal demo.counter.increment arrives
  Run increment_demo_counter with amount and state.count
  Use result count
    Commit state.count
    Reply demo.counter.updated with count
```

## Layout and theme

These rules describe the current node graph prototype.

- Put the node palette on the left, the definition canvas in the center, and
  the inspector on the right. Give the canvas the most space. At narrow
  widths, put the palette above the canvas and the inspector below it. Run
  the flow from top to bottom and keep both output nodes visible.
- Reuse the Studio theme roles. Use `--studio-bg` for the canvas,
  `--studio-card` for nodes and panels, `--studio-border` for borders,
  `--studio-text` for labels, and `--studio-muted` for supporting text. Use
  `--definition-accent` for node type and `--definition-wire` for connections.
  Assign values for both themes. Keep the grid faint enough that wires and
  text stand out. [Studio theme](../../lib/jido_studio/shell.css) ·
  [component colors](../../lib/jido_studio/components.css) ·
  [canvas styles](../../studio_playground/assets/css/definition_mockup.css)
- Use system sans-serif for labels and monospace for types, paths, field names,
  and values. Use 12 px padding in a node, 16 px in a panel, and 24 px around
  the workspace as starting values. Let long identifiers wrap at `.`, `_`, or
  `/` when possible.

## Nodes and connections

| Node | Accent | Information in the node |
| --- | --- | --- |
| Signal | Cyan | Signal type, input fields, and defaults |
| Route | Amber | Match condition and action target |
| Action | Green | Action name, state read, and result |
| State | Violet | Field, type, and initial value |
| Reply | Rose | Reply signal type and payload fields |

- Give each node an icon, a type label, a name, and a short summary. Use a
  distinct outline for selection. Show keyboard focus with its own visible
  ring. Keep icons and labels so color supports recognition.
- Put input ports on the leading edge and output ports on the trailing edge.
  Keep the same direction across the canvas. Attach each wire to a port. Label
  a wire when its data or condition needs explanation. Use a branch when one
  output has two destinations.
- In `demo-counter`, a route matches `demo.counter.increment` and passes its
  payload to the action. The signal accepts an integer `amount` from 1 to 10
  and defaults to 1. The action reads `state.count` and returns the new
  `count`. The route uses that output for the state commit and for the
  `demo.counter.updated` reply. Show `0` as the initial state value.
- In the inspector, put the selected node's name and type first. Follow with
  its fields, types, constraints, and defaults. Show what it reads, what it
  produces, and where the output goes when those details apply. Label the
  screen as a prototype. Keep instance values and runtime events on the
  instance page.

## Review each change

1. Change one design rule at a time. Name the rule and the problem it solves.
   Keep the agent and selected route or node the same in the before and
   after views. Use all three examples for changes to the overall layout.
2. Compare both themes at 1440 × 900 and 390 × 844. Check label wrapping,
   contrast, and the inspector. Follow the selected signal to its response.
   In the complex example, find the approval and recovery paths from the
   overview with the other stacks collapsed.
3. Use the keyboard to reach and select a node in an interactive prototype.
   Check the focus ring and the inspector update. Keep the palette as a
   reference until the team reviews a drag-and-drop interaction.
4. Record each accepted rule with the date, reason, and review evidence in the
   table below. Update the rule above when a later review changes it.

| Date | Accepted rule | Reason and evidence |
| --- | --- | --- |
| | | |
