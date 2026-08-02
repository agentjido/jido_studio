# Job 8: Deploy and Upgrade Safely

## Status

**Hypothesis**

No customer interview evidence supports this contract yet.

The shared JTBD contract score is **6/10**, as stated in the JTBD index. Research
must validate the job dimensions, the four forces, the alternatives, and the
separate hire moments.

GitHub-only delivery is an intentional product constraint for this contract. A Hex package is out of scope.

The current repository gives these implementation facts:

- `mix.exs` sets the package version to `1.0.0`.
- `JidoStudio.version/0` and the install examples in `README.md` use `0.1.0`.
- The current local repository has no version tag.
- The README and release workflow still contain Hex package and publish paths.
- `mix.exs` requires Elixir `~> 1.18`, Jido `~> 2.3`, Jido AI `~> 2.2`, Phoenix `~> 1.7`, and Phoenix LiveView `~> 1.0`.
- CI currently runs one Elixir version, `1.19`.
- The default observability adapter is ETS. An optional Ecto adapter uses the migration template in `priv/ecto/migrations`.
- Thread storage can use ETS, a file adapter, or the host Jido storage adapter. Workspace checkpoints have schema version `1`.

These facts are current gaps and constraints. They are not release claims or customer evidence.

## Priority and Hire Moment

Priority: **8 of 8 — scale and lifecycle**. This job follows successful installation, access setup, smoke testing, and core repeated use. It becomes critical before the first production deployment and before every later upgrade.

**Big Hire hypothesis:** A team decides to add the embedded operations tool to a deployed Phoenix application from an exact GitHub source revision.

**Little Hire hypothesis:** For each update, a maintainer decides to move from the current locked commit to a new tag or commit and decides whether to continue or roll back.

## Job Statement

> When I need to add or upgrade an embedded operations tool in a deployed application, I want to select and verify an exact source revision and understand its compatibility and data effects, so I can release it and roll it back without losing access or operational evidence.

## Successful Outcome

The maintainer deploys one immutable Git commit that has accurate version data, tested compatibility, complete upgrade notes, and a known storage plan. The deployed About and Settings pages report the same version and commit as the dependency lock.

The maintainer knows whether the change needs a host migration, which data can disappear, whether mixed versions can run, and how to restore the prior code. A rollback does not destroy stored evidence. If rollback is not safe, the release process blocks before production and states why.

## Job Dimensions

### Functional

The maintainer must select a GitHub tag or commit, verify dependency compatibility, review config and storage changes, run checks, deploy, and use a tested rollback path.

### Emotional

The maintainer wants to feel in control of the change and certain that the version label, migration state, and rollback instructions are true.

### Social

The maintainer wants reviewers and operators to see a careful release record. The maintainer does not want to cause downtime or evidence loss because of an unclear ref or hidden migration.

Customer evidence for all three dimensions is missing.

## Forces

- **Push hypothesis:** A defect, security update, compatibility change, or needed capability makes the current locked commit costly to keep.
- **Pull hypothesis:** An immutable GitHub ref, a verified support matrix, exact version output, clear upgrade notes, and a tested rollback path make the new revision easier to trust.
- **Anxiety hypothesis:** Maintainers fear dependency conflicts, moved tags, mixed node versions, failed mounts, access loss, missing tables, destructive migrations, unreadable old data, and an unsafe downgrade.
- **Habit hypothesis:** Teams keep an old commit, pin a branch, maintain a fork, copy source code, skip migrations, or avoid all upgrades because the current deployment still starts.

All four forces are hypotheses. Research must find them in past behavior.

## Current Alternatives

The following alternatives are hypotheses until interviews and artifacts confirm them.

- **Direct alternative:** A maintainer edits the Git dependency, reads GitHub diffs and release notes, updates `mix.lock`, and uses the host CI and deployment runbook.
- **Indirect alternative:** A maintainer depends on a fork, vendor copy, container image, deployment rollback, or general dependency update service.
- **DIY alternative:** A team keeps a spreadsheet or document with tested commits, writes scripts to compare dependency trees, and maintains custom migration and rollback notes.
- **Non-consumption:** A team stays on the old commit, removes the operations tool from production, uses it only in local development, or waits until an urgent failure forces an update.

## Direct Simple Experience

### Entry Condition

