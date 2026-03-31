# 060 — Add "Why is my test not executed?" to the webUI

**Ticket:** https://progress.opensuse.org/issues/198647
**Sibling ticket:** https://progress.opensuse.org/issues/198644 (scheduler status file)
**PR context:** https://github.com/os-autoinst/openQA/pull/7174#discussion_r2983400695

## Summary

Surface scheduler skip reasons in the `/tests` page so users can understand
why their jobs remain in `scheduled` state. Use the existing `reason` column
in the `jobs` table to store per-job scheduling skip reasons, and display
them as tooltips in the scheduled jobs table and via a "Why is my test not
executed?" indicator next to the heading.

## Background

### Current state

The scheduler (`OpenQA::Scheduler::Model::Jobs`) already logs all skip
reasons via `log_debug` but none of this information is visible in the UI.
The only scheduling-related indicators currently shown on `/tests` are:

| Indicator                    | Where             | How                                                                                          |
| ---------------------------- | ----------------- | -------------------------------------------------------------------------------------------- |
| `(limited by server config)` | Running heading   | `list_running_ajax` includes `max_running_jobs` when limit is hit; JS appends text to `<h2>` |
| Storage warning banner       | Scheduled section | `list_scheduled_ajax` includes `job_skipped_by_disk_limits`; JS toggles a `d-none` alert div |

Both are reactive per-request checks in the WebUI controller. The PR
discussion concluded that the **scheduler** should own these checks and
persist its state for the WebUI to read.

### The `reason` column

The `jobs` table has a `reason` column (`varchar`, nullable, no index). It
is currently only written during `done()` or `cancel()` transitions and is
always `NULL` for jobs in `scheduled` or `assigned` state. No code ever
reads it for scheduled jobs. This makes it a natural fit for storing
per-job scheduling skip reasons without any schema migration. The value is
automatically overwritten when the job eventually finishes or is cancelled.

Key code references:

- Column definition: `lib/OpenQA/Schema/Result/Jobs.pm:80-83`
- `done()` sets reason: `lib/OpenQA/Schema/Result/Jobs.pm:2203`
- `cancel()` sets reason: `lib/OpenQA/Schema/Result/Jobs.pm:2213`
- `_compute_result_and_reason()` checks `!$self->reason` before overwriting:
  `lib/OpenQA/Schema/Result/Jobs.pm:2197` — a stale scheduling reason is
  safely replaced when the job transitions.
- `to_hash()` already includes `reason` when set:
  `lib/OpenQA/Schema/Result/Jobs.pm:479-481`

### Design decision: `reason` column vs. state file

A JSON state file (`scheduler-status.json`) was originally considered per
the PR#7174 discussion. After analysis, the `reason` column is preferred:

| Criterion           | State file                                    | `reason` column                         |
| ------------------- | --------------------------------------------- | --------------------------------------- |
| Per-job granularity | No — only global/aggregate reasons            | Yes — each job gets its own explanation |
| New infrastructure  | Yes — atomic file writes, staleness logic     | No — uses existing DB column            |
| Staleness risk      | Yes — file can become stale if scheduler dies | No — DB is the shared state             |
| API compatibility   | Needs new response keys                       | `to_hash()` already includes `reason`   |
| Write load concern  | N/A (single file)                             | Mitigated by write-on-change strategy   |

The sibling ticket #198644 envisioned a scheduler status file. This plan
proposes closing that ticket as "won't fix" or converting it to a
"scheduler sets `reason` on scheduled jobs" scope, since the `reason`
column approach achieves the same goal more simply.

### All scheduler skip conditions (from `Model/Jobs.pm`)

