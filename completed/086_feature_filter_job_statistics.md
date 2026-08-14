# Plan for filtering job statistics by group globs

## Objective
Allow similar filtering for `/api/v1/isos/job_stats` as on `/tests` and `/tests/overview` by supporting the `group_glob` and `not_group_glob` parameters. This allows filtering out jobs from specific groups (e.g. "Development" groups).

## Implementation Steps

1. **Update `lib/OpenQA/WebAPI/Controller/API/V1/Iso.pm`**
   - Modify the `job_statistics` method.
   - Extract groups using `$self->groups_for_globs` which already parses `group_glob` and `not_group_glob`.
   - If globs are provided but match no groups, early return an empty JSON object `{}`.
   - Otherwise, extract the matched group IDs (if any) into an array reference.
   - Pass this array reference as an additional parameter to `$scheduled_products->job_statistics(...)`.

2. **Update `lib/OpenQA/Schema/ResultSet/ScheduledProducts.pm`**
   - Modify the `job_statistics` method signature to accept an optional `$group_ids` parameter.
   - In the recursive query (`WITH RECURSIVE ...`), inject a conditional `AND mrj.group_id IN (?, ?, ...)` clause in the `most_recent_jobs` select block if `$group_ids` is provided and non-empty.
   - Append the `$group_ids` elements to the list of bind parameters for the executed query.

3. **Add Tests in `t/api/02-iso.t`**
   - Mock a scenario with jobs belonging to different group IDs (including a mock "development" group).
   - Test `/api/v1/isos/job_stats` with `group_glob` and `not_group_glob` parameters.
   - Ensure the JSON response accurately filters out the unwanted jobs and includes only the expected ones based on the globs.

## Verification
- Ensure `make tidy` passes.
- Ensure `make test-checkstyle` passes.
- Ensure `make test-unit-and-integration TESTS=t/api/02-iso.t` passes.
