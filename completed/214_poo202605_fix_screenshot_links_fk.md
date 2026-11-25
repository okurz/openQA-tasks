# Plan: Fix foreign key constraint error in screenshot_links table

## Motivation
When a worker attempts to update screenshots for a job that was recently deleted or canceled (meaning the `job_id` is no longer present in the `jobs` table), inserting into the `screenshot_links` table fails with a foreign key violation `screenshot_links_fk_job_id`. This causes an unexpected crash/error in logs which triggers monitoring alerts (logwarn).

## Design Choices
1. **Pre-check Job Existence**: Check if the job actually exists in the `Jobs` table first. If not, return early. This handles the vast majority of cases without invoking database errors or failed transactions.
2. **Race Condition Recovery (eval block)**: Wrap the DBIx::Class `populate` call in an `eval` block. If the job is deleted between the pre-check and the insert, catch the exception. If it is a `screenshot_links_fk_job_id` foreign key constraint error, gracefully log it at `info` level and skip. Otherwise, rethrow the error.
3. **Log Warn Prevention**: By catching and logging the issue as `info`, we avoid logwarn alerts.

## Implementation Steps
1. In `lib/OpenQA/Schema/ResultSet/Screenshots.pm`:
   - Import `log_info` from `OpenQA::Log` in addition to `log_trace` and `log_error`.
   - In `populate_images_to_job`, add a pre-check: `return unless $self->result_source->schema->resultset('Jobs')->find($job_id);`.
   - Wrap the `populate` block in `eval` and handle the foreign key exception gracefully.

## Verification
1. Add a test case in `t/42-screenshots.t` where `populate_images_to_job` is called with a non-existent job ID, verifying that:
   - It does not throw an exception.
   - It behaves gracefully.
2. Run `make tidy` and `make test-checkstyle`.
3. Run `COVERAGE=1 make test-unit-and-integration TESTS=t/42-screenshots.t` and inspect coverage.