| #   | Condition                                      | Log message pattern                                                                | Scope       | Reason text for `reason` column            |
| --- | ---------------------------------------------- | ---------------------------------------------------------------------------------- | ----------- | ------------------------------------------ |
| 1   | Disk space below threshold                     | `Skipping job scheduling: free storage space in results directory below threshold` | Global      | `storage space below threshold`            |
| 2   | `max_running_jobs` exceeded                    | `max_running_jobs ($limit) exceeded, scheduling no additional jobs`                | Global      | `max_running_jobs limit reached`           |
| 3   | `MAX_JOB_ALLOCATION` / limit reached           | `limit reached, scheduling no additional jobs (max_running_jobs=…)`                | Global      | `scheduling limit reached`                 |
| 4   | No free workers for worker class               | `Skipping %d jobs because of no free workers for requested worker classes (%s)`    | Per-class   | `no free workers for class <X>`            |
| 5   | Parallel dependencies not ready                | `Skipping job $id because dependent jobs are not ready`                            | Per-job     | `parallel dependencies not ready`          |
| 6   | Incomplete parallel cluster                    | `Discarding job $id … due to incomplete parallel cluster`                          | Per-cluster | `incomplete parallel cluster`              |
| 7   | `PARALLEL_ONE_HOST_ONLY` constraint            | `Cannot assign job $id on $worker, cluster already runs on host $host`             | Per-job     | _(defer to later iteration)_               |
| 8   | Blocked by parent (`blocked_by_id`)            | _(SQL filter, no log)_                                                             | Per-job     | _(already visible via `blocked_by_id`)_    |
| 9   | Waiting on Gru task                            | _(SQL filter, no log)_                                                             | Per-job     | _(already excluded from scheduling query)_ |
| 10  | All workers dead/broken/busy/wrong API version | _(worker filter, no log)_                                                          | Global      | `no workers online`                        |
| 11  | Job scheduled > `max_job_scheduled_time` days  | _(cancelled as OBSOLETED)_                                                         | Per-job     | _(job is cancelled, not scheduled)_        |

Initial scope covers conditions #1–#6 and #10. Conditions #7–#9 and #11
are either already visible through other mechanisms or deferred.

## Design

### Scheduler sets `reason` on scheduled jobs

During each scheduling tick in `_allocate_jobs()`, the scheduler already
determines why each job cannot be assigned. Instead of only logging these
reasons, the scheduler also updates the `reason` column on affected jobs.

**Write-on-change strategy:** The scheduler's in-memory `scheduled_jobs`
hash (which persists across ticks) stores the last-written reason per job.
A DB update is only issued when the reason changes, avoiding unnecessary
write traffic. When a reason is cleared (job can now be scheduled but no
worker is available yet for a different reason, or the job gets assigned),
the column is set back to `NULL`.

**Reason lifecycle:**

1. Job is created → `reason = NULL`
2. Scheduler tick determines skip reason → `reason = 'no free workers for class qemu_x86_64'`
3. Subsequent ticks with same reason → no DB write (cached in memory)
4. Reason changes → `reason` updated to new value
5. Job is assigned to worker → `reason = NULL` (cleared during assignment)
6. Job finishes → `done()` sets `reason` to the completion reason,
   overwriting any residual value

### WebUI display

Two complementary indicators:

1. **Per-job tooltip:** Each scheduled job row shows the `reason` as a
   tooltip on the status icon (using the existing `title` attribute
   pattern already used for running/done jobs).
