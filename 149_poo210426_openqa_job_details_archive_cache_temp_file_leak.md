# 149 (poo#210426): openQA leaks temporary files in the job details archive cache

Ticket: https://progress.opensuse.org/issues/210426
Repository: `openQA` (this checkout), branch `feature/149_oqa1_poo210426_archive_cache_temp_file_leak`.
Discovered during the storage analysis of `tasks/148_poo210483_osd_results_full_distribution_of_test_results.md`
(its `webui/ 191 GB` entry, a `du -sk` KiB value: 182 GiB). Scope here is **only** the job details archive cache
(`/var/lib/openqa/webui/cache/archives`). Non-goals: relocating `images/`, archive-volume
tiering, and every retention decision of plan 148 — those are handled separately.

## Problem

The on-demand "Download all" ZIP cache (`[job_details_archive]`, `OpenQA::Archive`) leaks
temporary files whenever an archive creation does not complete, and the cache cleanup can
never see them. On `openqa.suse.de` the cache is **182 GiB**, of which **181.1 GiB is 7 stale
`job_*.zip.tmp.<hex>` files** — one of them 37.2 GB (`job_22927865.zip.tmp.EBB47459`,
2026-06-22 08:08). The configured limit there is the default of 5 GB, and OSD sets no
`[job_details_archive]` section at all, so the limit has not been effective for months.

Measured (read-only, `openqa.suse.de`, 2026-11-19):

| item | value |
|---|---|
| `du -sk /var/lib/openqa/webui/cache` | 191,240,328 KiB (182.4 GiB) |
| `du -sk .../cache/archives` | 191,160,856 KiB (182.3 GiB) |
| `job_*.zip.tmp.<hex>` | 7 files, 181.1 GiB |
| `job_*.zip` (real archives) | 6 files, 1.2 GiB |
| `job_*.zip.lock` | 163 files, 0 bytes |
| largest single leak | 37,224,287,339 B, `job_22927865.zip.tmp.EBB47459` |

Root causes, all in `lib/OpenQA/Archive.pm`:

1. `create_job_archive` (L100–L108) removes `$archive_name.tmp.<hex>` only when
   `writeToFileNamed` returns a non-`AZ_OK` status. Any exception (`die` of the `rename`),
   process kill or Minion `expire`/`SignalGuard` retry leaves the partial payload behind.
   `File.pm#archive` enqueues the Minion job with `expire => 3600`, so a long-running
   >1 h archive creation is simply dropped.
2. `_perform_cache_cleanup` (L126) only greps `^job_\d+(?:_(?:all|resultfiles|ulogs|assets))?\.zip$`,
   so `.tmp.<hex>` and `.lock` files are invisible to the accounting and are never removed.
   `is_cache_limit_exceeded` therefore compares 1.2 GiB against the 5 GB limit and returns
   "within limits" while 181 GiB of garbage sits next to it.
3. `cleanup_cache` is only called from `create_job_archive` (L99), i.e. only when somebody
   downloads. A leaked file no longer causes downloads, so nothing ever revisits the cache.
4. `create_job_archive` creates `$archive_name.lock` (L49–L53) and never removes it;
   `flock` is released on exit, so the 163 files are inert but permanent.
5. `cleanup_cache()` runs *before* `writeToFileNamed`, so a freshly created archive is not
   part of the size accounting — the cache may exceed the limit by one archive until the
   next creation.

Evidence limitation: `minion_jobs` on OSD is pruned after ~7 days, so the 7 leak events
(2026-06-20…22) can no longer be attributed to a specific job/error.

## Tasks

Every task is one session and one commit, except T5 (ops on OSD, gated by approval, no commit).

### T1: remove the temporary file when archive creation fails
**Files:** `lib/OpenQA/Archive.pm`, `t/60-archive-download.t`.
**Commit:** `fix(archive): remove temporary zip files when archive creation fails`

Wrap the write/rename in a `scope_guard` that removes `$temp_path` if it still exists, so
the `AZ_*` error path and any `die` (e.g. a failing `rename`) both clean up. Keep the
current behaviour of a failing creation not producing a `.zip`.

**Acceptance criteria**
- [ ] After a mocked `AZ_IO_ERROR` no `job_*.zip.tmp.*` remains in the cache directory (extends the existing `Create archive failure` subtest)
- [ ] After a failing `rename` (mocked) no `job_*.zip.tmp.*` remains and the error still propagates
- [ ] A successful creation leaves neither a `.tmp` file nor a modified pre-existing archive

