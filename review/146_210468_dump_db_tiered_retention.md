# 210468: `script/dump-db` atomic dump writes

Ticket: https://progress.opensuse.org/issues/210468
Downstream plan: `salt-states-openqa/tasks/023_210468_osd_backup_dump_tiering.md`

## Session starter

Read this plan and `git status` first. No implementation yet: the approval below must be recorded
before any code change or commit (git-workflow).

## Approvals

| Decision                                                           | Approver | Date       |
| ------------------------------------------------------------------ | -------- | ---------- |
| Plan only; implementation pending review                           | okurz    | 2026-11-17 |
| Prune scope unchanged: the pre-deployment dump is disposable (Q22) | okurz    | 2026-11-17 |
| Compression and archive tier rejected                              | okurz    | 2026-11-17 |
| Atomic dump write: the one remaining fix                           | okurz    | 2026-11-17 |
| Implementation in Bash with CLI flags (-f, -d, -h) and atomic trap | okurz    | 2026-11-19 |
| Standalone test t/45-dump-db.t mocking pg_dump                     | okurz    | 2026-11-19 |
| Docs reference --help as single source of truth                    | okurz    | 2026-11-19 |

## Problem

`script/dump-db` (installed as `openqa-dump-db`) runs
`pg_dump -Fc -c openqa -f ${DUMP_FOLDER}/$(date -Idate).dump` and then prunes with
`find -L ${DUMP_FOLDER} -type f -mtime +${DAYS_TO_KEEP} -delete` (default 7 days). It is started by
`openqa-dump-db.timer` (23:40) and by `backup_exec` on every rsnapshot alpha interval (~4h), so it is
retaken roughly 6×/day, each time into the same date-named file.

Space is not the problem: on OSD the folder holds 8 dailies (~15G each) plus one disposable
pre-deployment dump, and 127G on a 16T volume cannot move a `/results` alert. Compression measured
0.6–1.2% on a 2 GiB sample, so no compression, no archive tier and no retention change.

The remaining defect is the non-atomic overwrite: `-f` truncates the day's file before writing, so a
failed run destroys the same day's earlier good dump, leaves a partial file that the prune keeps for
7 days, and lets rsnapshot back up that partial file.

## Proposed change

1. **Atomic write:** dump to `${DUMP_FOLDER}/.$(date -Idate).dump.tmp`, then `mv` to the final name
   only after `pg_dump` succeeds; `trap` removes the tmp file on failure.
2. **No prune-scope change.** Deleting any file older than `DAYS_TO_KEEP` is wanted: the
   pre-deployment dump only has to survive a deployment rollback, and after a week the dailies
   supersede it.
3. **Compression and archive tier: rejected** (measured and arithmetic, recorded in 023).
4. **Docs:** `docs/Installing.md` does not document `DUMP_FOLDER` or `DAYS_TO_KEEP`.

## Tasks

### Task 1: Atomic dump write

**Files:** `script/dump-db`, `t/45-dump-db.t`.

**Acceptance criteria**

- [x] A failed `pg_dump` leaves the previous same-day dump byte-identical and no tmp file behind
- [x] A successful run produces the same `YYYY-MM-DD.dump` name and permissions as today

**Verification:** `prove -l t/45-dump-db.t`; `shellcheck script/dump-db` clean.

### Task 2: Docs

- [x] `docs/Installing.md` documents `DUMP_FOLDER` and `DAYS_TO_KEEP` via `--help` reference

## Verification gate per commit

- `prove -l` on the new test file
- `shellcheck script/dump-db`
- `tidy`/`perlcritic` only if Perl test files are touched

## Risks

| Risk                                    | Impact | Mitigation                                                                       |
| --------------------------------------- | ------ | -------------------------------------------------------------------------------- |
| Stale `.dump.tmp` left after SIGKILL    | Low    | `trap` covers normal failures; the unchanged prune removes it after the horizon  |
| Readers seeing a partially written file | Low    | `mv` within the same filesystem is atomic; readers see old or new, never partial |

## Open questions

- Create the tmp file in `DUMP_FOLDER` (same filesystem, required for atomic `mv`) and exclude
  `*.tmp` from the prune explicitly, or rely on the mtime horizon? Recommend the explicit exclusion.