2. **Heading-level indicator:** A `help_popover`-style `?` icon next to
   the "Scheduled jobs" heading that aggregates the distinct reasons
   across all currently displayed scheduled jobs (e.g., "15 jobs: no free
   workers for class qemu_x86_64, 3 jobs: parallel dependencies not
   ready"). Built client-side from the per-job `reason` values already
   in the DataTable data.

## Execution Plan

### Step 1 — Scheduler sets `reason` on scheduled jobs

**Files to modify:**

- `lib/OpenQA/Scheduler/Model/Jobs.pm`

**Implementation details:**

1. Track a `last_reason` key in the `scheduled_jobs` hash entries
   (already persisted across ticks via `$self->scheduled_jobs`).
2. In `_allocate_jobs()`, after each skip decision, compute a short
   reason string for the affected job(s):
   - Lines 53–55 (disk space): set reason on **all** scheduled jobs.
   - Lines 57–59 (max_running_jobs): set reason on all scheduled jobs.
   - Lines 65–68 (worker class mismatch): set reason on jobs removed
     from `$scheduled_jobs` due to no matching workers.
   - Lines 91–93 (parallel deps not ready): set reason on the skipped job.
   - Lines 110–121 (incomplete parallel cluster): set reason on all
     jobs in the discarded cluster.
   - Lines 135–139 (allocation limit): set reason on remaining unallocated
     jobs.
3. After `_allocate_jobs()` returns in `schedule()`, issue a batched
   DB update for all jobs whose reason changed since the last tick.
   Use `UPDATE jobs SET reason = ? WHERE id IN (?)` grouped by reason
   string for efficiency (one query per distinct reason, not per job).
4. For jobs that were allocated (will be assigned), clear `reason` to
   `NULL` if it was previously set.
5. When no free workers exist at all (condition #10), set a global
   reason on all scheduled jobs before returning early.
6. Keep existing `log_debug` calls unchanged.

**Write-on-change logic:**

```perl
# In the scheduled_jobs hash entry:
# $info->{last_reason} = previously written reason (undef if NULL)
# $info->{current_reason} = reason computed this tick
# Only update DB when last_reason ne current_reason
```

**Testing:**

- `t/05-scheduler-full.t` — verify `reason` is set on jobs for each skip
  scenario. Mock `check_df` / workers to trigger each condition. Verify
  `reason` is cleared when the condition resolves. Verify no redundant
  DB writes (mock `update` and count calls across multiple ticks with
  stable reasons).

### Step 2 — Clear `reason` on job assignment

**Files to modify:**

- `lib/OpenQA/Scheduler/Model/Jobs.pm`

**Implementation details:**

1. In `_assign_multiple_jobs_to_worker()` (line 521), when updating
   job state for assignment, include `reason => undef` to clear any
   scheduling reason.
2. In `reschedule_state()` (`Jobs.pm:326`), also clear `reason` when
   a job is rescheduled (e.g., after a failed assignment attempt).

**Testing:**

- `t/05-scheduler-full.t` — verify that after a job is assigned, its
  `reason` is `NULL`. Verify that after `reschedule_state()`, `reason`
  is `NULL`.

### Step 3 — Display `reason` in the scheduled jobs table

**Files to modify:**

- `lib/OpenQA/WebAPI/Controller/Test.pm` — in `list_scheduled_ajax`,
  add `reason` to the selected columns and include it in the response
  hash for each job.
- `assets/javascripts/tests.js` — in the scheduled jobs DataTable
  rendering, show `reason` as a `title` attribute on the status icon
  (consistent with how running/done job statuses use tooltips).

**Implementation details:**

1. In `list_scheduled_ajax` (line 352), add `reason` to the column list.
2. In the response hash construction (line 364–381), add
   `reason => $job->reason` (or omit if `NULL` to keep response lean).
3. In `tests.js`, when rendering the status column for scheduled jobs,
   set `title` to `row.reason` if present. Example:
   `title="Scheduled: no free workers for class qemu_x86_64"`.
4. Preserve backward compatibility: keep `job_skipped_by_disk_limits`
   in the AJAX response for now (derived from whether any job has a
   `storage space below threshold` reason). The existing
   `#scheduled_jobs_warning` alert continues to work.

**Testing:**

- `t/ui/01-list.t` — verify that scheduled jobs with a `reason` set
  display the reason as a tooltip. Verify jobs without a reason show
  the default "Scheduled" tooltip.

### Step 4 — "Why is my test not executed?" heading indicator

**Files to modify:**

- `templates/webapi/test/list.html.ep` — add a `help_popover`-style
  icon next to `#scheduled_jobs_heading`.
- `assets/javascripts/tests.js` — after DataTable data loads, aggregate
  distinct `reason` values from all rows and populate the popover
  content.

**Implementation details:**

1. Use the existing `help_popover` helper from
   `lib/OpenQA/WebAPI/Plugin/Helpers.pm:150` for the icon markup.
   Label: "Why is my test not executed?".
2. After `dataSrc` processes the scheduled jobs AJAX response, count
   jobs per distinct `reason` and build an HTML summary:
   ```html
   <ul>
     <li>15 jobs: no free workers for class qemu_x86_64</li>
     <li>3 jobs: parallel dependencies not ready</li>
   </ul>
   ```
3. Update popover content dynamically via
   `$().attr('data-bs-content', html).popover('update')`.
4. If no jobs have a `reason`, show "No scheduling issues detected".
5. If all jobs have the same global reason (e.g., storage limit), show
   it as a single line without per-job count.

**Testing:**

- `t/ui/01-list.t` — Selenium test: verify the popover icon appears,
  verify clicking it shows aggregated reason text. Verify with mixed
  reasons across jobs. Verify empty state message.

### Step 5 — Remove direct `df` call from WebUI (optional cleanup)

**Files to modify:**

- `lib/OpenQA/WebAPI/Controller/Test.pm` — remove the
  `results_storage_above_threshold()` call from `list_scheduled_ajax`.
  Replace with checking whether any scheduled job has a storage-related
  `reason` (already available from the DB query in Step 3).
- `lib/OpenQA/Utils.pm` — keep `results_storage_above_threshold()` for
  the scheduler's use but remove WebUI controller imports.

**Note:** This step can be deferred. The `df` call is benchmarked at
~0.04ms and is not a bottleneck. The primary motivation is architectural
cleanliness (scheduler owns the decision, WebUI reflects it).

**Testing:**

- Verify no test regression. Existing tests adapted in Steps 3–4
  cover the new code path.

### Step 6 — Final validation

**Validation checklist:**

- [ ] `make tidy` passes
- [ ] `make test-checkstyle` passes
- [ ] `make test-unit-and-integration TESTS=t/05-scheduler-full.t` passes
- [ ] `make test-unit-and-integration TESTS=t/ui/01-list.t` passes
- [ ] Manual verification on a dev instance with `max_running_jobs=2`
      and `results_min_free_disk_space_percentage=99` to trigger both
      conditions simultaneously
- [ ] Verify `reason` is cleared when a job gets assigned
- [ ] Verify `reason` is overwritten correctly when job finishes
      (no stale scheduling reason leaks into done state)

## Dependency Graph

```
Step 1 (scheduler sets reason)
  └── Step 2 (clear reason on assignment)
        └── Step 3 (display reason in table)
              └── Step 4 (heading popover)
                    └── Step 5 (remove df call — optional)
                          └── Step 6 (validation)
```

Steps 1–2 are the backend foundation (could be one PR).
Steps 3–4 are the UI deliverable (second PR).
Step 5 is optional cleanup (can be a follow-up).

## Risks and Mitigations

| Risk                                                         | Mitigation                                                                                                                                                           |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DB write load from updating `reason` on many jobs every tick | Write-on-change: only update when reason differs from last tick. Batch by reason string (one UPDATE per distinct reason, not per job).                               |
| Stale `reason` leaks into done/cancelled state               | `_compute_result_and_reason()` already checks `!$self->reason` and overwrites. `cancel()` always sets `reason` explicitly. Safe by existing design.                  |
| Scheduler crash leaves stale reasons on scheduled jobs       | Acceptable: reasons remain until next scheduler tick or job completion. No worse than current state (no reason shown at all).                                        |
| Breaking existing `job_skipped_by_disk_limits` consumers     | Preserve the key during transition by deriving it from per-job reasons in the AJAX response.                                                                         |
| `reason` column has no length limit at DB level              | Scheduler-set reasons are short static strings (< 100 chars). The existing 300-char truncation in `done()` does not apply here but the strings are inherently short. |
| Concurrent scheduler instances (multi-webUI setups)          | Each scheduler independently updates jobs it manages. No conflict since each job belongs to one instance.                                                            |

## Out of Scope

- `PARALLEL_ONE_HOST_ONLY` reason (#7) — complex to surface clearly,
  defer to later iteration.
- Blocked-by-parent (#8) and Gru-dependency (#9) reasons — already
  visible through `blocked_by_id` and not processed by the scheduler's
  `_allocate_jobs` at all (filtered out in SQL). Could be set during
  job creation or state transitions in the future.
- Real-time WebSocket push of scheduler status — over-engineering for
  this use case; DataTable AJAX polling is sufficient.
- Scheduler status API endpoint — the per-job `reason` is already
  exposed via `to_hash()` / `/api/v1/jobs/:id`. An aggregate endpoint
  could be added later if needed.