The maintainer has an authorized GitHub repository source, a current locked commit or a first-install target, the host dependency versions, the active storage modes, and access to a non-production environment.

### User Steps

1. Select a signed or protected release tag, or select an exact commit SHA. Record the resolved immutable SHA, release version, source repository, and prior rollback SHA.
2. Compare the current and target revisions. Review the tested compatibility matrix, config changes, route changes, storage changes, required migrations, mixed-version rule, and upgrade notes.
3. Prepare the change. Pin the exact tag or SHA, keep the prior lock state, back up durable data when required, and copy a host migration only when the notes require it.
4. Run dependency resolution, strict compile, tests, migration checks, and the authenticated smoke path in non-production. Confirm that the reported version and commit match the selected source.
5. Deploy and verify runtime access, evidence read and write, and node version agreement. If a stop condition occurs, restore the prior code ref and use the stated storage-safe rollback procedure.

### Completion State

The deployed dependency lock resolves to the recorded commit. All product and release version surfaces agree. Compatibility and migration checks pass. The maintainer stores the upgrade result and can restore the prior code without deleting evidence. If the release cannot continue, the system remains on the known prior revision and gives a clear next action.

## Experience Rules

- Use GitHub as the only delivery source. Do not require a Hex package, Hex registry lookup, or Hex API key.
- Use a release tag or a full commit SHA for production. Treat a branch as an evaluation source, not an immutable production release.
- A tag must resolve to one recorded commit. If the tag target changes, stop the release and show the old and new SHAs.
- Keep one version source in the codebase. Use it for `mix.exs`, `JidoStudio.version/0`, About, Settings, generated documentation, and release metadata.
- Show the exact source commit with the product version. A version string alone is not enough for a GitHub dependency.
- Keep the dependency lock as release evidence.
- Publish a tested compatibility matrix for Elixir, OTP, Phoenix, Phoenix LiveView, Jido, and Jido AI. Do not treat a dependency range as proof that all versions in the range work.
- State whether a rolling deployment with mixed old and new nodes is supported. If it is not supported, require one coordinated version.
- Generate GitHub upgrade notes from Conventional Commit history. Do not require a manual edit to `CHANGELOG.md`.
- Upgrade notes must state breaking config, resolver, router, route, asset, telemetry, persistence, and storage changes.
- Upgrade notes must state the required order for code, config, migrations, and node restarts.
- The package must not edit host config files or run host migrations automatically.
- Label observability ETS as temporary. It has no migration path and loses data on a BEAM restart.
- For Ecto observability, check the required tables before the new code starts to write. State whether the schema is backward-compatible with the prior code.
- Label thread ETS as temporary. Label file storage as restart-safe on its file system. Do not call file storage cluster-shared unless all nodes use the same supported storage.
- Define how each workspace checkpoint schema version reads data from the prior version. Keep an explicit path for unsupported versions.
- Prefer additive database changes. Do not remove or rewrite stored data without an explicit backup, restore, and approval step.
- A code rollback must not require a destructive database rollback. If old code cannot read the new schema, block code rollback and state the safe recovery path.
- Verify the authenticated mount, resolver behavior, one read path, and one safe interaction after deployment.
- Never show a release as complete when the runtime version, Git ref, migration state, or storage state is unknown.

## Failure and Recovery States

| Failure state | User-visible result | Recovery |
|---|---|---|
| Tag or commit does not exist | Name the source and requested ref | Correct the ref or select a known commit |
| Tag resolves to a different SHA than the release record | Show both SHAs and stop | Investigate the moved tag and use a verified immutable SHA |
| Dependency resolution fails | Show the exact conflicting packages and constraints | Select a compatible target or update the host plan before deployment |
| Target is outside the tested matrix | Show `not verified`, not `compatible` | Test that host combination or use a supported combination |
| Version surfaces disagree | Show every conflicting value and stop | Fix the single version source and create a new release ref |
| Upgrade notes are missing or incomplete | Name the missing section | Complete the GitHub release notes before deployment |
| Required Ecto tables or migration are missing | Stop writes and name the missing object | Back up data, copy the migration, run it in the host, and test again |
| Migration fails | Keep the prior code active and preserve the backup | Fix or reverse the safe migration step before code deployment |
| Stored checkpoint schema is not readable | Name the stored and supported schema versions | Use a compatible code ref or run a tested non-destructive conversion |
| Cluster nodes run different unsupported versions | List each node and commit | Complete the coordinated deployment or restore the prior commit on all nodes |
| Authenticated mount or resolver smoke test fails | Mark the release unhealthy | Restore the prior code ref and verify access before the next attempt |
| Code rollback cannot read the new storage schema | Block automatic rollback | Keep compatible code active, restore a backup in a controlled process, or deploy a forward fix |
| Temporary ETS evidence disappears during restart | State that the loss was expected for this mode | Use durable storage before the next release when evidence retention is required |

