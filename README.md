# Jido Studio

Jido Studio is an embeddable Phoenix LiveView dashboard. The `release/v3`
branch provides an Overview page, a read-only Agents view, and an optional
component showcase.

## Mount Studio

Add Studio as a dependency, then import its router macro in your Phoenix
router.

```elixir
import JidoStudio.Router

scope "/" do
  pipe_through :browser
  jido_studio "/studio"
end
```

The host supplies the root layout, LiveView client, and endpoint socket.
Use the same socket path in the endpoint and the host's `LiveSocket` client.
Studio includes its own scoped styles and shell controls.

### Connect a Jido runtime

To inspect agents, add Jido v3 to the host and start its runtime under the host
supervisor. Pass the runtime's registered name to the Studio mount:

```elixir
jido_studio "/studio", jido: MyApp.Jido
```

Set `partition: "operations"` to view a named Jido partition. By default, the
mount lists unpartitioned instances. The host selects the runtime and partition
in the router.

The Agents page lists resident instances. Open an instance to read its runtime
status and committed snapshot summary. The two panels load and retry
independently. Refresh reads the current data. The snapshot summary shows the
definition, revision, and state field count. State values stay in the runtime.

Open an instance at `/studio/agents/:agent_id` and select **Turn history** to
see recent settled turns. Studio keeps up to 512 turn summaries in memory on
the local node and shows up to 50 for the current running instance. The view
shows signal and trace identifiers, outcome, and commit status. History starts
with the Studio application and applies to the current agent activation.

### Host access

Use the host's HTTP authentication pipeline and pass its LiveView
authentication and policy hooks with `:on_mount`:

```elixir
jido_studio "/studio",
  on_mount: [{MyAppWeb.UserAuth, :ensure_authenticated}, MyAppWeb.StudioPolicy]
```

In the policy hook, use `JidoStudio.Access.put(socket, level)` and return
`{:cont, socket}` with the updated socket. Choose `:read_only`, `:all`, or
`{:forbidden, "/local/path"}` from the authenticated user's role. Studio
defaults to read-only and redirects forbidden users before rendering a
page. Studio handlers must check `JidoStudio.Access.allowed?(socket, :action)`
before they change runtime or stored data.

### Content Security Policy

When the host uses a nonce-based policy, set the nonce in the connection
before Studio renders and use the same nonce in the response CSP:

```elixir
jido_studio "/studio", csp_nonce_assign_key: :csp_nonce
```

Use `%{style: :style_nonce, script: :script_nonce}` if the host uses separate
assigns. The options apply to Studio's assets. The host manages its own
asset policy and socket.

You can mount Studio under a Phoenix path scope. Its navigation keeps the
mount prefix and carries the `runtime` and `node` query values. Use a unique
`:live_session_name` if the same router mounts Studio more than once.

## Run the playground

```sh
cd studio_playground
mix setup
mix phx.server
```

Open [Agents on localhost](http://localhost:4702/studio/agents). The playground
starts a local Jido v3 runtime with three sample instances and loads Studio
from the parent directory.
It enables the [component showcase](http://localhost:4702/studio/components).
Set `showcase: true` to make the same page available in another host.

The previous Studio implementation and tests are in `lib_old/` and
`test_old/`. They are available as references for the rebuild.

## Documentation

See the [documentation index](docs/README.md) for the feature checklist,
visual reference, and v3 decision roadmap.
