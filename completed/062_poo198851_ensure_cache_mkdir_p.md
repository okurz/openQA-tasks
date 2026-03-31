# Task 062: Ensure cache service does not fail on non-existent parent directories

## Motivation

The openQA worker cache service fails when `rsync` attempts to create the `tests` directory within a non-existent parent directory. This can happen if `/var/lib/openqa/cache/FQDN` is missing.

## Acceptance Criteria

- **AC1:** The openQA worker cache service does not fail on non-existent parent directories within the top-level cache dir.

## Design Choices

1. Reproduce the failure with a new test case in `t/repro_poo198851.t`.
2. Add `Mojo::File::path($to)->make_path` in `lib/OpenQA/CacheService/Task/Sync.pm`'s `_cache_tests` before executing `rsync`.
3. Verify that the new test case passes.

## Implementation Plan

1. Create `t/repro_poo198851.t` to reproduce the failure.
2. Edit `lib/OpenQA/CacheService/Task/Sync.pm` to create the parent directory.
3. Run tests and verify the fix.
4. Run `make tidy` and `make test-checkstyle`.
