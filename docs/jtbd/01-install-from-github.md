# Job 1: Install from GitHub

## Status

**Hypothesis**

This contract is not a validated customer job. Repository code gives technical
facts, but it does not give customer evidence.

The current checkout has these known conditions:

- GitHub is the intended source. The absence of a Hex package is not a defect.
- `mix.exs` declares version `1.0.0`, but `README.md`, `JidoStudio.version/0`, and
  one version test still use `0.1.0`.
- The current checkout has no Git tag. A branch dependency plus `mix.lock` is the
  current development behavior.

## Priority and Hire Moment

Priority: **1 of 8 — install and activation**.

The Big Hire occurs when a developer decides to add an operations interface to
an existing Phoenix and Jido application. The developer has not yet seen the
interface work in the host application. A failed or unclear install stops all
later jobs.

The Little Hire occurs when the developer restores the application from a clean
clone or updates the dependency to another reviewed source revision.

## Job Statement

> When I need to add an operations interface to an existing Phoenix agent application, I want to install a known and compatible source revision with one clear dependency change, so I can compile the host application and evaluate it without dependency uncertainty.

## Successful Outcome

The host application fetches Jido Studio from the official GitHub repository,
locks one immutable revision, and compiles. The developer can see the declared
package version, the exact Git revision, and the supported host dependency
constraints. No instruction or error suggests that Jido Studio must exist on
Hex.

## Job Dimensions

### Functional

Install one reviewed source revision and resolve it with the host dependencies.

### Emotional

Feel certain that the source, version, and compatibility information agree.

### Social

Show a teammate or reviewer a reproducible dependency change with a clear source
and revision.

All three dimensions are hypotheses. Customer research must validate them.

## Forces

- **Push hypothesis:** Conflicting install text, copied source trees, and manual
  dashboards make the first evaluation slow and uncertain.
- **Pull hypothesis:** One copy-ready GitHub dependency, an immutable revision,
  and a short compatibility table make evaluation easy to review.
- **Anxiety hypothesis:** The developer fears a moving branch, an incorrect
  version, an untrusted repository, or a dependency conflict in the host
  application.
- **Habit hypothesis:** The developer normally uses only Hex dependencies, keeps
  a local path checkout, or delays the evaluation until a package release exists.

## Current Alternatives

- Use `main` with a committed `mix.lock` entry.
- Use a local path dependency during development.
- Use a Git submodule or copy the source into the host repository.
- **DIY:** Build a small Phoenix LiveView page, use IEx, or combine logs and
  telemetry tools.
- Use a different agent operations interface.
- **Non-consumption:** Continue without an operations interface or delay the
  evaluation because the install source is unclear.

## Direct Simple Experience

### Entry Condition

The developer has an existing Phoenix application, Git access to
`agentjido/jido_studio`, and permission to change `mix.exs` and `mix.lock`.

### User Steps

1. Read one compatibility block and compare it with the host application.
2. Add one dependency that uses an existing immutable Git tag or a full commit
   SHA. At this contract revision, the valid immutable form is:

   ```elixir
   {:jido_studio,
    github: "agentjido/jido_studio",
    ref: "6fcd0968b9a949ad8561af19d3e26c73e921e559"}
   ```

3. Run `mix deps.get` and commit the resulting `mix.lock` change.
4. Run `mix compile` and inspect the resolved source revision and declared
   version.

### Completion State

Compilation succeeds. `mix.lock` contains the expected Git revision. The visible
package version is `1.0.0` for this source revision, and the host dependency set
meets the declared constraints.

## Experience Rules

- GitHub is the only Jido Studio distribution source in this contract.
- The primary install example must use an existing immutable tag or a full
  40-character commit SHA.
- `github: "agentjido/jido_studio", branch: "main"` is acceptable for active
  development only when the developer commits `mix.lock`. It is not the target
  production example.
- The product must show package version and source revision as different values.
  A package version must not imply that a Git tag exists.
- `mix.exs` is the source of truth for the declared version and compatibility
  constraints. Public docs, runtime UI, tests, and release metadata must agree
  with it.
- The compatibility block must show these current host constraints:

  | Component | Constraint |
  | --- | --- |
  | Elixir | `~> 1.18` |
  | Jido | `~> 2.3` |
  | Jido AI | `~> 2.2` |
  | Phoenix | `~> 1.7` |
  | Phoenix HTML | `~> 4.0` |
  | Phoenix LiveView | `~> 1.0` |
  | Phoenix PubSub | `~> 2.1` |

- The full dependency solver output remains authoritative for transitive
  dependencies.
- The install page must not show a Hex dependency, a Hex version badge, or a Hex
  package link for Jido Studio.
- An update must be an explicit change to an immutable source reference, followed
  by a reviewed `mix.lock` change.

## Failure and Recovery States

