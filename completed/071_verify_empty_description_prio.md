# Task: Verify priority increase for empty job group description

The feature "increase priority based on job group properties" should correctly handle job groups with empty descriptions when configured.

## Current state

- `prio_group_parameters` allows scaling priority based on job group properties.
- Matching logic in `OpenQA::Schema::ResultSet::Jobs::_apply_prio_throttling` uses `defined $val && $val =~ $rule->{regex}`.
- If a job group description is `NULL`, it will not match `^$` because `defined $val` will be false.

## Plan

1. Extend `t/api/04-jobs.t` to include a test case for empty job group descriptions.
2. Verify that if description is `undef` (NULL in DB), the priority is NOT increased.
3. Fix the logic in `lib/OpenQA/Schema/ResultSet/Jobs.pm` to treat `undef` as empty string for property matching.
4. Verify that the priority is now increased.
5. Run `make tidy` and `make test-checkstyle`.
6. Final verification with `make test-unit-and-integration TESTS=t/api/04-jobs.t`.

## Test Adaptation

Add a subtest in `t/api/04-jobs.t`:

- Create a job group with `NULL` description (or use an existing one and ensure it's `NULL`).
- Set `prio_group_parameters = description:^$:73`.
- Post a job in that group.
- Assert priority is increased by 73.
