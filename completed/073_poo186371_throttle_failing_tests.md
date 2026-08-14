# Execution Plan: 073_poo186371_throttle_failing_tests

## Motivation
Consistently failing openQA tests are expensive and can bog down an openQA instance. We want to throttle such test scenarios by automatically reducing the job priority (increasing the priority value) based on the consecutive failure history.

## Configuration Settings
Add new settings under `[misc_limits]` in `lib/OpenQA/Setup.pm` and `etc/openqa/openqa.ini`:
- `throttle_failing_job_threshold`: Number of consecutive failures before throttling kicks in. Default will be `1`.
- `throttle_failing_job_prio_step`: The priority malus to add per consecutive failure above the threshold. Default will be `10`.

## Implementation
1. **History Query Logic**: Add a helper method in `lib/OpenQA/Schema/ResultSet/Jobs.pm` to query the most recent complete jobs for a given scenario (derived from the `SCENARIO_WITH_MACHINE_KEYS` in the `settings` hash) to count consecutive failed/incomplete results.
2. **Throttling Implementation**: In `_apply_prio_throttling`, invoke the history check. If consecutive failures >= threshold, increase the job priority by `prio_step * (consecutive_failures - threshold + 1)`.
3. **Informative Message**: Append the reason (e.g., "Adjusting job priority by +20 based on 2 consecutive failures in this scenario") to the `_PRIORITY_EXPLANATION` setting.

## Testing
- Add tests in `t/10-jobs.t` to verify that repeated creation of failing jobs for the same scenario scales up the priority and populates the explanation message.
- Ensure `make tidy` and `make test-checkstyle` pass before committing.
