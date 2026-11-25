# 178 job_impacts snapshot table, filled on job completion

Theme: `174_job_impact_theme_overview.md`. Depends on: 124 (125 optional;
without it the worker level is skipped).

## Goal

Store an immutable impact record per finished job, with the resolved factors.
Aggregation can then be done in SQL, and history stays stable when an admin
changes a factor. Only new jobs get records (decision: no backfill).

## Commit 1: feat(schema): add job_impacts table

- New file `lib/OpenQA/Schema/Result/JobImpacts.pm`. Columns:
  - `job_id`: PK, FK to jobs, `ON DELETE CASCADE`
  - `seconds` integer
  - `vcpus` real, `ram_gb` real, `power_w` real
  - `energy_kwh` double, `carbon_g` double
  - `cost_energy` double, `cost_hardware` double, `cost_human` double
    (nullable, task 133), `cost_total` double
  - `currency` text
  - `model_version` integer
  - `factors` jsonb: the resolved factors plus their sources
  - `t_created`
- Relationship: `Jobs` `might_have impact => JobImpacts`.
- Bump the schema version (next free number; coordinate with 126) and run
  `./script/upgradedb --prepare_upgrade`.
- Index: `job_id` only, as the PK. Aggregations join on `jobs`
  (`group_id`, `BUILD`, `t_finished`), which are already indexed. Check
  `EXPLAIN` on the queries planned in 131.
- Tests: deploy/upgrade tests stay green, and a minimal create/read in
  `t/10-jobs.t`.

## Commit 2: feat: compute job impact when a job finishes

- `lib/OpenQA/Schema/Result/Jobs.pm`:
  - New method `compute_impact`:
    1. Return early if `job_impact.enabled` is 0, or if `t_started` or
       `t_finished` is missing (a job cancelled before start has no
       hardware cost; store nothing).
    2. Resolve the factors with `OpenQA::JobImpact::resolve_factors`, using
       the config, the class config, the `assigned_worker`
       `job_impact_factors` (task 125, guarded with `can`), and
       `settings_hash`.
    3. Call `assess(...)` and use `update_or_create` on `JobImpacts`.
  - Call it at the end of `done()`, after `t_finished` is set and before the
    restart/retry logic.
  - Wrap it in `eval`: an impact failure must never break job completion.
    Log errors with `log_warning`.
- Performance: one extra INSERT per finished job, which is negligible. Reuse
  the cached `settings_hash`.
- Tests: `t/10-jobs.t` or a new `t/job_impact_db.t`:
  - A finished job gets a record whose values match a direct `assess` call.
  - A disabled config writes no record.
  - A job without `t_started` writes no record.
  - A worker with `JOB_IMPACT_SLOT_POWER_W` overrides the ini value; check
    `factors.sources`.
  - An exception in `assess` (mocked) still lets `done()` complete, with a
    warning logged.
  - Incomplete jobs (e.g. a worker that died) are also recorded, because
    hardware was used.

## Notes

- `result_size`/archiving do not affect the record.
- Cleanup: the FK `ON DELETE CASCADE` removes records together with their
  jobs. No separate cleanup is needed.

## Acceptance

- Every job that finishes after deployment and has a start time has exactly one
  `job_impacts` row.
- `done()` behavior is otherwise unchanged; existing tests are unmodified and
  green.

## Status

Implemented on branch `feature/127_job_impacts_snapshot_table`:

- Commit 1: `24b81ac8c feat(schema): add job_impacts table`
- Commit 2: `50eba5c6c feat: compute job impact when a job finishes`

Verification:

- `make tidy` and `make test-checkstyle` passed cleanly.
- `make test-gitlint` passed across all commits.
- Full statement coverage verified on all new and modified lines.
