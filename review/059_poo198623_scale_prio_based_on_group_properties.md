# Task: Scale priority based on job group properties (poo198623)

## Motivation

Job groups like "Development" should not block production job group tests. We need to extend our dynamic adjustment of priorities to cover job group parameters (name, description).

## Acceptance Criteria

- **AC1:** By default, job groups with "Development" in the name add +50 to the `prio` value.
- **AC2:** Job group names (or more generalized parameters) and their priority impact are configurable in `openqa.ini` under `[misc_limits]`, next to `prio_throttling_parameters`.

## Proposed Changes

### 1. Configuration (lib/OpenQA/Setup.pm)

- Update `default_config` to include `prio_group_parameters` in the `misc_limits` section.
- Default value: `name:Development:50,description:^$:100`.
- Add a helper method `_load_prio_group_throttling` to parse this new configuration string.
- The format will be `property:regex:priority_increment`.
- Call this helper in `read_config` and store results in `$config->{misc_limits}->{prio_group_data}`.

### 2. Priority Calculation (lib/OpenQA/Schema/ResultSet/Jobs.pm)

- Modify `_apply_prio_throttling` to accept an optional third argument `$group`.
- If `$group` is provided, iterate over `prio_group_data`:
  - Check if the specified property (`name` or `description`) matches the regex.
  - If it matches, add the increment to `$new_job_args->{priority}`.
- Update `create_from_settings` to pass the `$group` object (retrieved at line 124) to `_apply_prio_throttling`.

### 3. Documentation (etc/openqa/openqa.ini)

- Add comments explaining `prio_group_parameters` and its default values.

### 4. Tests

- Update `t/api/04-jobs.t` to include subtests for job group-based priority adjustments:
  - Verify +50 for "Development" in name.
  - Verify +100 for empty description.
  - Verify multiple matching rules.
  - Verify configuration overrides.

## Verification Plan

1. Run `make tidy` to ensure code style compliance.
2. Run `make test-unit-and-integration TESTS=t/api/04-jobs.t` to verify the new functionality.
3. Run `make test-checkstyle` to ensure no linting errors.
4. Manually verify with different `openqa.ini` configurations if possible.
