# Plan: Resolve Instability in t/25-cache-service.t

## Context

Test `t/25-cache-service.t` has shown intermittent failures in the `OpenQA::CacheService::Task::Sync` subtest. The problem, as seen in `tasks/048_fix_unstable_cache_service.log`, manifests as `stderr_like` failing to capture expected log output during a simulated `rsync` failure.

## Root Cause Analysis

The subtest `OpenQA::CacheService::Task::Sync` (line 666 in `t/25-cache-service.t`) starts a background Minion worker (`worker_2`) while also relying on `perform_minion_jobs` to run the task in the foreground.

When a background worker is present:

- There is a race condition where the background worker process may pick up the enqueued `rsync` task before the foreground worker loop (`perform_minion_jobs`) can.
- The background worker's `STDERR` is not captured by the `stderr_like` block in the foreground process.
- Consequently, when the task fails and logs its error, it is printed to the background worker's `STDERR` (visible in overall `prove` output) but appears empty to the `stderr_like` assertion.

## Execution Plan

### 1. Code Modification

Modify `t/25-cache-service.t` to remove the background worker from the `OpenQA::CacheService::Task::Sync` subtest. The tasks should be exclusively handled by the foreground `perform_minion_jobs` call to ensure stable output capture.

**File:** `t/25-cache-service.t`
**Action:** Delete lines 667, 668, and 670.

### 2. Verification

Since the issue is intermittent, verification requires repeated execution.

- **Unit Test Execution:**
  ```bash
  for i in {1..10}; do make test-unit-and-integration TESTS=t/25-cache-service.t || break; done
  ```
- **Static Analysis & Style:**
  ```bash
  make tidy
  make test-checkstyle
  ```

### 3. Cleanup

Ensure no temporary files from `rsync` tests (in `/tmp` or `t/cache.d`) are left behind if the test is interrupted.

## Success Criteria

- `t/25-cache-service.t` passes consistently (10/10 runs).
- `make tidy` and `make test-checkstyle` pass without issues.
- No regression in other subtests of `t/25-cache-service.t`.

## Risks and Mitigations

- **Risk:** The removal of `worker_2` might reduce the realism of the test by not using a separate process.
- **Mitigation:** The Sync task functionality is primarily about its execution logic and interaction with `rsync`. This is fully verified in the foreground. Other tests already verify background worker registration and interaction. Stability is prioritized here to ensure CI reliability.
