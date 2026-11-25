# 176 Worker-reported impact factors

Theme: `174_job_impact_theme_overview.md`. Depends on: 124.

## Goal

Let admins of worker hosts declare the real per-slot power and cost in
`workers.ini`, either globally or per `[class:X]`. A worker host knows its own
hardware better than the central web UI config does.

## Commit 1: feat(worker): report JOB*IMPACT*\* settings as capabilities

- `lib/OpenQA/Worker.pm` `capabilities()`:
  - Copy all `JOB_IMPACT_*` keys from `$global_settings` into the capabilities
    hash, using lowercase keys as the existing capabilities do, e.g.
    `job_impact_slot_power_w`.
  - Accept only numeric values. Log a warning for others and skip them.
  - `Settings.pm` already merges `[class:X]`, so no change is needed there.
    Verify this in a test.
- `lib/OpenQA/WebAPI/Controller/API/V1/Worker.pm`:
  - Validate the optional `job_impact_*` params as numbers >= 0.
  - `update_caps` already stores unknown capabilities with
    `set_property(uc ...)`. Confirm that unknown keys are not rejected, and
    widen the allow-list if one exists.
- `etc/openqa/workers.ini`: add commented examples:
  - `JOB_IMPACT_SLOT_POWER_W = 150` under `[global]`
  - `JOB_IMPACT_HW_EUR_PER_SLOT_HOUR` under `[class:qemu_x86_64]`
- Tests:
  - `t/24-worker-overall.t`: capabilities include the configured
    `job_impact_*` keys, non-numeric values are skipped with a warning, and
    class sections are honored.
  - `t/api/04-workers.t` (or the existing worker API test): registration with
    impact capabilities stores `JOB_IMPACT_*` worker properties; a negative
    value returns 400.

## Commit 2: feat(webui): show impact factors on the admin worker page

- `templates/webapi/admin/workers/show.html.ep` (or the existing worker detail
  template): list the `JOB_IMPACT_*` properties in the properties table.
  They likely appear already because properties are rendered generically. If
  so, only add a tooltip that links to `docs/JobImpact.md`, and skip this
  commit if nothing needs to change.
- Tests: `t/ui/12-admin-workers.t` checks that the property is visible.

## Commit 3: feat: honor worker-reported factors in factor resolution

- Add a helper `OpenQA::Schema::Result::Workers::job_impact_factors`:
  - Returns `{slot_power_w => ..., ...}` from the properties.
  - Uses a single query over `worker_properties` with `key LIKE 'JOB_IMPACT_%'`.
- Task 127 passes the helper's result to `OpenQA::JobImpact::resolve_factors`
  as `worker_props`. This commit adds only the helper and its tests in
  `t/10-jobs.t` or a new `t/job_impact_worker.t`.

## Edge cases

- If the worker is unregistered or deleted when the job finishes, factor
  resolution skips the worker level and records `source = ini`.
- The worker might change its factors between job start and finish. Use the
  properties at completion time, which is acceptable for estimates, and
  document this.

## Acceptance

- All new and modified lines are covered.
- Worker registration with or without the new keys is backwards compatible:
  old workers keep working.

## Status

Implemented on branch `feature/125_job_impact_worker_factors`:

- Commit 1: `9f2a4267f feat(worker): report JOB_IMPACT_* capabilities`
- Commit 2: `ddca51e2c feat(webui): show impact factors on admin worker`
- Commit 3: `1e5bea3a3 feat: honor worker-reported impact factors`

Verification:

- `make tidy` and `make test-checkstyle` passed cleanly.
- `make test-gitlint` passed across all commits.
- Full statement coverage on all new lines.
