# 161 poo#210630: periodic results crosscheck

Context: follow-up to the results cleanup work in
`tasks/154_oqa1_poo210630_optimize_results_cleanup.md` (PR
https://github.com/os-autoinst/openQA/pull/8147) and
`tasks/160_poo210630_verified_results_removal.md`. Ticket: poo#210630.
Numbering: prefix `161` (max existing prefix is 160).
Branch: `feature/161_poo210630_periodic_results_crosscheck`, worktree
`~/local/os-autoinst/oqa-161-crosscheck`.

---

## Problem statement

The daily cleanup skips jobs with `result_size = 0` (PR #8147). That is correct
for the ~99 % of jobs whose results really are gone, but it removes the previous
property that every candidate was re-checked once per day, so a mismatch between
database and filesystem is now invisible to the cleanup.

Measured on OSD (2026-11-20, read-only, 100,000 random size-0 jobs with a
`result_dir` of 1,430,805 such jobs):

| Finding | Value |
| :------ | :---- |
| size-0 jobs that still have a directory | 1,067 (1.07 %) |
| … containing only empty `.thumbs/` + `ulogs/` | 1,028 |
| … containing files | 39 (0.04 %), 4,765 files, 1.75 MB |
| extrapolated instance-wide | ~560 jobs, ~25 MB |
| newest leftover file vs. row `t_updated` | older in **39 of 39** cases |

The leftovers are failed or partial removals that still recorded
`result_size = 0`, not uploads that arrived after cleanup. Plan 160 fixes that
cause. This plan adds the integrity net that finds existing drift, plus the
mismatch class plan 160 cannot see at all: directories whose job row is gone.

## Scope and cost

| Tier | Check | Cost basis (measured) | Runtime estimate |
| :--- | :---- | :-------------------- | :--------------- |
| A | DB→FS presence for jobs past the results retention: cleaned jobs must have no directory, jobs with results must have one | one `stat` per job (0.1–1 ms), ~1.6 M jobs | 10–30 min warm, ≤2 h cold |
| B | FS→DB orphans: every directory under `testresults/` and `archive/testresults/` must belong to an existing job | 24,343 prefix dirs × ~900 entries, chunked | hours of idle I/O |
| C | size verification `du` vs `result_size` | 5.5 ms warm / 344 ms cold per dir, and `result_size` over-reports the job dir ~27× median (it counts screenshots) | not run; out of scope |

Tier C is deliberately excluded: the comparison has no defined meaning without a
redefinition of `result_size`, and even a monthly run would cost more than the
25 MB it could explain.

The crosscheck is one Minion task with child jobs, lowest priority, a cursor in
`prjdir/webui/cache/`, report-only by default. It is *not* about reclaiming
space; it is about noticing bugs like the January 2026 case (4,725 files left
behind) within weeks instead of by chance, and about the orphan class B.

## Design

One Minion task `crosscheck_results_consistency`, chunked like
`limit_screenshots` (parent enqueues children with id/prefix ranges):

```
crosscheck_results_consistency (parent, priority 1000, limit 1, ttl 7 days)
  ├─ child per group batch      (tier A, e.g. 20 groups or 20,000 jobs)
  └─ child per prefix batch     (tier B, e.g. 500 prefix dirs)
```

- **Priority and locking**: `priority => 1000` (the daily cleanup is enqueued
  with `priority => 5`, archive/screenshot children with `-20`; lower value runs
  sooner), own Minion guard `crosscheck_results_task`, plus a skip while a
  `limit_results_and_logs` job is inactive/active so the two do not hammer the
  same disks.
- **Tier A semantics**: reuse the group-based retention logic instead of
  re-deriving it in SQL (`keep_results_in_days` → parent `default_*` → config,
  important builds and linked jobs included):
  - `find_jobs_with_expired_results` (existing) → directory must exist, else
    report `results_without_dir`;
  - new `find_jobs_with_cleaned_results` (`results_present = 0` and past the
    results retention) → directory must not exist, else report `cleaned_with_dir`.
  Only `-d` checks, no deletion, no walking.
- **Tier B semantics**: iterate the prefix directories of `resultdir()` and
  `archivedir()`, parse the leading job id from each entry name (`^(\d+)-`),
  and batch-check the ids against `jobs`. Entries without a matching row and
  older than 24 h are reported as `orphan_dir`.
- **Safety**: skip jobs whose state is not final, skip directories whose mtime is
  younger than 24 h (in-flight uploads), skip groups with unlimited retention.
- **Cursor**: `prjdir/webui/cache/crosscheck-status.json` with
  `last_group_id` and `last_prefix`, written after each child batch, so an
  interrupted month resumes instead of restarting.
- **Output**: parent note with `checked_jobs`, `cleaned_with_dir`,
  `results_without_dir`, `orphan_dirs`, `bytes_unexpected`, `groups_checked`,
  `prefixes_checked` and at most 20 sample paths. Children note their own counts.
- **Repair**: off by default (`repair => 0`); with `repair => 1` the task may only
  remove a directory that is reported as `cleaned_with_dir` or `orphan_dir`, whose
  mtime is older than the retention period, and whose job (if any) is in a final
  state. Never repair on a size mismatch, never touch a directory reported as
  `results_without_dir`.
- **Scheduling**: `systemd/openqa-enqueue-result-crosscheck.{timer,service}` plus
  `script/openqa-enqueue-result-crosscheck`, mirroring the existing daily pair,
  with `OnCalendar=monthly` (ops-adjustable) and the ini switch
  `[cleanup] crosscheck = 0` so a packaged instance does not start scanning
  silently.

## Tasks

### Task 1 (Commit 1): tier A — presence crosscheck per group batch

- **Files**: `lib/OpenQA/Task/Job/Crosscheck.pm` (new),
  `lib/OpenQA/Schema/Result/JobGroups.pm`
  (`find_jobs_with_cleaned_results`), `lib/OpenQA/Schema/Result/Jobs.pm`
  (predicate helper if needed), `lib/OpenQA/WebAPI.pm` or the plugin that
  registers tasks (where `limit_results_and_logs` is registered),
  `t/42-results-crosscheck.t` (new).
- **Objective**: register the parent task, chunk the work over groups, do the two
  `-d` checks, aggregate the note, write the cursor file.
- **Tests**: cleaned job with a directory is reported; job with results but no
  directory is reported; healthy jobs of both kinds are not reported; a job in a
  non-final state is skipped; chunking enqueues the expected number of children
  with the expected ranges; cursor file content after the run.
- **Verification**: Gates Commit 1.

### Task 2 (Commit 2): tier B — prefix scan for orphan directories

- **Files**: `lib/OpenQA/Task/Job/Crosscheck.pm`, `t/42-results-crosscheck.t`.
- **Objective**: prefix batches over `resultdir()` and `archivedir()`, id parsing
  from directory names, batched existence check, 24 h age guard, cursor
  `last_prefix`, counts in the note.
- **Tests**: orphan directory reported; directory of an existing job not
  reported; archived directory of an archived job not reported; young directory
  skipped; prefix batching and cursor wrap-around.
- **Verification**: Gates Commit 2.

### Task 3 (Commit 3): scheduling, switch and documentation

- **Files**: `systemd/openqa-enqueue-result-crosscheck.timer`,
  `systemd/openqa-enqueue-result-crosscheck.service`,
  `script/openqa-enqueue-result-crosscheck`, `lib/OpenQA/Setup.pm`
  (`cleanup -> crosscheck`), `etc/openqa/openqa.ini`,
  `docs/UsersGuide.md`, `t/config.t`.
- **Objective**: monthly timer, enqueue script
  (`app->gru->enqueue(crosscheck_results_consistency => [], {priority => 1000, ttl => 604800, limit => 1})`),
  ini switch with default `0`, documentation of the two tiers and the repair
  option.
- **Tests**: `t/config.t` asserts the new default; `t/44-scripts.t` (HEAVY) runs
  the new script.
- **Verification**: Gates Commit 3.

### Task 4 (Commit 4): optional repair mode

- **Files**: `lib/OpenQA/Task/Job/Crosscheck.pm`, `t/42-results-crosscheck.t`.
- **Objective**: `repair => 1` removes only the cases documented under *Design*,
  logs each removal, and counts them separately in the note.
- **Tests**: repair removes a reported old directory; keeps a young one, keeps
  one of a non-final job, keeps everything with `repair => 0`.
- **Verification**: Gates Commit 4.

### Task 5 (no commit): run once on OSD and record results

Trigger the task on OSD out of hours (report-only), compare the reported counts
with the sampling numbers in this plan (~560 jobs with files, ~25 MB), and
record both in the plan. Only then decide whether `repair => 1` is ever enabled.

## Out of scope

- Tier C (`du` size verification).
- Screenshot/image tree consistency: `scan_untracked_screenshots` already exists
  and is tracked separately.
- Batching or parallelising the daily cleanup (Tasks 7/8 of plan 154).

## Risks

- Tier B walks every prefix directory: on a 16 TB XFS with cold metadata this is
  hours of I/O. Mitigations: lowest Minion priority, chunked children, own
  cursor, skip while the daily cleanup runs, and the ini switch off by default.
- False positives for jobs still uploading: mitigated by the 24 h age guard and
  the non-final-state skip; that is also why repair defaults to off.
- The note must stay small (Minion notes are stored in the database as JSON).

---

## Implementation notes (Tasks 1–4, commits `ce132b1a0`, `b1ebfe6ae`, `2ce691d6f`, `a75f3e929`)

- **Priority inverted in the plan**: `Minion::Backend::Pg` dequeues `ORDER BY
  priority DESC`, so `priority => 1000` would run *before* the daily cleanup
  (`priority => 5`) and the archive/screenshot children (`-20`). Implemented as
  `priority => -100` in parent, children and summary.
- **PR #8147 is not merged** (`origin/master` at `a0b5f8faf`), so
  `find_jobs_with_expired_results` has no `result_size` filter. The size
  condition is applied by the crosscheck's own queries: tier A checks
  `result_size = 0` (`find_jobs_with_cleaned_results`) and `result_size > 0`
  (`find_jobs_with_present_results`) on top of `_find_expired_jobs`.
  `result_size IS NULL` jobs are deliberately not checked: a NULL-size job
  without a directory is the normal state of a job that never uploaded.
- Registration is `OpenQA::Shared::Plugin/Gru.pm` (not `OpenQA::WebAPI.pm`).
- Parent, group-batch child and summary are three phases of the single task
  `crosscheck_results_consistency`; the summary is enqueued with `parents =>
  \@child_ids` and writes the aggregated `crosscheck_summary` note onto the
  parent job, which is the only way to aggregate children results. `bytes_unexpected`
  is not implemented: measuring bytes requires the `du` walk of tier C.
- Gate result: `make tidy`, `make test-checkstyle SKIP_UPDATE_DEPS=1`,
  `COVERAGE=1 make test-unit-and-integration TESTS=t/42-results-crosscheck.t`
  and `make test-gitlint` pass. `make check-line-coverage` fails as expected
  (its cover_db holds only this test, so 500 unrelated lines are uncovered);
  per-file verification via `jq` on `cover_db/codecov.json` shows zero
  uncovered statements in `Crosscheck.pm` and in the added `JobGroups.pm` lines.

- **Tier B scans both trees via `resultdir()` and `resultdir(1)`** (commit
  `b1ebfe6ae`): archived results live under `<archive>/testresults`, not under
  `archivedir()` itself, so `archivedir()` alone finds no prefix directories.
  `Mojo::File->list` excludes directories by default, so the scan needs
  `list({dir => 1})` and an explicit `@{...}` deref. Directory names are
  zero-padded, so the ID has to be normalized numerically before the row lookup.
  Counters: `entries_scanned`, `prefixes_checked`, `orphan_dirs`,
  `cleaned_with_dir`, `archived_with_dir` (archived row, dir in the results
  tree), `archived_copy` (non-archived row, dir in the archive tree). Samples
  are deduplicated in the summary because the group batch of a job and the
  prefix batch of its directory report the same path.
- **Tier B bullet 2 is covered by tier A**: a job row recorded as present whose
  directory is missing is detected by the group batch (past retention,
  `result_size > 0`), so the prefix batch checks the filesystem→database
  direction only. Rows in a prefix that never uploaded (`result_size` NULL) are
  not counted as mismatches.
- **DBIC `filter_column` on `result_dir`**: a resultset `columns` list must
  include `result_dir` for the inflated full path, otherwise a row access
  returns undef and the filesystem comparison silently misclassifies.
- **Task 4** (commit `a75f3e929`): `repair` is an argument of the parent job,
  never a config key, so enabling it is a deliberate one-off enqueue and the
  timer (`repair` absent) stays report-only. It is propagated to the children and
  inherits the existing guards: the group query already limits to jobs past
  results retention in a final state, and a directory must be older than 24 h.
  Only `cleaned_with_dir` and `orphan_dirs` are removable; `results_without_dir`,
  `archived_with_dir` and `archived_copy` are report-only. The `repaired` counter
  only appears in a note when repair is on, so report-only notes are unchanged.
- **Task 3** (commit `2ce691d6f`): `script/openqa-enqueue-result-crosscheck`
  enqueues only when `[cleanup] crosscheck` is set, `Setup.pm` defaults it to 0,
  `t/config.t` asserts the default, the monthly timer is added to the RPM unit
  list and to `openqa-webui.service` `Wants=`. `t/44-scripts.t` (HEAVY) passes
  with the new script. `make check-line-coverage` was not run for commit 3
  (`Setup.pm` change is data, covered by `t/config.t`).

- **Cadence**: the timer ticks daily and `enqueue_if_due` reads
  `[cleanup] crosscheck_interval_days` (default 30, 0 = every tick) plus the last
  finished Minion run, so no unit-file override is needed.
- **Branch and PRs**: `feature/161_poo210630_periodic_results_crosscheck` (tiers
  A+B and scheduling, rebased onto `origin/master` `84135d4eb`) is draft PR
  <https://github.com/os-autoinst/openQA/pull/8158>. Repair is stacked on it as
  `feature/161_poo210630_periodic_results_crosscheck_2` (commit `a75f3e929`),
  draft PR <https://github.com/okurz/openQA/pull/1>, to be reopened against
  `master` once the base PR is merged. Task 5 (run on OSD) and any enabling stay
  out until reviewers agree.

## Approvals

| Decision                                                                                  | Approver | Date    |
| :---------------------------------------------------------------------------------------- | :------- | :------ |
| Add a periodic crosscheck as a separate Minion task instead of re-adding the daily walk     | okurz    | 2026-11-20 |
| Two tiers only (presence and orphan scan); no `du` size verification                        | pending  | pending |
| Lowest Minion priority, monthly `OnCalendar`, ini switch defaulting to off                  | pending  | pending |
| Repair mode off by default, only for old `cleaned_with_dir`/`orphan_dir` cases              | pending  | pending |
| Tier A reuses the group retention logic instead of re-deriving retention in SQL             | pending  | pending |
| Run the first production pass out of hours in report-only mode before enabling repair       | pending  | pending |

## Gates

| Commit | Scope | Verification Command |
| :----- | :---- | :------------------- |
| Commit 1 | tier A crosscheck | `make tidy && make test-checkstyle SKIP_UPDATE_DEPS=1 && COVERAGE=1 make test-unit-and-integration TESTS=t/42-results-crosscheck.t && make check-line-coverage && make test-gitlint` |
| Commit 2 | tier B orphan scan | `make tidy && make test-checkstyle SKIP_UPDATE_DEPS=1 && COVERAGE=1 make test-unit-and-integration TESTS=t/42-results-crosscheck.t && make check-line-coverage && make test-gitlint` |
| Commit 3 | timer, script, switch, docs | `make tidy && make test-checkstyle SKIP_UPDATE_DEPS=1 && make test-markdown && COVERAGE=1 make test-unit-and-integration TESTS="t/config.t" && HEAVY=1 COVERAGE=1 make test-unit-and-integration TESTS=t/44-scripts.t && make test-gitlint` |
| Commit 4 | optional repair mode | `make tidy && make test-checkstyle SKIP_UPDATE_DEPS=1 && COVERAGE=1 make test-unit-and-integration TESTS=t/42-results-crosscheck.t && make check-line-coverage && make test-gitlint` |
| Task 5 (no commit) | report-only run on OSD | jobs noted counts vs. the sampling numbers in this plan, recorded here |

## Session starter

```markdown
Continue with execution plan `tasks/161_poo210630_periodic_results_crosscheck.md`.
Load skills: `perl-dev`, `testing`, `git-workflow`.
Create worktree `~/local/os-autoinst/oqa-161-crosscheck` on branch
`feature/161_poo210630_periodic_results_crosscheck`.
Start with Task 1: add `lib/OpenQA/Task/Job/Crosscheck.pm` registering
`crosscheck_results_consistency`, a parent/child split over job group batches,
and two read-only checks per job past the results retention: jobs with
`results_present = 0` must have no result directory, jobs returned by
`find_jobs_with_expired_results` must have one. Add
`JobGroups::find_jobs_with_cleaned_results`, aggregate the counts into the
parent job note, and write `prjdir/webui/cache/crosscheck-status.json`.
Test it in the new `t/42-results-crosscheck.t`.
Context you can rely on: see the measured table in the plan; tier C (`du`) is
out of scope; repair mode is Task 4 and off by default.
Confirm with the user before: (a) running the task against any production
instance, (b) enabling the systemd timer or the ini switch anywhere, (c) repair
mode, (d) pushing the branch or opening a PR.
```