## Acceptance Criteria

- Given the install documentation, when a maintainer follows the production path, then it uses a GitHub tag or full commit SHA and does not use a Hex version requirement.
- Given the release workflow without a Hex API key, when a GitHub release runs, then it can complete all required GitHub-only release steps.
- Given a production dependency that uses a branch, when release validation runs, then it warns that the source is mutable and requires an immutable tag or SHA.
- Given a tag, when validation resolves it, then the release record, dependency lock, and deployed runtime show the same full commit SHA.
- Given a target release, when version checks run, then `mix.exs`, `JidoStudio.version/0`, About, Settings, documentation metadata, and the GitHub release tag show one version.
- Given each supported Elixir, OTP, Phoenix, Phoenix LiveView, Jido, and Jido AI combination, when CI runs the stated matrix, then strict compile and tests pass.
- Given a combination that has not passed the matrix, when the maintainer reviews compatibility, then the experience labels it `not verified`.
- Given an upgrade with no storage change, when the maintainer reviews the notes, then the notes explicitly say that no migration is required.
- Given observability ETS or thread ETS, when upgrade checks run, then they warn that a restart removes temporary evidence.
- Given file thread storage, when the new revision starts on the same file system, then it reads the prior supported checkpoint schema and retains stored threads.
- Given the Ecto adapter, when the target needs a migration, then tests cover pre-migration detection, migration success, read and write after migration, and prior-code behavior against the new schema.
- Given an unsupported mixed-version cluster, when nodes report different commits, then health stays incomplete and the release cannot report success.
- Given the authenticated smoke path, when the new revision is deployed, then an approved user can open the mounted route, pass the resolver, read stored evidence, and complete one safe interaction.
- Given a failure after deployment, when the prior code is storage-compatible, then the maintainer can restore the prior ref and lock without deleting stored evidence.
- Given an unsafe schema downgrade, when rollback validation runs, then it blocks the code rollback before production and gives the backup restore or forward-fix path.
- Given GitHub release notes, when a reviewer checks them, then they include compatibility, breaking changes, config, routes, storage, migrations, deployment order, mixed-version support, smoke checks, and rollback.

## Job Metrics

### Big Hire

- **Hypothesis:** Percentage of first production installs that use a verified immutable GitHub tag or full SHA.
- **Hypothesis:** Median time from source selection to the first verified production deployment.
- **Hypothesis:** Percentage of candidate installs that stop because compatibility, access, or storage requirements are unclear.
- **Hypothesis:** Main reasons that teams choose a fork, local-only use, or non-consumption instead of the GitHub source.

### Little Hire

- **Hypothesis:** Percentage of started upgrades that finish with matching version and commit data on all nodes.
- **Hypothesis:** Median time from upgrade start to successful smoke verification.
- **Hypothesis:** Percentage of compatibility and migration problems found before production.
- **Hypothesis:** Upgrade failure rate by ref type, dependency conflict, storage mode, and migration state.
- **Hypothesis:** Percentage and median time of storage-safe rollbacks.
- **Hypothesis:** Count of version-report mismatches and moved-tag detections.
- **Hypothesis:** Rate of evidence loss during upgrades, split by temporary and durable storage.

Do not use download counts or release page views alone as proof that this job is complete.

## Research Questions

- Tell me about the last time you added a Git dependency to a deployed Elixir application.
- Which ref did you select, and what made you select it?
- What did you record about the resolved commit before deployment?
- Tell me about the last upgrade of an embedded developer or operations tool.
- What event started that upgrade, and what did you do first?
- Which compatibility information did you check, and where did you find it?
- Tell me about the last dependency conflict that stopped or delayed an upgrade.
- How did you decide whether to change the host dependency or the target ref?
- Tell me about the last upgrade that changed stored data or required a migration.
- What backup did you create, and how did you verify it?
- Tell me about the last deployment that reported the wrong version or an unclear source revision.
- How did that version uncertainty affect diagnosis or rollback?
- Tell me about the last rollback. What failed, which ref did you restore, and what happened to stored data?
- Tell me about a past upgrade that you postponed or did not start. What did you use or do instead?
- Which parts of the last release notes changed your deployment plan?

