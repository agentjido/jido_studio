# Job 2: Mount with Safe Access

## Status

**Hypothesis**

This contract is not a validated customer job. The repository has an access
contract, but it does not yet enforce that contract.

The current code defines `:all`, `:read_only`, and `{:forbidden, path}` in
`JidoStudio.Resolver`. The router puts the resolver and `current_user` in the
LiveView session. The mount hook stores the resolver on the socket. It does not
call `resolve_user/1` or `resolve_access/1`, and current mutation handlers do not
check an access value.

## Priority and Hire Moment

Priority: **2 of 8 — install and activation**.

The Big Hire occurs when a developer is ready to expose the mounted operations
interface inside a host application. The developer must decide who can open it
and who can change runtime state.

The Little Hire occurs on each later page load, LiveView reconnect, and attempted
mutation by an authorized, read-only, or forbidden user.

## Job Statement

> When I add an operational interface to an authenticated application, I want each signed-in person to receive only the access that the host policy allows, so I can expose useful diagnostics without creating an unauthorized control path.

## Successful Outcome

The host application authenticates the person on the HTTP request and LiveView
mount. The resolver maps that person to `:all`, `:read_only`, or
`{:forbidden, path}`. Jido Studio enforces the result in rendered controls and on
the server. A forged LiveView event cannot bypass read-only or forbidden access.

## Job Dimensions

### Functional

Mount the routes behind host authentication and enforce one access result on all
pages and events.

### Emotional

Feel safe that a useful diagnostic page did not also create an unreviewed control
surface.

### Social

Show security reviewers and teammates a small, testable access policy with clear
role behavior.

All three dimensions are hypotheses. Customer research must validate them.

## Forces

- **Push hypothesis:** An internal dashboard without complete server enforcement
  creates an unacceptable production risk.
- **Pull hypothesis:** One host-auth mount example and one three-result resolver
  make the policy easy to understand and test.
- **Anxiety hypothesis:** The developer fears LiveView reconnect bypasses, hidden
  controls that still accept forged events, redirect loops, and future mutations
  that omit a policy check.
- **Habit hypothesis:** The developer relies on network location, a router pipeline
  alone, or a custom admin page that already has application-specific access
  checks.

## Current Alternatives

- Put the interface behind a VPN, private network, or reverse-proxy rule.
- Use only a Phoenix authentication pipeline.
- Build a host-specific LiveView `on_mount` authorization hook.
- **DIY:** Fork the package and add role checks to each event handler and template.
- Use logs, IEx, or a read-only observability service instead of a control page.
- **Non-consumption:** Do not mount the interface in a shared or production
  environment.

## Direct Simple Experience

### Entry Condition

Job 1 is complete. The host application has a browser session, an authentication
pipeline, a LiveView authentication hook, and a current-user assign. The host has
identified which people need full, read-only, and forbidden access.

### User Steps

1. Add a resolver that returns one documented access value:

   ```elixir
   defmodule MyAppWeb.StudioResolver do
     @behaviour JidoStudio.Resolver

     @impl true
     def resolve_user(conn), do: conn.assigns[:current_user]

     @impl true
     def resolve_access(%{role: :admin}), do: :all
     def resolve_access(%{role: :developer}), do: :read_only
     def resolve_access(_user), do: {:forbidden, "/users/log-in"}
   end
   ```

2. Mount the routes behind the host HTTP and LiveView authentication checks:

   ```elixir
   scope "/" do
     pipe_through [:browser, :require_authenticated_user]

     jido_studio "/studio",
       resolver: MyAppWeb.StudioResolver,
       on_mount: [{MyAppWeb.UserAuth, :ensure_authenticated}]
   end
   ```

3. Sign in as an administrator and verify that one controlled interaction can
   change the selected test agent.
4. Sign in as a read-only developer and verify that data is visible, mutation
   controls are not available, and a forced mutation event is denied.
5. Sign out or use a forbidden account and verify that no Studio content renders
   before the host login or forbidden destination appears.

### Completion State

The host has an automated three-access integration test. The administrator can
perform an allowed mutation. The read-only user can inspect data but cannot
change runtime or stored state. The forbidden user cannot see a Studio page.

## Experience Rules

- Host authentication and Studio authorization are separate controls. Both are
  required for the safe mount experience.
- The HTTP pipeline must protect the initial request. A host LiveView hook must
  protect connected mounts and reconnects.
- The configured resolver must receive the user from `resolve_user/1`, then return
  `:all`, `:read_only`, or `{:forbidden, local_path}` from `resolve_access/1`.
- `:all` permits view actions and documented mutations within the selected host
  runtime and node scope.
- `:read_only` permits navigation, search, filters, refresh, row expansion, and
  other socket-local view actions.
- `:read_only` denies actions that start an instance, dispatch a signal or action,
  send chat, change agent debug state, evaluate and store a trace result, or
  create, change, or clear persisted workspace data.
- The server must enforce read-only access. Hiding or disabling a control is only
  a second user cue.
- A read-only page must show a persistent `Read only` cue and explain why a
  mutation is unavailable.
- `{:forbidden, path}` must halt the mount before page data renders and redirect
  only to a valid local host path.
- A missing user, resolver exception, invalid access value, or invalid redirect
  path must deny access. It must never become `:all`.
- One central policy must protect current and future mutation handlers. Extension
  routes must use the same policy or declare a stricter host policy.
- Access checks must keep the current runtime and node scope. A query parameter
  must not increase access.
- Denied-event logs and telemetry must not contain session tokens, provider keys,
  or full user records.

## Failure and Recovery States