### T2: clean up stale temporary and lock files
**Files:** `lib/OpenQA/Archive.pm`, `t/60-archive-download.t`.
**Commit:** `fix(archive): clean up stale temporary and lock files in the job details archive cache`

Extend `_perform_cache_cleanup` so that, in addition to `.zip` rotation:
* `job_*.zip.tmp.<hex>` older than a stale threshold (`STALE_ARCHIVE_AGE_SECONDS`, 24 h) is
  counted in `$current_cache_size` and removed;
* a stale `.lock` file is removed when its `flock` can be acquired non-blocking, so an
  in-progress creation (which holds the lock for the whole `addTree`/write phase) is never
  mistaken for a leftover;
* the success path removes its own lock file right after the `rename`, before releasing the
  lock, since the early `return $archive_path if -e $archive_path` short-circuit then
  protects any concurrent request.

**Acceptance criteria**
- [ ] A `.tmp` file with an mtime older than the threshold is removed; one newer than the threshold is kept
- [ ] A stale `.tmp`/`.lock` pair whose lock is held by the test (flock) is kept and logged
- [ ] A successful `create_job_archive` leaves no `.lock` file behind for that archive name
- [ ] `.tmp` files are included in the size accounting (`is_cache_limit_exceeded` sees them)

### T3: enforce the cache limit without a download
**Files:** `lib/OpenQA/Task/Job/Limit.pm`, `t/42-df-based-cleanup.t`.
**Commit:** `fix(cleanup): clean the job details archive cache independently of downloads`

Call `OpenQA::Archive::cleanup_cache()` at the top of `_limit`, i.e. **before** the
`result_cleanup_max_free_percentage` early return that skips the whole pass (on OSD the pass
is skipped as soon as more than 16 % is free, which is exactly when a leak has time to grow).
The call is cheap: one `readdir`+`stat` of a directory with a few hundred entries, and
`cleanup_cache` returns immediately when the directory does not exist. Deliberately no new
Minion task and no new script, to avoid a salt change for this fix.

**Acceptance criteria**
- [ ] With an over-limit cache directory and a free percentage above `result_cleanup_max_free_percentage`, `_limit` trims the cache and still finishes with the "sufficient free space" note
- [ ] When the cache directory does not exist the cleanup pass behaves exactly as before (no new notes, no errors)
- [ ] Cache rotation does not delete the archive that is currently being served (cleanup still runs before a new archive is written in `create_job_archive`)

### T4: document the cache and its limits
**Files:** `docs/UsersGuide.md`, `etc/openqa/openqa.ini` (comments only).
**Commit:** `docs: document the job details archive cache and its automatic cleanup`

`[job_details_archive]` is currently undocumented outside `etc/openqa/openqa.ini`: add a
short subsection to the archiving part of the UsersGuide with the cache directory, the
`*_cache_limit_gb` / `*_min_free_percentage` / `*_watermark_percentage` settings, and the
fact that the cache is also trimmed by the daily cleanup and that stale temporary and lock
files are removed automatically.

**Acceptance criteria**
- [ ] All four `[job_details_archive]` settings are documented with their defaults
- [ ] The documented cleanup trigger matches the behaviour implemented in T2/T3
- [ ] `etc/openqa/openqa.ini` comments mention the automatic removal of stale `*.tmp.*`/`*.lock` files

### T5: remove the leaked files on OSD — done 2026-11-19
**Depends on:** nothing (the leaked files are never read: `download_archive` serves only the
     exact `archivepath` from the request and `_perform_cache_cleanup` ignores them).

Pre-flight: newest `.lock` file was 2026-11-16 12:17 and `0` lock files were modified within
24 h, so no `create_zip_archive` run was in flight; 7 `.tmp` files (oldest 2026-06-22) and
163 `.lock` files, plus the 6 real archives to keep.

Executed (approved by okurz; elevation needed because the directory is `geekotest:nogroup`):

```sh
ssh osd 'sudo -n -u geekotest find /var/lib/openqa/webui/cache/archives -maxdepth 1 -type f \(
  -name "job_*.zip.tmp.*" -o -name "job_*.zip.lock" \) -delete'
```

Result:

| item | before | after |
|---|---|---|
| entries in `webui/cache/archives` | 176 (7 tmp, 6 zip, 163 lock) | 6 |
| `du -sk …/archives` | 191,160,856 KiB (182.3 GiB) | 1,278,952 KiB (1.2 GiB) |
| `du -sk /var/lib/openqa/webui/cache` | 191,240,328 KiB (182.4 GiB) | ≈ 1.2 GiB |
| `df -h /var/lib/openqa` | 15T used, 1.1T avail, 94 % | 15T used, 1.3T avail, 93 % |

