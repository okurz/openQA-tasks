# 160 poo#210630: verified results removal and upload guard

Context: follow-up to the results cleanup work in
`tasks/154_oqa1_poo210630_optimize_results_cleanup.md` (PR
https://github.com/os-autoinst/openQA/pull/8147), which stopped visiting jobs
with `result_size = 0`. Ticket: poo#210630.
Numbering: prefix `160` (max existing prefix is 159).
Branch: `feature/160_poo210630_verified_results_removal`, branched from
`origin/master` after PR #8147 is merged, worktree
`~/local/os-autoinst/oqa-160-verified-removal`.

Execution gate (approved 2026-11-21): no task starts before PR #8147
("perf(cleanup): skip already-cleaned jobs in results cleanup") is merged. It is
approved, all checks green, `mergeStateStatus: CLEAN`, so it is expected to land
without further action from me. The worktree already exists at `a0b5f8faf`
(2026-11-21) and must be rebased onto the post-#8147 `origin/master` before
Task 1; waiting for the merge keeps Task 3 a plain replacement of #8147's filter
instead of a rebase against a moving target.

Schema version: `origin/master` is at **108**, not 107, so this plan's migration
bumps **108 → 109** (`dbicdh/_source/deploy/109`,
`dbicdh/PostgreSQL/upgrade/108-109`, `dbicdh/_common/upgrade/108-109`).
In-flight branches are at 108 (`feature/120`, `feature/121`, `feature/154`) and
109 (`stack/032_ssh_key_auth`), so the version number must be announced on the
pull request.

---

## Problem statement

PR #8147 assumes `result_size = 0` means "results are gone". That claim is
written by `delete_results` unconditionally, after an unchecked
`Mojo::File::remove_tree` (`Jobs.pm:1222-1237`); `Mojo::File::remove_tree`
discards the `File::Path` result and `File::Path` ignores errors unless asked.

Measured on OSD (2026-11-20, read-only, 100,000 random size-0 jobs with a
`result_dir` of 1,430,805 such jobs):

| Bucket                                          | Count | Share of sample |
| :---------------------------------------------- | :---- | :-------------- |
| directory still present                         | 1,067 | 1.07 %          |
| … only empty `.thumbs/` + `ulogs/`              | 1,028 | 1.03 %          |
| … containing files                              | 39    | 0.04 %          |
| files / bytes in those 39 directories           | 4,765 / 1.75 MB | —    |
| extrapolated instance-wide                      | ~560 jobs / ~25 MB | — |

**Mechanism (measured, not assumed):** for all 39 jobs the newest leftover file
is *older* than the job row's `t_updated`, and in several cases the directory
mtime equals `t_updated` exactly, e.g.

| job      | newest file      | dir mtime   | `t_updated` |
| :------- | :--------------- | :---------- | :---------- |
| 20122232 | 2025-11-24 14:59 | 2026-01-29 01:46 | 2026-01-29 01:46:06 |
| 18899862 | 2025-08-24 14:00 | 2025-10-09 04:47 | 2025-10-09 04:47:04 |
| 22040241 | 2026-04-27 04:04 | 2026-04-27 04:04 | 2026-05-08 01:43:56 |

So the leftovers come from **failed or partial removal during cleanup that still
recorded `result_size = 0`**, not from uploads arriving after the cleanup. A
late-upload guard alone would therefore not fix the observed data; the fix that
matches the evidence is to verify the removal before claiming the job is clean,
and to keep the upload guard as defence in depth (it prevents the API paths from
re-creating a cleaned directory, which is cheap and testable).

Worst single case: job `20122232` with 4,725 files (1.68 MB) survived a cleanup
that set `result_size = 0` in January 2026.

## Design

Introduce an explicit presence flag instead of overloading `result_size`
(mirroring the existing `logs_present`):

- `jobs.results_present BOOLEAN NOT NULL DEFAULT TRUE`, backfilled as
  `result_size IS NULL OR result_size > 0` (identical candidate set at migration
  time).
- `delete_results` sets `results_present = 0` **only** when the directory is gone
  and no screenshot links remain; otherwise it logs a warning and keeps the flag
  at 1, so the job stays a candidate and the next run retries (self-healing,
  bounded to the jobs that actually failed).
- The candidate queries (`find_jobs_with_expired_results`, the df-based
  `_delete_results`) select on `results_present` instead of the arithmetic
  `result_size > 0 OR NULL`. This removes the magic value from the query and
  keeps `NULL` meaning only "size unknown".
- Upload endpoints (`POST /api/v1/jobs/<id>/artefact` for artefacts, `ulogs`,
  `image`/screenshots and `extra_test` parses) return `409` with a JSON error
  when the job's results were cleaned, instead of silently re-creating the
  directory. `OpenQA::Worker::WebUIConnection::evaluate_error` already does not
  retry most 4xx responses, so no worker change is needed.

Tradeoffs: one schema migration; `result_size` stays an estimate for the
`Limit.pm` df margin and is no longer consulted for selection.

## Tasks

### Task 1 (Commit 1): `results_present` column and backfill

- **Files**: `lib/OpenQA/Schema.pm` (`$VERSION` 108 → 109),
  `lib/OpenQA/Schema/Result/Jobs.pm` (column),
  `dbicdh/_source/deploy/109/001-auto.yml`,
  `dbicdh/PostgreSQL/deploy/109/001-auto.sql`,
  `dbicdh/PostgreSQL/upgrade/108-109/001-auto.sql`,
  `dbicdh/_common/upgrade/108-109/010-backfill-results-present.pl`.
- **Objective**: add the column via `./script/initdb --prepare_init` and
  `./script/upgradedb --prepare_upgrade` (see `docs/Contributing.md`,
  "How to update the database schema"), then backfill with a custom migration
  named to run after `001-auto.sql`:
  `UPDATE jobs SET results_present = (result_size IS NULL OR result_size > 0)`.
  Announce the version bump on the pull request because other in-flight branches
  may also bump it.
- **Tests**: `t/deploy.t` exercises deploy and the upgrade path including custom
  migrations; confirm the backfill runs and produces the expected candidate set.
- **Verification**: Gates Commit 1.

### Task 2 (Commit 2): verified removal in `delete_results`

- **Files**: `lib/OpenQA/Schema/Result/Jobs.pm`, `t/10-jobs-results.t`,
  `t/42-screenshots.t`.
- **Objective**: after `remove_tree`, re-check `-d $result_dir`; write
  `results_present => 0` (together with the existing `logs_present`/`result_size`
  update) only if the directory is gone and no links remain. Otherwise log a
  warning naming the path and leave `results_present` at 1. Keep `result_size`
  semantics unchanged in this commit.
- **Tests**: mocked `remove_tree` that does nothing → flag stays 1, warning
  logged, job remains in `find_jobs_with_expired_results`; normal removal → flag
  0; dry run → nothing written.
- **Verification**: Gates Commit 2.

### Task 3 (Commit 3): select candidates on `results_present`

- **Precondition**: PR #8147 merged (it introduced the `result_size` filter this
  commit replaces). On `origin/master` as of 2026-11-21 that filter does not
  exist: `_delete_results` (`Limit.pm:252,254`) selects the results pass with no
  size condition and `find_jobs_with_expired_results` has none, so this commit
  can only be written against the post-#8147 tree.
