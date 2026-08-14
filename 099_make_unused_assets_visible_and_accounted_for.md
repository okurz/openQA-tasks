# 099 — Make unused assets visible and accounted for

Related PR context: os-autoinst/openQA#7654 (feat: Skip download of unnecessary
assets in clone_job). Reviewer (aylen384) suggested moving from an opt-out to an
opt-in asset model, motivated by large vagrant box files. This plan reframes the
underlying problem: assets are attributed to jobs purely by settings-name
pattern matching (inheritance), regardless of whether a test actually uses them.
The goal is to give test maintainers a concrete, attributable motivation to
declare assets only where needed instead of at broad product/medium/machine
levels where every descendant job uselessly inherits them.

## Problem statement

- An asset is tied to a job whenever a setting matching `asset_type_from_setting`
  (`lib/OpenQA/Utils.pm`) exists, via `parse_assets_from_settings` ->
  `register_assets_from_settings` (`lib/OpenQA/Schema/Result/Jobs.pm:1529`).
  Attribution is by _declaration_, not by _use_.
- Settings inherit downward (product/medium/machine/job-template -> job). A broad
  declaration makes every descendant job carry the asset.
- Cost accounting (`size_limit_gb`, `exclusively_kept_asset_size`,
  `lib/OpenQA/Task/Asset/Limit.pm`) is per job group, disconnected from the
  maintainer/level that over-declared the asset.
- There is no signal for "declared but never accessed at runtime". The worker
  (`detect_asset_keys` in `lib/OpenQA/Worker/Engines/isotovideo.pm`) knows which
  assets it hands to a test but does not record whether the test opened them.

## Guiding principle

Incentives change behavior when the cost is (1) measured, (2) attributed to the
decision-maker, and (3) visible without asking. Deliver visibility and
attribution first; only add enforcement (opt-in / warnings) once the data proves
the scale of the problem.

## Atomic tasks

Each task below is independently implementable, testable, and committable. Later
tasks depend on data produced by earlier ones but do not require them to be in
the same commit/PR. Ordering reflects lowest-effort/highest-leverage first.

### Task 1 — Measure declared vs. actually-used vagrant/large assets (data spike)

- **Type**: investigation, read-only; produces a report script, not product code.
- **Goal**: settle the open question "are there any tests still using the vagrant
  box assets, or are they purely stale broad declarations?".
- **Scope**:
  - Add a standalone reporting script (e.g. `script/openqa-asset-usage-report`)
    or a documented SQL query that, for a given asset type/name pattern, lists:
    number of jobs that _declare_ the asset (via `jobs_assets`) vs. number that
    show evidence of _using_ it. Absent a runtime-use signal yet (added in
    Task 3), approximate "use" via last_use_job_id and by cross-referencing the
    declaring inheritance level (Task 2 output) where available.
  - Output CSV/plain text suitable for sharing with test maintainers.
- **Deliverable**: script + short README section under existing docs.
- **Tests**: unit test for the query/aggregation logic against fixtures in
  `t/fixtures/`; assert counts for a declared-but-unused asset and a used asset.
- **Commit**: `feat(script): report declared-vs-used asset counts`.
- **Note**: This is the cheapest first step and may show the vagrant boxes are
  simply removable stale declarations, avoiding larger work.

### Task 2 — Record the inheritance origin of each asset-typed setting

- **Type**: backend, schema/data.
- **Goal**: attribute an asset declaration to the level (product/medium/machine/
  job-template/job) where the setting originates, so cost can later roll up to
  the decision-maker rather than the consuming job group.
- **Scope**:
  - Determine, during settings expansion (`OpenQA::JobSettings` /
    `ScheduledProducts`), the origin level of each asset-typed setting.
  - Persist origin metadata (new column or side table keyed by asset + origin
    level), populated in `register_assets_from_settings`.
  - Keep migration additive and backward-compatible (nullable column / new
    table); no behavior change to scheduling.
- **Deliverable**: DB migration + population logic.
- **Tests**: schema deployment test; unit test asserting origin level is
  captured for a setting declared at product vs. job-template vs. job level.
- **Commit**: `feat(assets): record declaring inheritance level for asset settings`.

### Task 3 — Capture a runtime "asset accessed" signal from the worker

- **Type**: worker + API.
- **Goal**: distinguish declared assets from assets a test actually opened.
- **Scope**:
  - In the worker/cache path (`detect_asset_keys` and the cache service handoff
    in `lib/OpenQA/Worker/Engines/isotovideo.pm`), record which asset files were
    actually provided to and/or accessed by the test.
  - Report this back to the web UI (new API field / job result detail) and
    persist a per-job "used assets" set distinct from the declared
    `jobs_assets`.
  - Be conservative: "provided to the test" is an acceptable first proxy if true
    file-access instrumentation is out of scope; document the chosen definition.
