# Plan: Improve Parallel Test Execution

## Current Situation

`t/testrules.yml` used an allowlist approach where only specific tests were marked as safe for parallel execution. Many entries were outdated or referred to non-existent files. The major blocker for parallel execution is the shared `t/data/openqa/testresults` directory, which is cleared and repopulated by `OpenQA::Test::Case::init_data`.

## Goal

Switch to a blocklist approach in `t/testrules.yml` and increase the number of tests running in parallel.

## Identification of Unsafe Tests

Tests are considered unsafe if they:

- Call `OpenQA::Test::Case::init_data` (shares `t/data/openqa/testresults`).
- Use the `public` database schema (e.g., `t/full-stack.t`, `t/33-developer_mode.t`).
- Bind to fixed ports without using random `OPENQA_BASE_PORT`.

## Actions Taken

1. **Cleaned up `t/testrules.yml`**: Removed non-existent test references (e.g., `t/20-workers-ws.t`).
2. **Expanded Parallel List**: Added tests that do NOT call `init_data` and are properly isolated (increased from 37 to 72 parallel tests).
3. **Verified Safety**: Ensured parallel tests don't conflict on ports or schemas.

## Next Steps (Proposed)

1. **Isolate `testresults`**: Modify `OpenQA::Test::Case::init_data` to use a unique subdirectory for each test (e.g., `t/data/openqa/testresults/<test_name>`).
2. **Mock `resultdir`**: Ensure `OpenQA::Utils::resultdir` returns the isolated directory during tests.
3. **Switch to Blocklist**: Once `testresults` are isolated, most tests calling `init_data` will become safe. The rules file can then be simplified to a small blocklist of truly unsafe tests (those with fixed ports or global state).

## Long-term Blocklist (Truly Unsafe)

- `t/05-scheduler-full.t`
- `t/24-worker-engine.t`
- `t/24-worker-jobs.t`
- `t/24-worker-overall.t`
- `t/33-developer_mode.t`
- `t/43-scheduling-and-worker-scalability.t`
- `t/45-make-update-deps.t`
- `t/full-stack.t`


## benchmark results

After fixes:

```
## mean runtime: 994259±43590.41 ms
```