| Failure state | User-visible result | Recovery |
| --- | --- | --- |
| The person has no authenticated host session | The host authentication flow redirects before Studio content renders | Sign in through the host application and return to the requested local path |
| The resolver returns `{:forbidden, path}` | The LiveView mount halts and redirects without a content flash | Request the required host role or use an allowed account |
| The resolver raises or returns an unknown value | Access is denied and a safe configuration error is logged | Fix the resolver callback and run the access integration tests |
| A read-only user selects a hidden or forged mutation event | The server rejects the event, shows a read-only message, and does not change state | Ask for the full-access role or continue with inspection actions |
| The LiveView session expires or a reconnect loses authentication | The host hook halts the new mount | Sign in again through the host flow |
| The forbidden path is empty, external, or loops back to Studio | The mount uses a safe local forbidden response and logs the invalid path | Configure a valid host login or forbidden path |
| A new extension has no access declaration | Its mutation surface is unavailable | Add the extension policy and its full/read-only/forbidden tests |

## Acceptance Criteria

- [ ] An unauthenticated HTTP request to every Studio route follows the host login
      flow and does not contain Studio page data.
- [ ] A connected mount and a reconnect both run the host LiveView authentication
      hook.
- [ ] A test resolver proves that `resolve_user/1` receives the request connection
      and that `resolve_access/1` receives its returned user.
- [ ] An `:all` user can view all in-scope pages and complete a representative
      runtime mutation through the UI.
- [ ] A `:read_only` user can navigate and filter all in-scope diagnostic pages and
      sees a persistent read-only cue.
- [ ] A `:read_only` user does not see enabled controls for start, dispatch, chat,
      debug changes, trace evaluation, or persisted workspace changes.
- [ ] Direct LiveView event tests send each protected event as a read-only user and
      prove that runtime state and storage do not change.
- [ ] A forbidden user is redirected to the resolver path before a disconnected or
      connected render exposes Studio content.
- [ ] Resolver exceptions, invalid values, missing users, and invalid redirect
      paths all produce a deny result, never `:all`.
- [ ] Runtime and node query changes do not alter the assigned access value.
- [ ] A policy inventory test fails when a new mutating event or extension route has
      no access classification.
- [ ] Denied access emits a result and reason category for measurement without
      sensitive user or session data.

## Job Metrics

### Big Hire

- Percentage of host applications that complete the three-access integration
  test before they expose the route.
- Median time from first mount edit to a verified safe mount.
- Rate of mounts that use both host HTTP authentication and a connected LiveView
  authentication hook.
- Configuration failure rate for resolver callbacks and redirect paths.

### Little Hire

- Successful mutation rate for `:all` users on allowed test actions.
- Unauthorized state-change rate for `:read_only` and forbidden users. The target
  value is zero.
- Percentage of denied events that leave runtime and stored state unchanged.
- Authentication and authorization result rate on LiveView reconnects.
- Access-related support cases and rollback events after deployment.

Research must set the other target values after it measures a baseline.

## Research Questions

Ask only about past behavior:

- Walk me through the last internal operations page that you mounted in a Phoenix
  application.
- How did the initial request identify the user?
- What happened on the last LiveView reconnect after a session expired?
- Which roles had read access, and which roles changed state?
- Tell me about the last time a read-only user tried a control action.
- Which server checks protected that action, and how did you verify them?
- What access defect or near miss did you investigate most recently?
- What evidence did a security reviewer request before the route was exposed?
- When did you choose not to mount an internal tool because of access risk?
- Which network, proxy, or custom-page alternative did you use instead?

## Evidence Needed

- At least 10 timeline interviews with developers who recently mounted, reviewed,
  restricted, or rejected an internal operations interface.
- The router, authentication hook, role policy, and access tests from those past
  events, with permission.
- Records of denied events, access defects, and security review comments.
- Observed setup time for all three access results.
- Evidence for the emotional and social dimensions from customer words.
- Separate Big Hire and Little Hire access measures.

## Scope Boundaries

In scope:

- Host session authentication at the route and LiveView mount boundaries.
- User resolution and `:all`, `:read_only`, and forbidden enforcement.
- UI cues, server event guards, local redirects, and extension policy coverage.

Out of scope:

- Building the host login system, user database, or organization role model.
- Replacing host data scoping or tenant isolation.
- Immediate revocation inside an already connected socket. The host session and
  LiveView hook own identity freshness.
- Network perimeter controls. They can add protection, but they do not replace
  this contract.
- Installing the dependency and proving the first interaction. Jobs 1 and 3 cover
  those outcomes.

## Research -> Plan -> Implement Cycle Gates

### Research Gate

- Complete at least 10 recent-event timeline interviews.
- Confirm or revise the job statement, all four forces, all three dimensions, and
  all current alternatives.
- Document the mutation classes and access evidence that real host teams used.
- Record separate safe-mount and repeated-access baselines.

### Plan Gate

- Define the central access policy and the full mutation inventory.
- Define how the resolver user and access result move through disconnected mount,
  connected mount, reconnect, render, and event handling.
- Decide the safe behavior for the default resolver and document any migration
  effect.
- Map every planned code, UI, docs, and test change to an acceptance criterion.
- Complete a threat review for forged events, invalid redirects, stale sessions,
  and extensions.

### Implement Gate

- The full, read-only, forbidden, exception, and reconnect integration suites pass.
- Every mutating handler has a server-side access classification and guard.
- The public mount example contains host HTTP and LiveView authentication.
- A security review confirms that forbidden content does not render and read-only
  events do not mutate state.
- Big Hire and Little Hire access measures are available without sensitive user
  data.
- Research participants complete the direct experience before the cycle closes.
