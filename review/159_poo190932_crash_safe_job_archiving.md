# 159 archiving: fix partial moves when an archiving job is terminated

Context: `OpenQA::Schema::Result::Jobs::archive` copies a job's result directory
into the archive and only then removes the source. A termination at the wrong
moment leaves either a half-populated directory at the final archive path or a
job flagged `archived = 1` whose results are still on the results volume. A
failure to remove the source directory (no crash involved) produces the same
orphan silently, because the return value of `File::Path::remove_tree` is
discarded today.
Ticket: poo#190932 (the finding came out of the review of
https://github.com/os-autoinst/openQA/pull/7779)
Base: `feature/114_archive_more` (PR #7779, head `393d3c1ce`), worktree
`~/local/os-autoinst/oqa-114-archive-more`
Worktree for this plan: `~/local/os-autoinst/oqa-159-archive-crash-safe`
Branch for this plan: `feature/159_poo190932_crash_safe_archiving`
Numbering: prefix `159` (highest existing is 158 in
`tasks/review/158_oqa1_gh_pages_ecosystem_dedup.md` and branch `feature/158_*`).

---

## Problem Statement

Current code (`lib/OpenQA/Schema/Result/Jobs.pm`, `sub archive`):

```perl
return undef if $self->archived || !$self->is_final;
my $normal_result_dir = $self->result_dir;
return $self->update({archived => 1}) unless $normal_result_dir && -d $normal_result_dir;
my $archived_result_dir = $self->add_result_dir_prefix($self->remove_result_dir_prefix($normal_result_dir), 1);
path($archived_result_dir)->make_path;
if (!File::Copy::Recursive::dircopy($normal_result_dir, $archived_result_dir)) {
    my $error = $!;
    File::Path::rmtree($archived_result_dir);
    die "Unable to copy '$normal_result_dir' to '$archived_result_dir': $error";
}
$signal_guard->retry(0) if $signal_guard;
$self->update({archived => 1});
$self->discard_changes;
File::Path::remove_tree($normal_result_dir);
return $archived_result_dir;
```

Failure windows:

1. **Partial publish.** `dircopy` writes straight into the final archive path
   (`make_path` + merge-copy). A SIGKILL/SIGTERM during the copy leaves a
   half-populated directory at the path that readers treat as a complete
   archive (web UI "Result files", `openqa-client archive`, archive downloads on
   a peer instance), with `archived = 0`.
2. **Flag before move completed.** `update({archived => 1})` happens *before*
   `remove_tree($normal_result_dir)`. A termination in between leaves the job
   flagged archived while its results still occupy the results volume. No
   query revisits such rows: the archiving candidate queries filter
   `archived => 0`, and `_archive_important_jobs_upfront` counts the job in its
   `archived_jobs` note as a success.
3. **Ignored removal errors.** `File::Path::remove_tree` reports errors via
   `$File::Path::errstr`; the result is discarded, so window 2 also happens
   without any crash, on every run, whenever removal fails (permissions, busy
   file, read-only mount).
4. **Costly retries.** A retry after window 1 re-copies the whole result
   directory into the existing (possibly partial) target.

Callers affected: `lib/OpenQA/Task/Job/ArchiveResults.pm:31`
(`archive_job_results`, notes `archived_path`) and
`lib/OpenQA/Task/Job/Limit.pm` (`_archive_important_jobs_upfront`).

## Design Decisions (all pending approval, see `## Approvals`)

- **Publish atomically inside the archive filesystem.** Copy into
  `<target>.partial.<pid>` next to the final path, `make_path` it first (the
  existing comment about a `File::Copy::Recursive` race still applies), then
  `Mojo::File::move_to` it to the final path (a `rename(2)`, which croaks on
  `EXDEV` — a wrong temp location must fail loudly, not silently copy).
  The final path therefore only ever exists complete.
- **Replace, never resume.** If the final path already exists, move it aside to
  `<target>.stale.<pid>` and remove it after publishing. This also heals
  half-populated targets left by the current code and avoids trusting an
  existing directory without metadata. Consequence: a retry always re-copies
  the job's results once; accepted, retries are rare and time-bounded.
- **Flag last.** `archived = 1` is set only after the source result directory is
  gone. Any crash then leaves `archived = 0`, which both existing archiving
  paths (retention-based enqueue and the upfront phase) pick up again.
- **Loud removal failures.** Capture `File::Path::remove_tree` errors; if the
  source still exists afterwards, `die` with the captured message. Both callers
  already handle that: `ArchiveResults` fails/retries the Minion job,
  `_archive_important_jobs_upfront` logs a warning and skips the job.
- **Signal guard position unchanged in effect:** `$signal_guard->retry(0)` is
  called right after publishing and before removing the source, so a job whose
  results are already published is not retried just to complete the removal.
- **Reconciliation as a separate, bounded Minion task** (Task 4), because a
  crash can always leave a leftover: delete result dirs of `archived = 1` jobs
  and `.partial`/`.stale` directories older than `ONE_DAY`. No new config
  setting; a module constant bounds the batch size. Scheduled daily from
  `_limit` with the existing "skip if one is already queued" pattern.
- **No database transaction** is used for the move: it cannot roll back a
  directory copy, and `rename(2)` is unavailable across the two filesystems
  the feature targets (the phase is skipped when they share a device).

Out of scope: retention semantics of the upfront archiving phase, the
same-device skip, `archive_keep_free_percentage` sizing (see PR #7779 review),
and any change to how archived results are served.

## Tasks

### Task 1 — `fix: publish archived results via atomic rename`

Files: `lib/OpenQA/Schema/Result/Jobs.pm` (`sub archive`),
`t/10-jobs-results.t` (subtest `archiving job`).

- Copy into `$archived_result_dir . '.partial.' . $$`, `make_path` that path,
  `dircopy($normal_result_dir, $tmp)`.
- On copy failure remove only `$tmp` (never the final target, never a previously
  published archive) and keep the existing die message.
- On success `path($tmp)->move_to($archived_result_dir)`.
- Keep the `archived` update and source removal order unchanged in this commit
  (Task 2 reorders them); window 2 still exists after this commit.
- Tests: copy failure leaves the source intact, no final target, no `.partial`
  leftover; success leaves no `.partial` leftover and the nested file readable.

Commit message body: `Motivation:` (a half-populated directory at the final
archive path is served as a complete archive), `Benefits:`. Estimated diff:
~25 lines lib, ~15 lines test.

### Task 2 — `fix: only flag jobs as archived once results are gone`

Files: `lib/OpenQA/Schema/Result/Jobs.pm` (`sub archive`),
`t/10-jobs-results.t`.

- If `-e $archived_result_dir`: `move_to($archived_result_dir . '.stale.' . $$)`,
  publish, then `remove_tree` the stale dir (errors logged, leftovers are
  Task 4's job).
- Move `$self->update({archived => 1})` and `discard_changes` after the source
  removal.
- Capture `remove_tree` errors (`{error => \my $err}`); if `-e
  $normal_result_dir` afterwards, `die "Unable to remove '<dir>': <err>"`.
- Tests: removal failure leaves `archived = 0` and throws; the retry after that
  succeeds and sets `archived = 1`; a pre-existing (partial) target is replaced
  by the complete copy (assert the old marker file is gone and the source's
  file is present); the existing success assertions stay green.

Commit message body: `Motivation:` (a job flagged archived while its results
still occupy the results volume is never revisited; removal errors were
ignored), `Design Choices:` (flag last, replace instead of resume),
`Benefits:`. Estimated diff: ~35 lines lib, ~40 lines test.

### Task 3 — `fix: count only moved results in upfront archiving`

Files: `lib/OpenQA/Task/Job/Limit.pm` (`sub _archive_important_jobs_upfront`),
`t/42-df-based-cleanup.t`.

- Use the return value of `archive()`: increment `archived_jobs` only when a
  path was returned, so the note reports results that actually left the results
  volume.
- Add a subtest in the existing `upfront archiving in limit_results_and_logs`
  block: `archive()` returning `undef` (mocked) is not counted, is not retried
  in the same run (`@skipped_ids`), and the loop proceeds to the next candidate.

Commit message body: `Motivation:` (the note claimed jobs as archived whose
results were not moved), `Benefits:` (operators can tell whether archiving
actually freed space). Estimated diff: ~10 lines lib, ~25 lines test.

### Task 4 — `feat: clean up leftover archived results`

Files: new `lib/OpenQA/Task/Job/LeftoverResults.pm`,
`lib/OpenQA/Shared/Plugin/Gru.pm` (register the plugin),
`lib/OpenQA/Task/Job/Limit.pm` (enqueue), `t/42-df-based-cleanup.t`.

- New task `delete_leftover_results`: own `SignalGuard`; walk the
  `resultdir()` prefix directories, parse `/^(\d+)-/` per job directory (as
  built during implementation: `resultdir()` holds `\d{5}` prefix directories,
  so a flat `opendir` on it finds no job directories), one `Jobs` query per
  prefix directory (at most 1000 job directories, `id => {-in => [...]}`,
  `archived => 1`), `remove_tree` matching dirs; note `checked`/`removed`
  counts.
- Delete `.partial`/`.stale` directories in `archivedir()/testresults` whose
  mtime is older than `ONE_DAY` (in-flight copies are younger, and only one
  `limit_results_and_logs` job runs at a time).
- No new batch-size constant: the `\d{5}` prefix directory bounds a batch to
  1000 entries by construction; stop after `DEFAULT_BATCHES_PER_MINION_JOB`
  prefix directories so a run is bounded; no config setting. Both directory
  walks return early when the directory does not exist (installations without
  archiving would otherwise fail daily).
- Enqueue from `_limit` with `delay => ONE_DAY` and only if no
  `delete_leftover_results` job is inactive/active (pattern of the
  `limit_screenshots` guard at `lib/OpenQA/Task/Job/Limit.pm`).
- Tests: orphan dir of an `archived = 1` job is removed; dir of an
  `archived = 0` job is kept; a `.partial` dir with an old mtime is removed, a
  fresh one is kept; notes assert the counts; a run with missing directories
  notes zero counts. `t/42-df-based-cleanup.t`'s `job done triggers cleanup`
  subtest selects its Minion job by task name because the new enqueue would
  otherwise be the newest job.
- Droppable: Tasks 1–3 already close the crash windows; this task only
  guarantees eventual removal.

Commit message body: `Motivation:` (leftovers after a crash or failed removal
are never revisited and consume results storage), `Design Choices:` (filesystem
walk batched by job id, `ONE_DAY` age gate), `Benefits:`. Estimated diff: ~120
lines lib, ~110 lines test.

### Task 5 — `docs: describe crash-safe archiving and leftover cleanup`

Files: `docs/UsersGuide.md` (section "Automatic archiving of old jobs"),
`etc/openqa/openqa.ini` (extend the `[archiving]` comments if a sentence is
needed, no new key).

- Document that a job is only marked archived once its results left the results
  directory, that a partially copied archive is never visible, and that leftover
  directories are removed automatically by the cleanup.
- State the remaining bound: results moved into the archive still consume
  archive space and are subject to the archive-side cleanup thresholds.
- `etc/openqa/openqa.ini` stays unchanged: the behaviour is documented, no new
  key is introduced.

### Test/verification coverage for the whole plan

- `t/10-jobs-results.t` (archive semantics), `t/14-grutasks.t` (upfront phase
  with the real `archive()`), `t/42-df-based-cleanup.t` (phase accounting and
  leftover task).
- No new dependency: `File::Path`, `Mojo::File`, `File::Copy::Recursive`,
  `Time::Seconds` are already used in `lib/`; no `dependencies.yaml` or spec
  change.

## Approvals

Approval counts only when recorded here.

| Decision                                                                                             | Approver | Date       |
| :--------------------------------------------------------------------------------------------------- | :------- | :--------- |
| Use poo#190932 (not poo#195560) as the ticket; no Redmine status/assignee change from this session    | okurz    | 2026-11-21 |
| New branch `feature/159_poo190932_crash_safe_archiving` off `393d3c1ce`, new stacked PR after #7779     | okurz    | 2026-11-21 |
| Worktree `~/local/os-autoinst/oqa-159-archive-crash-safe`, branch prefix `159`                        | okurz    | 2026-11-21 |
| Publish via `.partial.<pid>` + `rename(2)` inside the archive filesystem, croak on `EXDEV`            | okurz    | 2026-11-21 |
| Replace an existing archive target (`.stale.<pid>`) instead of skipping the copy (no resume shortcut) | okurz    | 2026-11-21 |
| `archived = 1` only after the source directory is gone; removal failure dies and is handled by callers | okurz    | 2026-11-21 |
| Task 4 as a new Minion task `delete_leftover_results`, daily enqueue, `ONE_DAY` age gate, no new setting | okurz    | 2026-11-21 |
| Task 4 included in this plan                                                                          | okurz    | 2026-11-21 |
| Docs limited to `UsersGuide.md` plus `openqa.ini` comments                                           | okurz    | 2026-11-21 |
| Verify only by unit tests; no run against o3/OSD data                                                 | okurz    | 2026-11-21 |

Session scope: all five tasks in one session, no stops in between.

## Gates

Run in the plan worktree. `tools/check-line-coverage` prints at most 500 global
lines, so filter for the touched files (expect no output).

| Commit                             | Scope                                 | Verification Command                                                                                                                                    |
| :--------------------------------- | :------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Task 1 `fix: publish … rename`     | archive publish                       | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS="t/10-jobs-results.t t/14-grutasks.t"` + coverage check + `make test-gitlint` |
| Task 2 `fix: only flag … gone`     | archive flag order, removal errors    | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS="t/10-jobs-results.t t/14-grutasks.t"` + coverage check + `make test-gitlint` |
| Task 3 `fix: count only moved …`   | upfront accounting                    | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS="t/42-df-based-cleanup.t t/14-grutasks.t"` + coverage check + `make test-gitlint` |
| Task 4 `feat: clean up leftover …` | leftover task, registration, enqueue | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS="t/42-df-based-cleanup.t t/14-grutasks.t"` + coverage check + `make test-gitlint` |
| Task 5 `docs: describe …`          | documentation only                    | `make test-markdown && SKIP_UPDATE_DEPS=1 make test-checkstyle && make test-gitlint`                                                                    |

Filtered coverage check, used by Tasks 1–4 (must print nothing):

```sh
make coverage-report-codecov
jq -r '.coverage | to_entries[] | .key as $f | .value | to_entries[] | select(.value==0) | "\($f) \(.key)"' cover_db/codecov.json \
  | grep -E 'Schema/Result/Jobs\.pm|Task/Job/(Limit|LeftoverResults)\.pm'
```

## Session starter

```markdown
Execute plan `tasks/review/159_poo190932_crash_safe_job_archiving.md` (read it fully first, then `git status`).
Load skills: `perl-dev`, `testing`, `git-workflow`; load `code-review` before the pre-push review.
Context: base is branch `feature/114_archive_more` (PR #7779, head `393d3c1ce`) in worktree
`~/local/os-autoinst/oqa-114-archive-more`; work in a new worktree
`~/local/os-autoinst/oqa-159-archive-crash-safe` and keep the base worktree untouched.
Commit unit for this session: Task 1 only (`fix: publish archived results via atomic rename` in
`lib/OpenQA/Schema/Result/Jobs.pm` plus `t/10-jobs-results.t`), with the exact Gate command from the
plan; stop after the commit and report the diff stat, the gate results and the next task.
Confirm with the user before: (a) the ticket and base-branch/PR decision, (b) creating the worktree or
any branch, (c) force-pushing to an existing PR, (d) starting Task 4 (droppable), (e) any access to
production hosts or databases.
```

## Outcome (2026-11-21)

Worktree `~/local/os-autoinst/oqa-159-archive-crash-safe`, branch
`feature/159_poo190932_crash_safe_archiving` (base `393d3c1ce`), draft PR
https://github.com/os-autoinst/openQA/pull/8150 (`After: #7779`).

- `afd55113d` fix: publish archived results via atomic rename
- `a9b4adac6` fix: only flag jobs as archived once results are gone
- `606b944e7` fix: count only moved results in upfront archiving
- `aaf972466` feat: clean up leftover archived results
- `7477240e4` docs: describe crash-safe archiving and leftover cleanup

Deviations from the plan as written:

- Task 4 batches per `\d{5}` prefix directory instead of a flat `opendir` on
  `resultdir()` plus a `LEFT_OVER_RESULTS_BATCH_SIZE` constant (see Task 4).
- Task 4 skips a copy whose `stat` fails because an archiving job may publish
  it concurrently; covered by its own subtest.
- `archive()` returns `undef` instead of the row object for jobs without
  results, so Task 3's accounting has a path-only contract; asserted in
  `t/14-grutasks.t` and in `t/42-df-based-cleanup.t`'s `job done triggers
  cleanup` subtest, which now selects its Minion job by task name.
- `etc/openqa/openqa.ini` unchanged (no sentence needed, no new key).

Verification: gates of Tasks 1–5 pass. Full `make test`: all tests successful;
`t/34-developer_mode-unit.t` (10 s) and `t/ui/10-tests_overview.t` (25 s) bail
out on their runtime limit under load, the latter identically in
`~/local/os-autoinst/oqa-114-archive-more`, so pre-existing.
