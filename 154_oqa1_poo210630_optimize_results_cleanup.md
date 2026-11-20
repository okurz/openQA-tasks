# 154 oqa1: Optimize Results Cleanup Performance

Context: openQA results and logs cleanup runtime optimization on https://openqa.suse.de/
Ticket: poo#210630 (oqa1)
Branch: `feature/154_oqa1_poo210630_optimize_results_cleanup` (branched from
`origin/master` at `1f7748a4d`), worktree `~/local/os-autoinst/oqa-154-cleanup`
Numbering: Prefix `154`; builds on investigation in poo#210483 and poo#197483.

---

## Status (2026-11-20)

Plan Tasks 1–3 plus one reviewer suggestion are implemented in three commits.
The commit messages were rewritten on 2026-11-20 to carry the measured numbers
below; the tree is unchanged by that rewrite (`git diff` against
`backup/154-msgs-20261120` is empty).

| Plan item from v1                                                      | Commit      | State                   |
| :--------------------------------------------------------------------- | :---------- | :---------------------- |
| T1 filter already-deleted results + early return in `delete_results`   | `2bd5ed5cb` | done                    |
| T1 tests (also API semantics, review S2)                               | `2bd5ed5cb` | done                    |
| T2 fast screenshot-link guard                                          | `cd48c3b49` | done                    |
| T3 skip redundant `UPDATE jobs` (+ review S1 `delete_logs` accounting) | `cd48c3b49` | done                    |
| Review extra: `result_size` filter in df-based emergency cleanup       | `ba3d88a93` | done                    |
| T4 fast directory removal                                              | —           | open, see Task 6        |
| T5 bulk/batched DB operations                                          | —           | open, see Task 7        |
| T6 parallelize group cleanup                                           | —           | open, see Task 8        |
| T7 docs + validation                                                   | —           | open, see Tasks 5 and 9 |

Notable correction to v1: `t/01-jobs.t` does not exist; the tests live in
`t/10-jobs-results.t`. v1 also listed the df-based `result_size` filter only as
a reviewer nit; it became its own commit.

---

## Problem Statement

The `limit_results_and_logs` Minion task on OSD takes ~24–25.5 hours per run
(observed: 1d00h02m, 1d00h06m, 1d01h28m). Profiling worker PID 2831356 and
PostgreSQL backend 2831358 during job 25565101 identified:

1. **Phantom job loop**: `find_jobs_with_expired_results` selected every job
   past `keep_results_in_days`, including jobs already cleaned, so ~85% of the
   daily candidates were re-processed forever. `find_jobs_with_expired_logs`
   already filtered on `logs_present`.
2. **Parallel-query penalty**: the exclusive-screenshot anti-join on
   `screenshot_links` (438M rows, 38 GB) spawns 2 parallel workers and costs
   ~42 ms even when the job has no links at all.
3. **Redundant writes**: one no-op `UPDATE jobs` per already-cleaned job per
   run, i.e. ~1.19M dead row versions per day on a 13 GB table.
4. **Per-inode filesystem work**: `list_tree` plus `stat`/`unlink` per file
   before `remove_tree`, for every job that still has a directory.
5. **Serial architecture**: 578 groups processed on one gru worker while
   `gru --jobs 4` is available.

---

## Measured evidence (OSD, 2026-11-19, read-only)

| Metric                                                   | Value                                      |
| :------------------------------------------------------- | :----------------------------------------- |
| Jobs past `keep_results_in_days` (groups with retention) | 1,389,032                                  |
| … with `result_size = 0` (already cleaned)               | 1,187,818 (85.5%)                          |
| … with `result_size > 0` (still hold results)            | 148,448                                    |
| … with `result_size IS NULL`                             | 52,766                                     |
| Candidates under the new predicate                       | 201,214 (14.5%)                            |
| Exclusive-usage anti-join, zero-link job                 | 42.4 ms exec (4.65 ms planning, 2 workers) |
| Indexed `SELECT 1 … LIMIT 1` link check                  | 0.098 ms (index-only scan, 7 buffers)      |
| Derived: 1.188M × 42.4 ms                                | ≈ 14 h of the ~25 h runtime                |
| `screenshot_links` / `screenshots` / `jobs` size         | 438M rows/38G, 169M/34G, 6.4M/13G          |
| `result_size = 0`, `logs_present = false`, links left    | 312 jobs                                   |

Caveats: the per-job timings are single-row microbenchmarks; the candidate
counts ignore important-build and linked-job exceptions; the 14 h figure is an
upper bound for the screenshot query alone, not an end-to-end measurement.

