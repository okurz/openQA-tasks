# Plan: Improve Parallel Test Speedup (Task 064)

## Problem Statement

The current implementation of parallel test execution in the `feature/parallel_tests` branch shows only a 3.8% speedup (972s -> 935s) on a 16-core system. This indicates that the tests are not efficiently utilizing parallel resources or are being throttled by shared resource contention.

## Diagnosis

1.  **Missing Rules Enforcement**: The `Makefile` passes `-j$(PROVE_JOBS)` but **not** the rules from `t/testrules.yml`. This causes `prove` to run _all_ 155 tests in parallel, including those marked as sequential or unsafe.
2.  **Shared Resource Conflicts**: The shared `t/data/openqa/testresults` directory is a major bottleneck. Concurrent tests compete for deletion and repopulation of this directory, leading to race conditions and test failures.
3.  **Inefficient Retry Loop**: The entire `prove` command is wrapped in `tools/retry`. A single test failure (likely due to resource conflicts) triggers a full restart of the 155-test suite, drastically increasing the total runtime.

## Proposed Execution Plan

### Phase 1: Resource Isolation

- **Isolate Test Results**: Modify `lib/OpenQA/Utils.pm:resultdir()` to return a unique path based on the test name (e.g., `t/data/openqa/testresults_$test_name`) when `$0 =~ /\.t$/`.
- **Update Test Case Initialization**: Ensure `t/lib/OpenQA/Test/Case.pm:init_data()` creates these isolated subdirectories for each test process.

### Phase 2: Rules Enforcement

- **Update Makefile**: Modify the `test-unit-and-integration` target to pass `t/testrules.yml` to `prove` using the `--rules` flag.
- **Transition to Blocklist**: With isolated `testresults`, the majority of tests will become parallel-safe. Simplify `t/testrules.yml` to a blocklist of truly global tests (e.g., `full-stack.t`, `33-developer_mode.t`).

### Phase 3: Stability & Optimization

- **Stabilize Parallel Execution**: Verify that all 155 tests pass reliably when run in parallel with the new rules and isolation.
- **Optimize Retries**: Once stability is achieved, evaluate if the full-suite retry in `Makefile` can be replaced with more granular retries or eliminated.

## Verification

- Run `make test-unit-and-integration` and monitor concurrency.
- Benchmark runtimes against the baseline to verify significant speedup (> 50% expected).
