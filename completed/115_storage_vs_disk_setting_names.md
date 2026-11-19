# 115 Resolve the "storage" vs "disk" naming collision in free-space settings

No Redmine ticket yet; spun off from the naming review in
`tasks/114_archive_more.md`. Create a poo ticket before implementation if this
should be tracked.

## Motivation

openQA has three families of free-space thresholds and two of them differ by a
single, meaningless word:

| Setting family                                               | Section         | Meaning                                                                                             | Default |
| ------------------------------------------------------------ | --------------- | --------------------------------------------------------------------------------------------------- | ------- |
| `results\|archive\|assets_min_free_storage_space_percentage` | `[scheduler]`   | suspend scheduling below this (`OpenQA::Utils::storage_below_threshold`, `lib/OpenQA/Utils.pm:982`) | 5       |
| `results\|archive_min_free_disk_space_percentage`            | `[misc_limits]` | df-based cleanup deletes until this                                                                 | undef   |
| `result\|asset_cleanup_max_free_percentage`                  | `[misc_limits]` | skip/abort cleanup above this                                                                       | 100     |

`archive_min_free_storage_space_percentage` (suspend scheduling) versus
`archive_min_free_disk_space_percentage` (delete from the archive) is a trap for
operators and for anyone reading logs. "disk" is also the wrong term: openQA
measures file systems via `df`, which may be network or volume-manager backed.
"storage" is the generic term already used by the scheduler family, by
`*_storage_duration` and by `storage_below_threshold`.

## Key constraint

A literal `disk` → `storage` rename makes the collision _total_:
`[misc_limits] results_min_free_storage_space_percentage` and
`[scheduler] results_min_free_storage_space_percentage` would then be identical
strings distinguishable only by section — worse than today for grep, logs and
error messages. The rename must therefore also add a token that names the
_action_ the threshold governs.

## Target names

| Old (`[misc_limits]`)                    | New (`[misc_limits]`)                 |
| ---------------------------------------- | ------------------------------------- |
| `results_min_free_disk_space_percentage` | `result_cleanup_min_free_percentage`  |
| `archive_min_free_disk_space_percentage` | `archive_cleanup_min_free_percentage` |
| `dry_min_free_disk_space_cleanup`        | `cleanup_min_free_dry_run`            |

Rationale:

- Pairs exactly with the existing `result_cleanup_max_free_percentage` and
  `asset_cleanup_max_free_percentage`: `<what>_cleanup_<bound>_free_percentage`,
  one family, one shape, `min`/`max` as the only difference.
- The medium word is dropped rather than replaced because the `max_free`
  siblings already omit it; adding "storage space" only to the `min` variant
  would break the pair. "disk" disappears either way, which is the actual
  requirement.
- `cleanup` versus the scheduler family's `storage_space` keeps both readable in
  isolation, e.g. in a Minion job failure message.
- Singular `result`/`archive` follows the existing `result_cleanup_*` /
  `asset_cleanup_*` keys.
- `[scheduler]` keys stay untouched; "storage" remains the canonical term for
  the medium there.

Alternative considered and rejected:
`result_cleanup_min_free_storage_space_percentage` — keeps "storage" literally
and is still unique via `cleanup`, but is 47 characters and inconsistent with
its own `max_free` sibling. Switch to this variant before starting if the
explicit medium term is preferred over consistency within the family.

Code identifiers renamed along with the settings:

- `OpenQA::Task::Utils::is_disk_usage_below_percentage` →
  `is_storage_usage_below_percentage`
- `OpenQA::Task::Utils::finish_job_if_disk_usage_below_percentage` →
  `finish_job_if_storage_usage_below_percentage`
- `OpenQA::Task::Job::Limit::_check_remaining_disk_usage` →
  `_check_remaining_storage_usage`
- "disk space"/"disk usage" prose in cleanup comments, `openqa.ini` and the
  cleanup sections of `docs/UsersGuide.md` → "storage space"/"storage usage".
  Unrelated uses of "disk" (QEMU `HDD_*`, `NUMDISKS`, worker cache docs) stay.

## Scope (verified occurrences)