---

## Remaining Work (re-ordered, measurement before risk)

Order rationale: make measurement possible (Task 4, 5) before changing more
behaviour; the per-inode work (Task 6) only matters for jobs that still have a
directory, so it comes only after Task 5 shows it dominates; batching (Task 7)
and parallelism (Task 8) are the remaining structural wins, parallelism last
because it changes coordination and needs the dry-run switch to roll out.

### Task 4 (Commit 4): `dry_run` argument for the periodic cleanup

- **Files**: `lib/OpenQA/Task/Job/Limit.pm`,
  `lib/OpenQA/Schema/Result/JobGroups.pm`, `t/42-df-based-cleanup.t`
- **Objective**:
  - Accept `limit_results_and_logs => [{dry_run => 1}]` and thread the flag into
    `JobGroups::limit_results_and_logs($preserved, $dry)`.
  - In the group loop: skip `$_->delete` for expired jobs, call
    `delete_results($dry)` / `delete_logs($dry)`, skip the
    `archive_job_results` enqueue, and do not advance
    `cleanup-status.json` (no round-robin state change on a dry run).
  - Write `$job->note(dry_run_stats => {groups, jobs_deleted, results_bytes,
logs_bytes, screenshots_bytes})` so a production dry run is auditable.
  - Note: `Jobs::delete` ignores `$dry`, so the skip must be explicit.
- **Tests**: dry run leaves rows, `result_size`, `logs_present`, directories and
  the cache file untouched; note carries non-zero counts; a second normal run
  still cleans everything.
- **Verification**: Gates Commit 4.

### Task 5 (Commit 5): Document and run the dump-replay validation