- **Files**: `lib/OpenQA/Schema/Result/JobGroups.pm`,
  `lib/OpenQA/Task/Job/Limit.pm`, `t/42-df-based-cleanup.t`, `t/10-jobs-results.t`,
  `t/14-grutasks.t`.
- **Objective**: replace `result_size => [{'>' => 0}, undef]` with
  `results_present => 1` in `find_jobs_with_expired_results` and in
  `_delete_results` (both the results-dir and archive passes).
- **Tests**: job with `results_present = 0` is not selected even with
  `result_size > 0`; job with `results_present = 1` and no directory is selected
  (the retry path); `NULL` sizes are selected when the flag is 1.
- **Verification**: Gates Commit 3.

### Task 4 (Commit 4): refuse uploads for cleaned jobs

- **Files**: `lib/OpenQA/Schema/Result/Jobs.pm` (`create_artefact`,
  `parse_extra_tests`, `store_image`, `update_module` if it is the seam that
  writes `details-*.json`), `lib/OpenQA/WebAPI/Controller/API/V1/Job.pm`
  (`create_artefact` action), `t/api/04-jobs.t`, `t/24-worker-jobs.t`.
- **Objective**: when `results_present` is false, do not create the result
  directory and answer `409` with `{error => "Results of job <id> have already
  been cleaned up"}`. Applies to artefacts, `ulogs`, screenshots and
  `extra_test` parses; the asset upload branch is unaffected (it writes to the
  factory, not the job directory).
- **Tests**: each upload variant against a cleaned job → 409, no directory
  created, `result_size` unchanged; the same upload against a normal job still
  succeeds; `t/24-worker-jobs.t` asserts the worker does not retry and logs the
  409 message (existing `evaluate_error` behaviour, no code change).
- **Verification**: Gates Commit 4.

### Task 5 (Commit 5): document the semantics

- **Files**: `docs/UsersGuide.md` (cleanup section: `results_present`, retry on
  failed removal, `result_size` as an estimate), the API section for
  `POST /api/v1/jobs/<id>/artefact` (409 response).
- **Verification**: Gates Commit 5.

### Task 6 (no commit): re-measure after rollout

Run the same sampling procedure once the change is released on an instance:
10,000 random jobs with `results_present = 0`, `test -d` each, `du` on hits.
Expected: ~0 jobs with a directory, because failed removals stay candidates and
are retried on the next run. Record the numbers in this plan before declaring the
task done.

## Out of scope

- A janitor task sweeping `results_present = 0 AND result_dir IS NOT NULL`:
  unnecessary while the flag only claims what was verified.
- Changing the `result_size` accounting itself (it also counts screenshots,
  which is why it over-reports the job directory by ~27x median).
