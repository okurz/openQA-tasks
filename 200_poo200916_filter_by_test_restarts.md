# Plan: Feature: option to filter based on number of restarts of a test

## Objective

Implement an option to filter jobs based on their minimum number of restarts (ticket #200916). The overview page already shows the number of restarts. We will add a `min_restarts` numeric filter.

## Architecture & Design

1.  **Search Criteria Definition (`lib/OpenQA/Constants.pm`)**:
    Add `min_restarts` to the `JOBS_OVERVIEW_SEARCH_CRITERIA` array. This makes it part of the known optional parameters for the jobs overview and ensures it passes validation automatically without breaking existing schemas.

2.  **Filter SQL Generation (`lib/OpenQA/WebAPI/Plugin/Helpers.pm`)**:
    In the `_compute_overview_filtering_params` method, retrieve the `min_restarts` parameter. If present and greater than 0, construct a SQL `IN` condition that joins `clone_id`s backward exactly `min_restarts` times. This elegantly matches jobs with at least that many ancestors. We cap the maximum nested JOINs (e.g. at 10) to prevent abuse from users supplying an unnecessarily large filter limit.

3.  **UI Updates (`templates/webapi/test/overview.html.ep`)**:
    Add a numeric input field `min_restarts` adjacent to the "Comment text" or "Misc" section on the overview filter form, following the UI style of other filter inputs with a helpful popover.

4.  **Testing (`t/10-tests_overview.t`)**:
    Add a new subtest `filter by min_restarts` immediately after the existing `restart counter` subtest. We will submit queries to `/tests/overview` with `min_restarts => 1`, `min_restarts => 2`, and `min_restarts => 3` against the jobs dynamically created in the preceding test, verifying that only jobs with the correctly evaluated number of restarts are returned.

## Execution Steps

1. Edit `lib/OpenQA/Constants.pm` to add `min_restarts` to `JOBS_OVERVIEW_SEARCH_CRITERIA`.
2. Edit `lib/OpenQA/WebAPI/Plugin/Helpers.pm` to retrieve `min_restarts` and append the dynamically generated nested `JOIN` SQL onto the returned `@conds` array in `_compute_overview_filtering_params`.
3. Edit `templates/webapi/test/overview.html.ep` to insert the numeric input `min_restarts` into the view form.
4. Edit `t/10-tests_overview.t` to add `filter by min_restarts` assertions testing limits 1, 2, and 3.
5. Verify changes with `make test-checkstyle`, `make tidy`, and `make test-unit-and-integration TESTS=t/10-tests_overview.t`.
6. Commit changes following conventions (`feat: allow filtering based on number of restarts`).

## Implementation Phase Progress (Completed)

Implemented the feature cleanly using the `flash-builder` sub-agent:

- Updated `lib/OpenQA/Constants.pm` to include `min_restarts` in the search criteria parameters.
- Built dynamic SQL in `lib/OpenQA/WebAPI/Plugin/Helpers.pm` mapping nested joins on `clone_id` to retrieve jobs with a minimum restart threshold, capped at 10.
- Added input field `min_restarts` inside `templates/webapi/test/overview.html.ep` matching design patterns and CSS guidelines.
- Created unit tests in `t/10-tests_overview.t` validating filtering capabilities for 1, 2, and 3 restarts.

## Review & Fix-up Phase Progress (Completed)

Hardened and verified by `precision-fixer` sub-agent:

- Added validation logic in `_compose_job_overview_search_args` via `$v->optional('min_restarts')->num(1, undef)` to avoid warnings and gracefully ignore invalid inputs (like non-numeric values).
- Identified and closed a test coverage gap on the join-capping branch (testing inputs like `min_restarts => 11`).
- Confirmed 100% statement and branch coverage on modified sections.
- Verified and passed all project checks: `make tidy`, `make test-checkstyle`, and integration tests in `t/10-tests_overview.t`.