`lib/OpenQA/Task/Job/Limit.pm` (12), `t/42-df-based-cleanup.t` (28),
`etc/openqa/openqa.ini` (5), `lib/OpenQA/Task/Utils.pm` (4),
`lib/OpenQA/Setup.pm` (3), `lib/OpenQA/Task/Asset/Limit.pm` (2),
`docs/UsersGuide.md` (2 + prose), `t/04-scheduler.t` (1, subtest name),
`templates/webapi/admin/group/group_property_editor.html.ep:270`, plus the
`t/config.t` documentation check. Generated artifacts (`docs/build/`,
`cover_db*/`, `nytprof/`) are out of scope.

## Tasks (atomic, one commit each)

### 1. refactor: rename the storage-usage helper functions

- Rename the three subs listed above including the `@EXPORT_OK` list in
  `lib/OpenQA/Task/Utils.pm:15` and both call sites
  (`lib/OpenQA/Task/Job/Limit.pm:12,47,89`,
  `lib/OpenQA/Task/Asset/Limit.pm:9,53`).
- Update the imports and calls in `t/42-df-based-cleanup.t`.
- Pure rename, no config impact, no behavior change; existing tests must pass
  unmodified apart from the identifier change.

### 2. feat: rename the free-space cleanup settings, keep the old names working

- New keys in `lib/OpenQA/Setup.pm` `misc_limits` defaults; keep the three old
  keys registered as deprecated so `t/config.t`'s completeness check stays
  meaningful.
- Map old → new in `OpenQA::Setup::read_config` with a deprecation warning,
  following the `[audit] blacklist` → `blocklist` precedent
  (`lib/OpenQA/Setup.pm:384-387`). Old key wins nothing: if both are set, prefer
  the new one and warn about the conflict.
- Update `etc/openqa/openqa.ini` (`:314-325`), the admin template
  (`templates/webapi/admin/group/group_property_editor.html.ep:270`) and all
  usages in `lib/OpenQA/Task/Job/Limit.pm`.
- Tests: rename the settings in `t/42-df-based-cleanup.t` and the subtest name
  in `t/04-scheduler.t`; extend the skip list in `t/config.t:189` for the
  deprecated keys; add a deprecation subtest modelled on `t/config.t:121-139`
  asserting the mapping and the warning.
- Removal of the compatibility aliases is explicitly _not_ part of this task;
  it needs its own ticket and a release note, as with `blacklist`.

### 3. doc: document the three threshold families distinctly

- `docs/UsersGuide.md`: use the new names, replace "disk" with "storage" in the
  cleanup sections, and add a short table contrasting the three families
  (suspend scheduling / cleanup lower bound / cleanup skip threshold) so the
  remaining similarity between `[scheduler] archive_min_free_storage_space_percentage`
  and `[misc_limits] archive_cleanup_min_free_percentage` is explained rather
  than merely tolerated.

## Verification (per commit)

- `make tidy` and `make test-checkstyle` before committing.
- `make test-unit-and-integration TESTS=t/42-df-based-cleanup.t`,
  `TESTS=t/config.t`, `TESTS=t/04-scheduler.t`, `TESTS=t/14-grutasks.t`.
- `COVERAGE=1` run for `t/config.t` plus `make check-line-coverage` for the new
  deprecation branch.
- Final check that `grep -rn 'disk_space\|disk_usage'` returns nothing outside
  generated artifacts and `tasks/`.
- `make test-gitlint` after each commit.

## Sequencing and risks

- **Do this before task 114.** Both touch `Limit.pm`, `Setup.pm`, `openqa.ini`
  and `t/42-df-based-cleanup.t`; landing the rename first lets 114 introduce
  `result_archiving_max_free_percentage` / `result_archiving_max_seconds`
  consistently with the renamed family and avoids a second rename round.
- External consumers must be checked: OSD/o3 salt pillars may set the old keys.
  The compatibility mapping keeps them working, but the deployment
  configuration should be updated in a follow-up outside this repository.
- Users who set the old keys get a warning per web UI/gru start; acceptable and
  consistent with the `blacklist` precedent.
