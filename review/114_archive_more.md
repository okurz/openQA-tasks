# 114 poo#195560 Archive more important job results when "results" is full but "archive" has space

Ticket: https://progress.opensuse.org/issues/195560 (size:S, In Progress, okurz)

## Motivation

Archiving important job results (`archiving.archive_preserved_important_jobs`,
task `archive_job_results`, `OpenQA::Schema::Result::Jobs::archive`) is today
driven purely by time-based retentions: `JobGroups::limit_results_and_logs`
collects jobs preserved because they are important and enqueues archiving for
exactly those. Free space on the results file system never influences how much
is archived. So when `results` is full while `archive` still has room, results
get deleted although they could have been moved.

## Acceptance criteria

- **A1:** If configured, important job results are archived as far as possible
  to reduce deletions caused by a full `results` file system.
- **A2:** Results are still cleaned up as necessary after the retention period
  expired.

## Chosen approach: upfront archiving in the always-active cleanup path

Two options were considered:

- **(a)** hook archiving into the df-based cleanup
  (`_ensure_results_below_threshold`) via a new
  `archiving_via_min_free_disk_space_cleanup = none|exclusively|additionally`
  setting, as suggested in the ticket.
- **(b)** upfront archiving inside `_limit` (`limit_results_and_logs`), before
  any deletion happens.