| Failure state | User-visible result | Recovery |
| --- | --- | --- |
| The GitHub repository cannot be reached | `mix deps.get` identifies the Git dependency and the network or access error | Check GitHub access, SSH or HTTPS policy, and proxy settings, then retry |
| The revision does not exist | The fetch names the missing tag or SHA | Copy an existing tag or full SHA from the official repository |
| Host versions do not meet constraints | Mix reports the exact dependency or Elixir conflict | Compare the host versions with the compatibility block and select a supported revision |
| Public version values disagree | The install verification reports each conflicting value | Stop the release and make `mix.exs`, runtime output, docs, and tests use one declared version |
| `main` moves after evaluation | The committed lock still identifies the reviewed commit | Keep the lock or replace the dependency with that full SHA before deployment |
| A developer searches Hex and finds no package | The docs state that GitHub-only delivery is intentional | Return to the GitHub install example; do not report a missing Hex release as a product failure |

## Acceptance Criteria

- [ ] A clean Phoenix fixture can add the documented immutable GitHub dependency,
      run `mix deps.get`, and run `mix compile --warnings-as-errors`.
- [ ] The fixture `mix.lock` records Jido Studio as a Git dependency at the exact
      documented commit, not as a Hex dependency.
- [ ] A second clean checkout with the same `mix.exs` and `mix.lock` resolves the
      same Jido Studio commit.
- [ ] An automated consistency test proves that `JidoStudio.version/0` equals the
      version in `Mix.Project.config()` for the checked-out source.
- [ ] An automated docs check proves that the install and compatibility values
      match the current `mix.exs` constraints.
- [ ] A repository search finds no active Jido Studio Hex install example and no
      public claim that a Hex package is required.
- [ ] A fixture with one unsupported dependency version fails with the name of the
      conflicting component and a link or path to the compatibility block.
- [ ] The install output or verification page shows both the declared package
      version and the full locked Git revision.
- [ ] A branch-based development fixture stays at its locked commit until an
      explicit dependency update occurs.

## Job Metrics

### Big Hire

- Percentage of evaluated host applications that complete `mix deps.get` and
  first compile from the official GitHub source.
- Median time from the first install instruction to a successful compile.
- Percentage of first attempts that use an immutable tag or full SHA.
- Dependency resolution failure rate, grouped by source access, Elixir version,
  and package conflict.

### Little Hire

- Clean-clone compile success rate with the committed lock file.
- Percentage of dependency updates that include an intentional source revision
  and reviewed lock change.
- Version or compatibility support cases per update.
- Rate of builds that resolve a different revision without an explicit update.

Research must set target values after it measures a baseline.

## Research Questions

Ask only about past behavior:

- Tell me about the last GitHub dependency that you added to a Phoenix
  application. What caused you to add it?
- What exact dependency entry did you use, and where did you get it?
- How did you decide which branch, tag, or commit to trust?
- What did you check before you changed `mix.exs`?
- What happened the last time package docs and runtime version text disagreed?
- Which dependency conflict did you see most recently, and how did you recover?
- When did you last commit or omit a Git dependency lock change? What happened
  after that?
- Tell me about a tool that you did not evaluate because it was not on Hex.
- Who reviewed the last source dependency that you added, and what proof did that
  person request?

## Evidence Needed

- At least 10 timeline interviews with developers who recently added, updated, or
  rejected a Git dependency in a Phoenix application.
- The actual `mix.exs` and `mix.lock` changes from those events, with permission.
- Compile logs and support reports for source, version, and compatibility
  failures.
- Time-to-compile observations from clean host fixtures.
- Evidence for the emotional and social dimensions from customer words, not team
  assumptions.
- Separate Big Hire and Little Hire measurements.

## Scope Boundaries

In scope:

- GitHub source identity and an immutable revision.
- The dependency entry, lock behavior, declared version, and compatibility facts.
- First fetch, first compile, clean restore, and explicit update recovery.

Out of scope:

- Publishing Jido Studio to Hex.
- Changing the versions of Jido, Phoenix, or other dependencies.
- General Git or network administration.
- Mounting routes, access control, and the first agent interaction. Jobs 2 and 3
  cover those outcomes.

## Research -> Plan -> Implement Cycle Gates

### Research Gate

- Complete at least 10 recent-event timeline interviews.
- Confirm or revise the job statement, all four forces, all three dimensions, and
  the listed alternatives.
- Record the current Big Hire and Little Hire baselines.
- Identify the source and compatibility facts that developers used in real
  decisions.

### Plan Gate

- Select one canonical immutable install form for the tested revision.
- Define one source of truth for version and compatibility data.
- Map each planned docs, code, and test change to an acceptance criterion.
- Define recovery copy for source access, missing revision, and dependency
  conflict failures.

### Implement Gate

- All automated acceptance tests pass in a clean Phoenix fixture.
- Public docs, runtime output, tests, and project metadata show the same declared
  version and compatibility data.
- The production example uses an existing immutable source reference.
- Big Hire and Little Hire events or build measures are available without storing
  host secrets.
- Research participants complete the direct experience with the implemented
  instructions before the cycle closes.
