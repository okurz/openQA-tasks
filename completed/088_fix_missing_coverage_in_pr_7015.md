# Plan: Fix missing coverage in PR 7015

## Objective
The code added in PR #7015 for archive downloads lacks statement coverage for the failure path when creating the ZIP archive. Specifically, the `catch ($e)` block in `lib/OpenQA/WebAPI/Controller/File.pm` around line 181-182 is never triggered by tests. We need to add a test case to cover this error handling path.

## Implementation Details

1. **File to modify:** `t/60-archive-download.t`
2. **Changes:**
   - Locate the `subtest 'Controller extra tests'` block.
   - Add a test step that mocks the minion `enqueue` method to throw an exception (e.g., `die 'Enqueue failed'`).
   - Issue a GET request to `/tests/$job_id/archive`.
   - Verify that the response status is `500` (Internal Server Error) and the content is or contains `'Internal Server Error'`.

By doing this, the exception will be caught by the `catch ($e)` block in `lib/OpenQA/WebAPI/Controller/File.pm` covering the previously missing lines and thus completing the coverage requirements for PR #7015.
