# Plan: Address Test Review Comments for "Result" Query Parameter

## Motivation
A code reviewer pointed out a flaw in the testing approach for the latest job query feature. Currently, the tests verify that a `result=passed` query parameter works by updating the *latest* job to `PASSED` and then querying for it. This approach is incomplete because querying without the `result=passed` parameter would return the exact same job (since it's the latest). We need to prove that the parameter actually acts as a filter by skipping newer jobs that don't match the requested result status.

## Design Choices
To correctly test this behavior, we need to guarantee that the *latest* job does not match the requested status, but an *older* job does. 
1. We will update the newest job to `FAILED` and an older job to `PASSED`.
2. A generic query for the latest job should return the newest `FAILED` job.
3. A query specifically requesting `result=passed` should successfully skip the newest job and return the older `PASSED` job.

## Implementation Steps

### 1. Update `t/10-overview_badge.t`
Modify the test scenario to use `test=kde&machine=64bit` (latest job 99963, older job 99962) to explicitly split the statuses of the two jobs.
- Update job `99963` (the latest job) to have `{result => FAILED, state => DONE}`.
- Update job `99962` (an older job) to have `{result => PASSED}`.
- Add an assertion for `/tests/latest/badge?test=kde&machine=64bit` checking that it returns a badge containing `failed` (proving it finds the latest job 99963).
- Add an assertion for `/tests/latest/badge?test=kde&machine=64bit&result=passed` checking that it returns a badge containing `passed` (proving it successfully bypasses the newest failed job to find the older passed one 99962).

### 2. Update `t/ui/18-tests-details.t`
Modify the test scenario for `test=kde&machine=64bit` (latest job 99963, older job 99962) to explicitly split the statuses of the two jobs.
- Update job `99963` (the latest job) to have `{result => FAILED, state => DONE}`.
- Update job `99962` (an older job) to have `{result => PASSED}`.
- Assert that fetching `/tests/latest?test=kde&machine=64bit` without the `result` parameter routes to the latest job, `99963`.
- Assert that fetching `/tests/latest?test=kde&machine=64bit&result=failed` routes to the newest job, `99963`.
- Assert that fetching `/tests/latest?test=kde&machine=64bit&result=passed` routes to the older passed job, `99962`.

## User Benefits
These test adaptations verify the API's filtering capability correctly and cleanly address the reviewer's concern by proving the `result` query parameter successfully traverses historical jobs to find a match.
