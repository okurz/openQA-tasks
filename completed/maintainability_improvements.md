# Maintainability Improvements for Job Group Aggregation

## Plan

1.  **Introduce Typed Exception**: Create `OpenQA::Error::LimitExceeded` and use it in `OpenQA::BuildResults` to avoid fragile string-based regex matching in controllers.
2.  **Refactor `compute_build_results`**: Decompose the large function into smaller, private helpers for fetching IDs, aggregating stats, and processing build metadata.
3.  **Optimize Query Logic**: Consolidate the multiple queries per build into a more efficient set of queries using subqueries or JOINs.
4.  **Centralize Configuration**: Ensure `job_group_overview_max_jobs` is sourced consistently from the application configuration.
5.  **Graceful Degradation**: Instead of a hard `die` that breaks the entire page, mark oversized builds and handle this in the UI.

## Verification

- `make test-unit-and-integration TESTS=t/61-job_group_aggregation.t`
- `make tidy`
- `make test-checkstyle-standalone`