**(b) is implemented here.** Reason: `_ensure_results_below_threshold` only
runs when `results_min_free_disk_space_percentage` is set, which is
experimental and not enabled on OSD, so (a) would ship code that is inert on
the instance that motivates the ticket (#203217). `_limit` runs on OSD today.
This also matches mkittler's "upfront archiving before cleaning up any result"
idea (ticket note 2026-02-11, #192967#note-21). The ticket's suggested
`archiving_via_min_free_disk_space_cleanup` setting is therefore **not**
introduced; extending the df-based path stays possible later (#190932).

## Current state (verified in tree)

- `_limit` (`lib/OpenQA/Task/Job/Limit.pm:32`): guards → early return via
  `finish_job_if_disk_usage_below_percentage(result_cleanup_max_free_percentage,
resultdir)` (`:46`) → cleanup of jobs without group (`:56`) → round-robin group
  loop with per-iteration early abort and `archive_job_results` enqueue
  (`:87-106`) → cursor write (`:108`) → screenshot batches →
  `ensure_results_below_threshold` enqueue.
- `_ensure_results_below_threshold` (`:262`) determines important builds across
  all groups (`:304-323`) and deletes in a fixed order via `_delete_results`.
- `check_df($dir)` (`lib/OpenQA/Utils.pm:910`) returns
  `($available_bytes, $total_bytes)` and dies on implausible data.
- `Jobs::archive` (`lib/OpenQA/Schema/Result/Jobs.pm:256`) copies the result dir
  to the archive prefix, sets `archived => 1`, removes the source, returns the
  archived path; it calls `$signal_guard->retry(0)` on the guard passed in.
- `Jobs::num_prefix_dir` (`:1248`) resolves to `resultdir($self->archived)`, so
  `result_dir`, `delete_results` and the retention queries keep working for
  archived jobs — **A2 holds**, archiving earlier does not shield a job from
  later retention-based cleanup.
- Tests: `t/14-grutasks.t:490-560` (archiving enqueued by
  `limit_results_and_logs`), `t/42-df-based-cleanup.t` (`Filesys::Df` mocked,
  `_limit` loop and cursor subtests at `:376+`).
- Config: `[archiving]` in `etc/openqa/openqa.ini:441-445`; docs
  `docs/UsersGuide.md:1660-1735`.

## Design decisions

- **Trigger:** new phase in `_limit`, placed after the
  `result_cleanup_max_free_percentage` early return and **before** the first
  deletion (`:56`). Runs only if `archive_preserved_important_jobs` is enabled
  and free space on `resultdir` is below the new trigger threshold.
- **Candidates:** important, `archived => 0`, final state, oldest id first —
  reusing the important-build conditions from `_ensure_results_below_threshold`.
  Unimportant jobs are never archived (ticket suggestion).
- **Stop conditions**, checked between jobs (never mid-copy):
  1. free space on `resultdir` reached the trigger threshold,
  2. free space on `archivedir` would fall below the archive floor,
  3. per-run wall-clock budget exhausted,
  4. no candidates left.
- **No byte accounting, no cursor.** Free space is re-read with `check_df` per
  iteration (two `statfs` calls, negligible next to a recursive copy) instead of
  estimating from moved bytes — ground truth, tolerant of concurrent writers,
  and `Jobs::archive` needs no signature change. A persistent cursor is not
  needed either: archiving sets `archived => 1`, so each job leaves the
  candidate set permanently and the next run continues with the next-oldest job.
  Progress is durable per job (copy → flag → remove source).
- **Cap dimension:** wall-clock, not job count or bytes — the concern is task
  duration and interruption by `openqa-gru.service` restarts, and copy
  throughput varies by orders of magnitude between result dirs.
- **Signal guard:** do **not** pass `_limit`'s
  `$ensure_task_retry_on_termination_signal_guard` to `Jobs::archive`; it would
  call `retry(0)` on it and thereby disable termination-retry for the whole
  cleanup task after the first archived job.
- **Same-filesystem guard:** if `resultdir` and `archivedir` share a device
  (`stat` `dev`), archiving frees nothing — skip with a `$job->note`.
- **Concurrency:** acquire the per-job Minion guard
  `process_job_results_for_<id>` and skip the job if unavailable, to avoid
  racing an `archive_job_results` task that started before `_limit` took
  `limit_results_and_logs_task`.
- **Errors:** a failing `Jobs::archive` (copy error) is logged and skipped, the
  phase continues with the next job; it must not fail the cleanup task.
- **No dry-run mode** for this phase (`dry_min_free_disk_space_cleanup` belongs
  to the df-based path). Reconsider if operators ask for a preview.

### New settings (`[archiving]`)

```ini
## Archive important job results upfront during cleanup while the free space on
## the results file system is below this percentage (0 disables)
#archive_important_jobs_min_free_percentage = 0
## Stop upfront archiving when the free space on the archive file system would
## drop below this percentage
#archive_keep_free_percentage = 5
## Maximum duration in seconds spent on upfront archiving per cleanup run
## (0 for no limit)
#archive_max_duration = 300
```

Naming is open for review; `archive_keep_free_percentage` in particular must be
documented as distinct from `misc_limits.archive_min_free_disk_space_percentage`
(which controls _deleting from_ the archive in the df-based cleanup).

## Tasks (atomic, one commit each)

### 1. refactor: extract the important-jobs condition builder

- Move `lib/OpenQA/Task/Job/Limit.pm:304-323` into a sub returning the
  important/not-important condition pairs so both
  `_ensure_results_below_threshold` and the new phase use one implementation.
- Keep the `$job->note(important_builds_*)` calls at the caller side or pass the
  Minion job in — no duplicated `important_builds` aggregation.
- No behavior change; covered by the existing `t/42-df-based-cleanup.t`
  subtests. Verify they still pass unmodified.

### 2. feat: add and validate the upfront archiving settings

- Defaults in `lib/OpenQA/Setup.pm` `archiving`:
  `archive_important_jobs_min_free_percentage => 0`,
  `archive_keep_free_percentage => 5`, `archive_max_duration => 300`.
- Commented-out documented entries in `etc/openqa/openqa.ini` `[archiving]`,
  wrapped at 80 characters.
- Validation in `_limit`: reuse `_is_valid_percentage` /
  `_format_percentage_error` (exported or moved alongside the helper from task
  1); invalid values fail the Minion job with a clear message.
- Tests in `t/42-df-based-cleanup.t`: parametrized subtest over invalid values;
  assertion that the defaults leave the current `_limit` behavior unchanged.

### 3. feat: archive important jobs upfront when the results file system is full

- Implement the phase described above in `lib/OpenQA/Task/Job/Limit.pm`,
  including trigger check, same-device guard, candidate query, per-job Minion
  guard, error skipping, the three stop conditions and the time budget.
- Log per job (`Archiving important job <id>`) in the style of the existing
  `Deleting …` messages; record `$job->note(archived_jobs => <count>)` and
  `$job->note(archiving_stopped => <reason>)`.
- Tests in `t/42-df-based-cleanup.t` (df already mocked there), mocking
  `OpenQA::Schema::Result::Jobs::archive` and feeding a queue of `df` values:
  disabled by default; archives oldest important unarchived jobs until the
  results threshold is reached; stops at the archive floor; skips when
  `resultdir` and `archivedir` are on the same device; stops on the time budget;
  continues after an `archive` exception; never archives unimportant or
  already-archived jobs.
- Integration test in `t/14-grutasks.t` next to the existing archiving subtest:
  a _not yet expired_ important job gets archived because the results file
  system is reported as full — this is the actual new behavior — and the job is
  still deleted later once its retention expires (A2).

### 4. doc: document upfront archiving

- `docs/UsersGuide.md` "Archiving": the section currently states archiving only
  happens at the regular-log expiration; extend it with the space-driven
  trigger, the three settings, the stop conditions and the caveat that this only
  helps if the archive is on a separate file system.
- Cross-reference from "Space-aware cleanup" and keep the existing note that
  archiving does not prevent later cleanup.

## Verification (per commit)

- `make tidy` and `make test-checkstyle` before committing.
- `make test-unit-and-integration TESTS=t/42-df-based-cleanup.t` and
  `TESTS=t/14-grutasks.t`.
- `COVERAGE=1 make test-unit-and-integration TESTS=t/42-df-based-cleanup.t`,
  then `cover -report text -select_re 'Task/Job/Limit'` and
  `make check-line-coverage`; full statement coverage of new lines is required.
- `make test-gitlint` after each commit.

## Risks and open questions

- While `_limit` runs it holds `limit_results_and_logs_task`, so concurrent
  `archive_job_results` tasks retry every minute. A long archiving phase
  therefore adds retry churn — bounded by `archive_max_duration`; watch for the
  pileup pattern from #197123. A secondary job-count cap can be added if the
  duration budget proves insufficient.
- Copy-then-delete needs no extra space on `results`, but it does add IO load
  exactly when the file system is under pressure.
- Determining important builds iterates all job groups; only done when the
  trigger threshold is undershot, but it is a heavy query on instances with many
  groups.
- `df` accounting is approximate on btrfs/compressed/sparse storage; the archive
  can overshoot its floor by up to one job.
- Feature is off by default and only effective if the archive is a separate file
  system with free space; enabling it on OSD is a separate infrastructure step.
