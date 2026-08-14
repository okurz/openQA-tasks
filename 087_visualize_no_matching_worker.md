# Plan: Visualize No Matching Worker Online

## Goal
In `lib/OpenQA/Scheduler/Model/Jobs.pm`, distinguish the "no free workers" rejection reason into two separate states:
1. `no free workers for class @needed` (Workers with requested classes are online but busy).
2. `no workers online for requested class @needed at all` (No workers with requested classes are online, busy or free).

## Performance Impact Evaluation
1. **Database Load:**
   - Currently, `determine_free_workers` runs a single DB query on the `Workers` table filtering by `job_id => undef`.
   - The plan requires querying all online workers (regardless of `job_id`). We can retrieve all online workers in one DB query and then derive the `free_workers` array in memory by filtering for `job_id => undef`.
   - Result: The number of DB queries remains identical (1 query per schedule loop). The amount of data retrieved over the DB connection slightly increases because we fetch data for busy workers as well, but this table is very small (active workers count is typically in the hundreds at most). Memory usage grows marginally.
   - **Conclusion:** Performance impact is negligible.

2. **Processing Time:**
   - `_allocate_jobs` processes a secondary check `_matching_workers($jobinfo, $online_workers)` ONLY when the initial `$free_workers` check fails.
   - String concatenation and array operations on limited-size arrays (usually small amounts of requested classes and a few dozen/hundred workers).
   - **Conclusion:** CPU overhead is O(rejected_jobs * online_workers) but localized to exceptional paths. Acceptable overhead.

## Implementation Steps

### Task 1: Refactor worker fetching logic
- Modify `lib/OpenQA/Scheduler/Model/Jobs.pm`.
- Change `determine_free_workers` to a new method `determine_online_workers($shuffle)`. It should query the DB for all active workers without the `job_id => undef` constraint.
- Re-implement `determine_free_workers($shuffle)` to call `determine_online_workers($shuffle)` and filter the result in Perl (`grep { !$_->job_id } @$online_workers`).
- Note: This ensures backward compatibility for existing callers of `determine_free_workers` while minimizing DB hits.

### Task 2: Pass online workers to `_allocate_jobs`
- Modify `lib/OpenQA/Scheduler/Model/Jobs.pm` around `schedule()`.
- Store `my $online_workers = determine_online_workers($self->shuffle_workers);`.
- Compute `my $free_workers = [grep { !$_->job_id } @$online_workers];`.
- Change the signature of `_allocate_jobs($self, $free_workers, $online_workers)`. Provide a fallback `determine_online_workers` if `$online_workers` is missing, protecting existing tests that only pass `$free_workers`.

### Task 3: Refine scheduling reason logic
- In `_allocate_jobs` (around line 82 of `Jobs.pm`), where `$jobinfo->{current_reason}` is assigned:
  ```perl
  if (!@{$jobinfo->{matching_workers}}) {
      my @needed = sort @{$jobinfo->{worker_classes}};
      if (@needed) {
          # Only check against online workers if we already failed against free workers
          if (@{_matching_workers($jobinfo, $online_workers)}) {
              $jobinfo->{current_reason} = "no free workers for class @needed";
          } else {
              $jobinfo->{current_reason} = "no workers online for requested class @needed at all";
          }
      } else {
          $jobinfo->{current_reason} = 'no workers online';
      }
  }
  ```

### Task 4: Adapt unit and integration tests
- Modify `t/05-scheduler-mocked.t` to mock `determine_online_workers` identically to `determine_free_workers` to avoid unexpected DB queries.
- Modify `t/05-scheduler-full.t` to assert the new message `"no workers online for requested class foo at all"` instead of `"no free workers for class foo"` in the worker job allocation subtest, as the test doesn't spawn any workers with the `foo` class.
- Verify tests pass cleanly (`make test-unit-and-integration TESTS=t/05-scheduler-full.t t/05-scheduler-mocked.t t/04-scheduler.t`).
