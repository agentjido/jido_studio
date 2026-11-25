# Studio Playground

This Phoenix app mounts Jido Studio at `/studio` and starts a local Jido v3
runtime.

```sh
mix setup
mix phx.server
```

Open [Agents on localhost](http://localhost:4702/studio/agents) to inspect the
three sample instances that the playground starts in development.
Use **Start demo agent** to start the demo counter from the Agents page.
Idle agents stay resident for 24 hours in the development runtime.

## Inspect a signal and turn

Open the demo counter and select **Increment counter**. Expand **Signal
payload** to see the amount and its default. The page shows the Jido turn
result, reply count, and matching telemetry events. The page keeps the latest
turn for the current LiveView session.

The demo uses the following Jido v3.0.0-beta.3 interfaces:

- A typed `Jido.Signal` module supplies `type/0`, `schema/0`, and `new/2`.
  Its schema describes the Signal's `data` field. Studio uses
  `Jido.Joi.to_json_schema/1` to read properties, required fields, and
  defaults. The typed constructor validates the payload on the server.
- An agent definition lists routes by Signal type or pattern. A route can
  apply defaults and plugins can prepare input before an Action or Flow runs.
  The executable input schema describes that later step. Use the typed
  Signal schema for the browser control.
- The host supplies the allowed typed Signal modules. Studio checks the
  agent route and generates a button when the Signal accepts an empty object
  with its defaults. A Signal with required input needs a form or a
  host-provided preset.
- A Signal carries the trace context. Studio reads the `TurnResult` from
  `Jido.AgentServer.call/3` and matches telemetry by trace ID and turn ID.

Run `mix precommit` to compile, format, and run the tests.

## Inspect the Goliath definition

Open [Goliath definition](http://localhost:4702/studio/definitions/goliath) from
the Agents page. **Request review** shows the steps that feed the review packet
and the events that can resume the wait. Expand **Collect sources** to see its
parallel calls. Use **Topology** to follow the evidence broadcast and its
receipts. Use **Resources** to see the configured resources and scheduled
inputs. The page uses definition data and starts no Goliath runtime.

Open **Canvas** to inspect the route or signal topology as a graph. Select a
node or a connection to see its declared details. Use **Fit** to see the whole
graph. Drag the background or use the arrow keys when the canvas has focus.

To refresh the snapshot, run this command from the adjacent `jido_lab` checkout.
It reads `Jido.Lab.Goliath.visual_map/0` without starting the Lab application.

```sh
mix run --no-start ../jido_devtools/jido_studio/studio_playground/scripts/export_goliath.exs \
  ../jido_devtools/jido_studio/studio_playground/priv/definitions/goliath.json
```
