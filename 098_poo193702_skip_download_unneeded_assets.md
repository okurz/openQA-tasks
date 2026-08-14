# Plan: 098_poo193702_skip_download_unneeded_assets

## Motivation

`openqa-clone-job` currently downloads all assets associated with a job even if the settings specifying those assets have been modified or cleared via command line overrides (e.g., `ISO=`). This results in unnecessary downloads.

## Acceptance Criteria

- [x] AC1: `openqa-clone-job` supports to exclude specifically mentioned assets from downloading if overridden
- [x] AC2: By default `openqa-clone-job` still downloads all assets linked to the clone source job

## Design Choices

1. In `lib/OpenQA/Script/CloneJob.pm`, modify `clone_job_download_assets` to accept an optional `$settings` parameter.
2. The `$settings` parameter will represent the _new_ (overridden) settings. If not provided, it defaults to the original job settings (`$job->{settings}`).
3. Before downloading each asset in `$job->{assets}`, check if the asset name appears as an exact value in the original job settings.
4. If it does, but it _no longer_ appears as a value in the new `$settings`, skip downloading it. This means the setting that referenced it was overridden or cleared by the user.
5. Add test coverage in `t/35-script_clone_job.t` to verify that an asset is skipped when its setting is cleared (`ISO=`) and downloaded when it's preserved.

## Benefits

- Saves time and bandwidth by avoiding unnecessary asset downloads.
- Simple, generic approach that works for any asset types (ISO, HDD, ASSET\_\*, etc.) without needing a hardcoded list of setting names.