Deleted: 194,439,053,055 B (181.1 GiB) across 7 `job_*.zip.tmp.<hex>` files plus 163
zero-byte `.lock` files. Free space is now ≈8 % of 16 T, still below
`result_cleanup_max_free_percentage = 16`, so the nightly cleanup continues to run (the leak
is not masked by the skip threshold).

Kept: the 6 real ZIPs (`job_25462795_assets` 1.2 GiB, `job_25501672_*`, `job_25551331_*`,
`job_25480700_ulogs`). Checked that their jobs' `testresults` dirs still exist
(25462795, 25480700, 25501672, 25551331 → all `dir-present`), so they are regenerable anyway
and their removal was not needed for the capacity win.

The `webui/ 191 GB` figure in the storage layout table of plan 148 is superseded: it is a
`du -sk` KiB value, i.e. 182 GiB, and is now 1.2 GiB.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Deleting a `.tmp` file that is still being written | Lost work, no corruption (the `.zip` is written to `$temp_path` then renamed) | stale threshold 24 h plus non-blocking `flock` on the sibling `.lock` in T2 |
| Deleting a `.lock` file while a creation is in progress | Two writers for the same archive name → wasted work on a duplicate ZIP | remove only when `LOCK_EX\|LOCK_NB` succeeds; success path unlinks before releasing the lock |
| Removing the 6 remaining ZIPs would destroy evidence for jobs whose result dir is gone | Lost job details | T5 keeps them; they are not part of the leaked 181 GiB |
| Cache cleanup now runs during the 25 h cleanup pass, adding I/O on the full volume | Slightly longer `limit_results_and_logs` | cost is one directory listing; no recursion, no `du` |
| OSD keeps the default 5 GB limit, so legitimate archives beyond 5 GB are rotated away | Users downloading an old 37 GB archive have to wait for regeneration (which yields nothing once the result dir is gone) | open question 1; not changed by this plan |
| `.lock` files are still created for archive names that never complete | Same leak class, smaller | `.lock` files are now removed in the success path and by the stale sweep; the payload class is fixed in T1 |

## Open questions

1. Should OSD configure `[job_details_archive]` at all (e.g. `job_details_archive_cache_limit_gb = 50`,
   `job_details_archive_cache_dir` on a volume with headroom) instead of running on the 5 GB
   default, given that 37 GB archives are requested there? Out of scope for the code fix,
   needs a decision with plan 148's capacity numbers.
2. Resolved: the fix belongs to poo#210426 ("webui folder with 183G"); poo#210483 stays the
   parent for the /results retention work of plan 148, where the leak was found.
3. `create_zip_archive`'s Minion `expire => 3600` makes multi-hour `addTree` runs of large
   result dirs fail by design — is that intended, or should it be raised/retried?

## Approvals

| Decision | Approver | Date |
|---|---|---|
| Delete the 7 stale `job_*.zip.tmp.*` (181.1 GiB) and 163 `.lock` files in `/var/lib/openqa/webui/cache/archives` on OSD, keeping the 6 real ZIPs | okurz | 2026-11-19 |
| Scope limited to the job details archive cache; `images/` relocation and archive-volume tiering are handled separately | okurz | 2026-11-19 |
| Stale threshold 24 h and lock-aware removal for `.tmp`/`.lock` (T2) | pending | – |
| Enforce the cache limit from `limit_results_and_logs` instead of a new Minion task/script (T3) | pending | – |
| Plan approved for implementation as written | pending | – |

## Gates

Gate before every commit (repo rule): `make tidy && make test-checkstyle`.
Then the task-specific gate, then `make test-gitlint` after the commit exists.

| Commit / task | Exact verification command |
|---|---|
| T1 `fix(archive): remove temporary zip files …` | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/60-archive-download.t && make check-line-coverage && make test-gitlint` |
| T2 `fix(archive): clean up stale temporary and lock files …` | same as T1 |
| T3 `fix(cleanup): clean the job details archive cache …` | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/42-df-based-cleanup.t && COVERAGE=1 make test-unit-and-integration TESTS=t/60-archive-download.t && make check-line-coverage && make test-gitlint` |
| T4 `docs: document the job details archive cache …` | `make test-markdown && make test-checkstyle && make test-gitlint` |
| T5 (ops, no commit) | `du -sk /var/lib/openqa/webui/cache/archives`; `ls -1 …/archives \| wc -l`; `df -h /var/lib/openqa` |