Ask follow-up questions about exact commits, tags, files, commands, times, people, and outcomes. Do not ask about future intent.

## Evidence Needed

- At least 10 timeline interviews with maintainers who recently installed, upgraded, postponed, or rolled back a Git dependency in a deployed Elixir application.
- Evidence from first installs, routine upgrades, urgent fixes, failed upgrades, and non-consumption.
- Sanitized `mix.exs`, `mix.lock`, CI logs, release notes, deployment records, migration plans, backup checks, smoke results, and rollback records.
- Past examples of tag selection, SHA selection, branch pinning, forks, and moved or missing refs.
- Baseline time and failure data for dependency resolution, compatibility review, migration, deploy, verification, and rollback.
- Repository checks that reconcile all version surfaces and the selected source commit.
- A tested support matrix that covers every claimed Elixir, OTP, Phoenix, Phoenix LiveView, Jido, and Jido AI combination.
- Upgrade and rollback tests for observability ETS, observability Ecto, thread ETS, thread file storage, and inherited host storage.
- Security and operations review evidence for release permissions, access control, backup, migration, and rollback.

## Scope Boundaries

### In Scope

- GitHub repository, tag, commit, and lock selection.
- Accurate version and source-commit reporting.
- Compatibility claims and their test evidence.
- GitHub upgrade notes from Conventional Commit history.
- Host-owned config and migration instructions.
- Temporary and durable storage upgrade behavior.
- Deployment smoke checks, mixed-version rules, and storage-safe rollback.

### Out of Scope

- Hex packaging, Hex publishing, Hex credentials, and Hex version selection.
- Automatic edits to host `mix.exs`, config, router, release files, or migrations.
- Automatic production deployment, database backup, or database restore.
- Management of the host CI system, infrastructure, or cluster rollout.
- Destructive data conversion without a separate approved migration plan.
- A guarantee for dependency combinations that the support matrix did not test.
- General incident coordination, which belongs to the prior job.

## Research -> Plan -> Implement Cycle Gates

### Research Gate

- Complete at least 10 interviews about recent past install, upgrade, delay, and rollback behavior.
- Reconstruct each timeline from the first trigger through source selection, verification, deploy, and outcome.
- Find evidence for all three job dimensions and all four forces.
- Confirm direct, indirect, DIY, and non-consumption alternatives with artifacts.
- Record separate evidence for the Big Hire and each repeated Little Hire.
- Measure the current upgrade time, pre-production detection rate, rollback time, and evidence-loss rate.

The gate fails if the team has only preference surveys, planned behavior, or unverified release assumptions.

### Plan Gate

- Update this contract with supported findings and keep unsupported items as hypotheses.
- Define the GitHub tag and SHA policy, tag protection, and release permission model.
- Define one version source and every generated version surface.
- Define the tested compatibility matrix and its CI cost.
- Define the storage upgrade table for ETS, Ecto, file, and inherited host adapters.
- Define migration order, mixed-version behavior, stop conditions, backup checks, and rollback for each storage change.
- Map every planned change to an acceptance criterion and a job metric.

The gate fails if the plan depends on Hex, permits an unknown source commit, or allows a destructive rollback without an approved restore path.

### Implement Gate

- Build the five-step GitHub-only path and all listed recovery states.
- Remove Hex requirements from the supported install and release path.
- Add automated checks for immutable refs, version agreement, release-note sections, and source-commit reporting.
- Run the full claimed compatibility matrix with strict compile and tests.
- Run upgrade and rollback tests for all supported storage modes and checkpoint schema versions.
- Run a GitHub release dry run without Hex credentials.
- Pilot one first install, one normal upgrade, one migration upgrade, and one failed-upgrade rollback in non-production.
- Compare completion time and failure rate with the recorded current alternative.
- Record the result and update this contract before another release cycle starts.

The gate passes only when a maintainer can identify the exact deployed commit, verify compatibility and storage state, and restore the prior safe revision without evidence loss.