- **Files**: `docs/Contributing.md` (section "Validating cleanup changes
  against a production database dump")
- **Objective**: make the validation reproducible:
  1. Fetch a dump (`openqa-dump-db`, `pg_dump -Fc`, ~127 GB) from OSD; restore
     into a dedicated local database; enable `pg_stat_statements`.
  2. Check out `1f7748a4d` and the branch in two worktrees, point both at the
     dump, use a throwaway `testresults` directory.
  3. Read-only comparison first: per group, time `find_expired_jobs`,
     `find_jobs_with_expired_results`, `find_jobs_with_expired_logs`, and diff
     returned id sets between old and new.
  4. Write-path comparison with Task 4's `dry_run`: assert zero `UPDATE`s for
     `result_size = 0` + `logs_present = false` jobs (count via
     `pg_stat_statements`) and identical cleaned-job sets.
  5. Production filesystem drift sample (cannot come from a dump): count
     `result_size = 0 AND logs_present = false AND result_dir IS NOT NULL`, then
     `test -d` a random sample under `/var/lib/openqa/share/testresults`.
- **Acceptance**: ≥80% candidate reduction, no job with `result_size > 0`
  dropped, zero no-op updates, drift sample consistent with the invariant.
- **Verification**: Gates Commit 5 and Gate "Task 5 run".

### Task 6 (Commit 6): Fast directory removal in `delete_results`

- **Precondition**: Task 5 shows filesystem traversal dominating for jobs with
  results. Do not start otherwise.
- **Files**: `lib/OpenQA/Schema/Result/Jobs.pm`, `t/10-jobs-results.t`
- **Objective**: replace the `list_tree` + per-file `stat`/`unlink` accounting
  with a single `remove_tree` and use the already accounted `result_size` as the
  returned deleted size; keep the exact walking behaviour for `$dry`.
- **Design note**: the returned size feeds the df-margin accounting in
  `Limit.pm`, so state the accuracy tradeoff in the commit body.
- **Tests**: non-dry run removes the tree and reports the accounted size;
  dry run still reports the walked size and deletes nothing.
- **Verification**: Gates Commit 6.

### Task 7 (Commit 7): Batched database operations

- **Files**: `lib/OpenQA/Schema/Result/JobGroups.pm`,
  `lib/OpenQA/Schema/Result/Jobs.pm`, `t/10-jobs-results.t`,
  `t/42-df-based-cleanup.t`
- **Objective**: batch status updates and screenshot-link deletes in chunks
  (≤500 ids) instead of per job; batch expired-job deletion. Keep per-job
  screenshot exclusivity checks, since those depend on other jobs.
- **Tests**: multi-job fixtures produce the same end state as the per-job path.
- **Verification**: Gates Commit 7.

### Task 8 (Commit 8): Parallelize group cleanup over Minion workers

- **Files**: `lib/OpenQA/Task/Job/Limit.pm`, `t/42-df-based-cleanup.t`
- **Objective**: enqueue `limit_job_group_results` child tasks (one per group or
  per small group batch) instead of the serial loop; each child re-checks the
  storage threshold before acting; round-robin state is updated by children
  under `flock`; the parent records child ids in its note.
- **Rollout**: validate with Task 4's `dry_run` on OSD, then enable.
- **Tests**: enqueue count and arguments, guard interaction, cache-file
  concurrency, and behaviour when the threshold is already reached.
- **Verification**: Gates Commit 8.

### Task 9 (Commit 9): User-facing documentation

- **Files**: `docs/UsersGuide.md` (cleanup architecture, retention vs
  lower-bound cleanup, `result_size` semantics, dry-run switch)
- **Verification**: Gates Commit 9.

---

## Approvals

| Decision                                                                                            | Approver | Date       |
| :-------------------------------------------------------------------------------------------------- | :------- | :--------- |
| Implement Tasks 1–3 and the df-cleanup `result_size` filter in the 154 worktree                     | okurz    | 2026-11-20 |
| Rewrite the three commit messages to carry measured benchmark numbers                               | okurz    | 2026-11-20 |
| Order remaining work as Task 4 (dry_run) → 5 (validation) → 6/7/8 → 9 (docs)                        | pending  | pending    |
| `dry_run` is a Minion job argument (`[{dry_run => 1}]`), not a config setting                       | pending  | pending    |
| Acceptance thresholds for the dump replay (≥80% candidates, no dropped results, zero no-op updates) | pending  | pending    |
| Fast directory removal only after Task 5 shows filesystem time dominating                           | pending  | pending    |
| Parallel group cleanup only after a dry-run OSD validation                                          | pending  | pending    |

---

## Gates

| Commit                 | Scope                                         | Verification Command                                                                                                                                                                                       |
| :--------------------- | :-------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Commit 1 `2bd5ed5cb`   | skip jobs with deleted results (done)         | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS="t/10-jobs-results.t t/42-df-based-cleanup.t t/api/10-jobgroups.t" && make check-line-coverage && make test-gitlint` |
| Commit 2 `cd48c3b49`   | skip no-op screenshot/job updates (done)      | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS="t/10-jobs-results.t t/42-screenshots.t" && make check-line-coverage && make test-gitlint`                           |
| Commit 3 `ba3d88a93`   | skip size-0 jobs in df cleanup (done)         | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/42-df-based-cleanup.t && make check-line-coverage && make test-gitlint`                                            |
| Commit 4               | `dry_run` argument and stats note             | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/42-df-based-cleanup.t && make check-line-coverage && make test-gitlint`                                            |
| Commit 5               | dump-replay validation procedure in docs      | `make test-markdown && SKIP_UPDATE_DEPS=1 make test-checkstyle && make test-gitlint`                                                                                                                       |
| Task 5 run (no commit) | execute the procedure against a restored dump | `pg_restore` + per-group timings + `git diff` of id sets; record numbers in the plan before starting Task 6                                                                                                |
| Commit 6               | fast directory removal                        | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/10-jobs-results.t && make check-line-coverage && make test-gitlint`                                                |
| Commit 7               | batched database operations                   | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS="t/10-jobs-results.t t/42-df-based-cleanup.t" && make check-line-coverage && make test-gitlint`                      |
| Commit 8               | parallel group cleanup                        | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/42-df-based-cleanup.t && make check-line-coverage && make test-gitlint`                                            |
| Commit 9               | user-facing cleanup documentation             | `make test-markdown && SKIP_UPDATE_DEPS=1 make test-checkstyle && make test-gitlint`                                                                                                                       |

---

## Session starter

```markdown
Continue with execution plan `tasks/154_oqa1_poo210630_optimize_results_cleanup.md`.
Load skills: `perl-dev`, `testing`, `git-workflow`.
Worktree: `~/local/os-autoinst/oqa-154-cleanup`, branch
`feature/154_oqa1_poo210630_optimize_results_cleanup`, base `1f7748a4d`,
currently 3 commits (Tasks 1–3 done, messages carry the OSD measurements).
Commit unit: start with Task 4 (`dry_run` argument for the periodic cleanup,
`lib/OpenQA/Task/Job/Limit.pm` + `JobGroups.pm` + `t/42-df-based-cleanup.t`).
Then Task 5: document and run the dump-replay validation before touching
Tasks 6–8.
Confirm with the user before: (a) running any cleanup in write mode against any
database, (b) restoring a production dump or accessing OSD, (c) starting
Tasks 6–8, (d) pushing or opening a PR.
```