## Session starter

```
Read tasks/149_poo210426_openqa_job_details_archive_cache_temp_file_leak.md in full and run
`git status` first. Load the `perl-dev`, `testing`, `openqa` and `git-workflow` skills before
writing code. Work on exactly one task per session, in this order: T1 → T2 → T3 → T4; T5 is
approved and independent of the code (it may run first).

Commit unit for this session: T1 — one commit
`fix(archive): remove temporary zip files when archive creation fails` on a branch
`feature/149_archive_cache_temp_file_leak`, touching only `lib/OpenQA/Archive.pm` and
`t/60-archive-download.t`, with the T1 acceptance criteria and the T1 gate from `## Gates`.
Do not modify the plan file's other sections.

Actions that need explicit confirmation before you run them, every time: any write on OSD
(including the T5 deletion, even though it is approved — confirm the exact command and paths
first), any `git push`, PR creation or merge, and any other deletion including `git clean`.
Read-only SQL/`ssh` on OSD is approved only for verification commands in this plan. Stop after
the commit.
```

## Implementation status (branch `feature/149_oqa1_poo210426_archive_cache_temp_file_leak`, based on `origin/master` 4306a4248)

| Task | Commit | Gate |
|---|---|---|
| T1 | `09ae687fe` fix(archive): remove temporary zip files when archive creation fails | `t/60-archive-download.t` PASS, `Archive.pm` 100 % stmt |
| T2 | `2fa6fa3a7` fix(archive): clean up stale temporary and lock files in the cache | `t/60-archive-download.t` PASS, `Archive.pm` 100 % stmt |
| T3 | `5f892da8c` fix(cleanup): clean the job details archive cache without downloads | `t/42-df-based-cleanup.t` + `t/60-archive-download.t` PASS, added line covered |
| T4 | `78c5eaf5f` docs: document the job details archive cache and its cleanup | `make test-markdown` PASS |
| T5 | done 2026-11-19, see above | 182 GiB → 1.2 GiB, `df` 1.1 T → 1.3 T free |

`make tidy` and `make test-checkstyle` PASS on the final commit, `make test-gitlint` PASS.

Pre-push review (nested `pi -p` session, `global.anthropic.claude-haiku-5-5`, prompt
`/pre-push-review reviewer=main`, verdict `ready`, 206 changed lines): applied the one
`should-fix` (the duplicated cache-listing expression is now `_cache_files`) and a comment on the
lock-file invariant; reworded the T3 motivation so every commit quotes the same 181 GiB.

PR: https://github.com/os-autoinst/openQA/pull/8138 (branch
`feature/149_oqa1_poo210426_archive_cache_temp_file_leak`, base `master`, 4 commits, all of them
carrying `Related issue: https://progress.opensuse.org/issues/210426`). Accepted
as-is: Mojo::File's `open` croaks with the path and `$!`, so the lock-specific message is not
lost; the residual TOCTOU window on orphaned lock files is harmless (atomic `rename`, random
temporary names).
Untested/next: `t/14-grutasks.t` is unaffected in this checkout but is worth running in CI;
pushed to `okurz/openQA` as PR #8138.

Deviations from the task text:

* T1: a *failing rename* cannot be staged (an existing destination short-circuits on
  `-e $archive_path`), so the die path is covered via a mocked `writeToFileNamed` that creates
  the temporary file and dies. Both that and the `AZ_*` error path assert that no
  `.tmp` file survives.
* Gates: `make check-line-coverage` aborts on any uncovered line of the whole codecov report,
  which a single test file can never satisfy. Verified instead with
  `DEVEL_COVER_DB_FORMAT=JSON cover -report text -select_re 'lib/OpenQA/Archive\.pm'` (100.0 %)
  and the line-level report for the added line in `Task/Job/Limit.pm`.
* T2: stale lock files are only removed when their archive *and* temporary file are gone, which
  is stricter than "lock not held" and rules out a second writer for a live archive name.
* T4 documents the `[job_details_archive]` settings by name only and points at
  `etc/openqa/openqa.ini` for their defaults, so the guide cannot go stale when a default changes.
* Lock files are opened via `Mojo::File::open` (`$lock_path->open('>')`, `->open('<')`) instead of
  a 3-argument `open`, including the existing creation path in `create_job_archive`.