- **Deliverable**: worker instrumentation + API + persistence.
- **Tests**: worker unit test that a provided asset is reported; API test that
  the used-assets set is stored and retrievable; ensure clean test output.
- **Commit**: `feat(worker): report actually-used assets per job`.
- **Depends on**: none strictly; complements Task 2. Can ship before Task 4.

### Task 4 — Surface declared-but-unused assets in the admin/asset UI

- **Type**: web UI + controller.
- **Goal**: make waste visible without maintainers having to ask.
- **Scope**:
  - Extend the assets admin view (`lib/OpenQA/WebAPI/Controller/Admin/`, assets
    table) to show, per asset (and rolled up per declaring level from Task 2):
    declared job count, used job count (from Task 3), size, and a
    "declared-but-unused" flag/percentage.
  - Add filtering/sorting by wasted size so the largest offenders (e.g. vagrant
    boxes) surface first.
- **Deliverable**: controller data + template changes.
- **Tests**: controller/UI test asserting the unused-asset indicator and roll-up
  numbers render for fixture data.
- **Commit**: `feat(webui): show declared-but-unused assets and declaring level`.
- **Depends on**: Task 2 (origin) and Task 3 (usage) for full data; can land a
  reduced version using only Task 3 data first.

### Task 5 — Attribute asset cost to the declaring level in size accounting

- **Type**: backend, asset limit/accounting.
- **Goal**: align "who caused the cost" with "who sees/pays the cost".
- **Scope**:
  - In `lib/OpenQA/Task/Asset/Limit.pm` accounting, augment the existing
    per-group `exclusively_kept_asset_size` with a roll-up attributing wasted
    (declared-but-unused) asset size to the declaring inheritance level from
    Task 2.
  - Expose this in the group/parent property views alongside the existing
    exclusively-kept size.
  - No change to actual cleanup/deletion behavior in this task (reporting only).
- **Deliverable**: accounting roll-up + display value.
- **Tests**: unit test for the roll-up computation with mixed
  used/unused/declared fixtures.
- **Commit**: `feat(assets): attribute wasted asset size to declaring level`.
- **Depends on**: Task 2, Task 3.

### Task 6 — Warn at settings-definition time about broadly-inherited large assets (prevention)

- **Type**: validation / linting.
- **Goal**: nudge maintainers to push asset settings down to only the jobs that
  need them (opt-in at the narrow level rather than opt-out at the broad level).
- **Scope**:
  - Add a validation/report (job-template validation path and/or a periodic
    report) flagging asset settings declared at a broad inheritance level and
    inherited by many jobs, weighted by asset size.
  - Non-blocking warning first; keep enforcement configurable.
- **Deliverable**: validation hook or periodic report + config toggle.
- **Tests**: unit test asserting a broadly-declared large asset triggers a
  warning and a narrowly-declared one does not.
- **Commit**: `feat(validation): warn on broadly-inherited large asset settings`.
- **Depends on**: Task 2 (origin), benefits from Task 1 thresholds.

### Task 7 (optional, gated) — Opt-in download model for clone-job

- **Type**: clone-job UX (the reviewer's original suggestion).
- **Goal**: only revisit the opt-out -> opt-in flip once Tasks 1/3/4 prove the
  scale and provide the data to do it safely.
- **Scope**:
  - Add an opt-in flag to `openqa-clone-job` to download only explicitly named
    asset types/files, keeping current opt-out behavior as the default to avoid
    a breaking change.
  - Consider a type-aware default-skip for known large/rarely-needed categories
    (e.g. vagrant boxes) instead of a wholesale flip.
- **Deliverable**: new clone-job option + docs.
- **Tests**: extend `t/35-script_clone_job.t` for the opt-in flag and the
  type-aware default-skip.
- **Commit**: `feat(clone-job): add opt-in asset selection`.
- **Depends on**: decision informed by Task 1 data; explicitly gated behind
  maintainer agreement because it changes default UX expectations.

## Sequencing summary

1. Task 1 (data spike) — may resolve the vagrant question outright.
2. Task 2 (declaring-level origin) and Task 3 (runtime usage) — the two data
   foundations; independent of each other.
3. Task 4 (UI visibility) and Task 5 (cost attribution) — build on 2 + 3.
4. Task 6 (prevention warnings) — builds on 2.
5. Task 7 (opt-in clone-job) — optional, gated on Task 1 findings and agreement.

## Verification (applies to every task)

- Every code change accompanied by test adaptations/new tests.
- Run targeted tests with `COVERAGE=1 make test-unit-and-integration TESTS=...`
  then `make check-line-coverage` for full statement coverage of changed lines.
- `make tidy` and `make test-checkstyle` must pass before committing.
- DB schema changes: include and verify deployment/migration tests.
- Keep commits atomic per task; conventional-commit messages with Motivation,
  Design Choices, Benefits in the body for feat commits.