- Parallelising the group loop and batching (Tasks 7/8 of plan 154).

---

## Approvals

| Decision                                                                                     | Approver | Date       |
| :------------------------------------------------------------------------------------------- | :------- | :--------- |
| Fix the measured failed-removal case instead of only guarding late uploads                    | pending  | pending    |
| Add an explicit `results_present` flag (schema migration 108 → 109, `deploy/109`, `upgrade/108-109`) instead of reusing `result_size` | okurz    | 2026-11-21 |
| Upload guard answers `409` (no silent drop) and needs no worker retry change                  | pending  | pending    |
| Backfill rule `result_size IS NULL OR result_size > 0`                                       | pending  | pending    |
| No task starts before PR #8147 is merged; worktree rebased onto post-#8147 master            | okurz    | 2026-11-21 |
| Version bump announced on the PR to avoid collisions with in-flight branches                 | pending  | pending    |

## Blocked

| Unit                        | Condition                                            | Verification command                                        | Recorded        |
| :-------------------------- | :--------------------------------------------------- | :---------------------------------------------------------- | :-------------- |
| All tasks (branch base)     | PR #8147 merged into `origin/master`                  | `gh pr view 8147 --json state,mergedAt`                     | unmet, 2026-11-21 |
| Task 3 (candidate selection) | #8147 merge commit is an ancestor of `origin/master`   | `git merge-base --is-ancestor <8147-merge-sha> origin/master` | unmet, 2026-11-21 |

## Gates

| Commit                 | Scope                                | Verification Command |
| :--------------------- | :----------------------------------- | :------------------- |
| Commit 1               | `results_present` column + backfill  | `make tidy && make test-checkstyle SKIP_UPDATE_DEPS=1 && COVERAGE=1 make test-unit-and-integration TESTS=t/deploy.t && make test-gitlint` |
| Commit 2               | verified removal in `delete_results` | `make tidy && make test-checkstyle SKIP_UPDATE_DEPS=1 && COVERAGE=1 make test-unit-and-integration TESTS="t/10-jobs-results.t t/42-screenshots.t" && make check-line-coverage && make test-gitlint` |
| Commit 3               | candidate selection on the flag      | `make tidy && make test-checkstyle SKIP_UPDATE_DEPS=1 && COVERAGE=1 make test-unit-and-integration TESTS="t/10-jobs-results.t t/42-df-based-cleanup.t t/14-grutasks.t" && make check-line-coverage && make test-gitlint` |
| Commit 4               | upload guard and 409                 | `make tidy && make test-checkstyle SKIP_UPDATE_DEPS=1 && COVERAGE=1 make test-unit-and-integration TESTS="t/api/04-jobs.t t/24-worker-jobs.t t/10-jobs-results.t" && make check-line-coverage && make test-gitlint` |
| Commit 5               | user-facing documentation            | `make test-markdown && SKIP_UPDATE_DEPS=1 make test-checkstyle && make test-gitlint` |
| Task 6 (no commit)     | re-measure after rollout             | `psql` sample of 10,000 jobs with `results_present = 0` + `test -d` per job + `du` on hits; numbers recorded here |

## Session starter

```markdown
Continue with execution plan
`/home/okurz/local/os-autoinst/openQA/tasks/160_poo210630_verified_results_removal.md`
(`tasks/` is excluded via `.git/info/exclude`, so the plan is not present in the
worktree; read it from the main checkout).
Load skills: `perl-dev`, `testing`, `git-workflow`.
Do not start any task before PR #8147 (results cleanup filter) is merged. The
worktree `~/local/os-autoinst/oqa-160-verified-removal` on branch
`feature/160_poo210630_verified_results_removal` already exists at `a0b5f8faf`;
rebase it onto the new `origin/master` once #8147 lands, then `git status`.
Start with Task 1: bump `$VERSION` in `lib/OpenQA/Schema.pm` from 108 to 109,
add `results_present BOOLEAN NOT NULL DEFAULT TRUE` to
`lib/OpenQA/Schema/Result/Jobs.pm`, regenerate the deploy files via
`./script/initdb --prepare_init` and `./script/upgradedb --prepare_upgrade`, and
add the backfill `dbicdh/_common/upgrade/108-109/010-backfill-results-present.pl`
setting `results_present = (result_size IS NULL OR result_size > 0)`.
Context you can rely on: the measured evidence in the plan shows the leftovers
are failed removals during cleanup, not late uploads; `Mojo::File::remove_tree`
ignores `File::Path` errors and `delete_results` records `result_size = 0`
regardless.
The 108 → 109 bump and the #8147 gate are approved (see Approvals). Rows 1, 3, 4
and 6 are still pending: get them recorded before writing code, never infer them.
Confirm with the user before: (a) using any schema version other than 109, (b)
running any cleanup in write mode against any database, (c) restoring a database
dump or accessing OSD, (d) pushing the branch or opening a PR, (e) writing Task 3
before verifying with `gh pr view 8147 --json state,mergedAt` that #8147 is merged.
```
