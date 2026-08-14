# 080 - [poo198551] Include parent job group name in priority check

The `prio_group_parameters` configuration should consider parent job group names when adjusting job priorities.

## Problem
Currently, only the immediate job group name is checked. If a job belongs to a "Functional" group under "Development", a regex for "Development" will not match.

## Proposed Changes

### `lib/OpenQA/Schema/ResultSet/Jobs.pm`
- Modify `_apply_prio_throttling` to use `full_<property>` method if it exists on the job group object.

### `t/api/04-jobs.t`
- Add a test case to verify priority adjustment based on a parent job group's name.

## Verification
- Run `make tidy` and `make test-checkstyle`.
- Run `make test-unit-and-integration TESTS=t/api/04-jobs.t`.
- Verify the new test case passes.
