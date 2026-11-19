# 126_poo193345: openqa-clone-job checks missing assets only after overrides

Follow-up of https://progress.opensuse.org/issues/193345 (resolved, this was
out of scope there).

## Problem

`openqa-clone-job … ISO=` already skips _downloading_ the cleared asset
(commit 227032b9e, `lib/OpenQA/Script/CloneJob.pm:213-218`), but
`_check_for_missing_assets` (`CloneJob.pm:154-168`, called at `:210`) checks
the original job's full `missing_assets` list before overrides are considered.
Cloning dies on an asset that is cleared by the override unless
`--ignore-missing-assets` or `--skip-download` is given.

## Implementation

- [ ] Extract the computation of referenced asset names from `$settings`
      (`CloneJob.pm:213`) into a helper, e.g.
      `_referenced_assets ($settings)` returning a hashref.
- [ ] Pass the result to `_check_for_missing_assets` and skip missing assets
      whose name (`type/name` split) is not referenced by the new settings.
- [ ] Reuse the same helper in `clone_job_download_assets` (no duplication).

## Tests

- [ ] `t/35-script_clone_job.t` (around `:216`, `@missing_assets`):
  - missing `iso/foo.iso` with override `ISO=` → no error, no download
  - missing `iso/foo.iso` with override `ISO=bar.iso` → no error for
    `foo.iso`
  - missing `hdd/some.qcow2` still referenced → still dies with the existing
    message
- [ ] `COVERAGE=1 make test-unit-and-integration TESTS=t/35-script_clone_job.t`
      and `make check-line-coverage`.

## Commit

`fix(clone-job): Ignore missing assets cleared by overrides`
