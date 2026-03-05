# Plan: Address security and resource concerns for "Download All" ZIP feature

## Motivation

PR #7015 introduces a server-side ZIP archival feature. Reviewers identified concerns regarding unauthenticated access to resource-intensive operations, which could lead to DoS (Denial of Service) by crawlers or malicious actors.

## Proposed Improvements

### 1. Authentication

Currently, the `/tests/:testid/archive` route is public. It should be moved under a route that requires at least a logged-in user. This prevents crawlers and non-authenticated users from triggering server-side compression.

### 2. Concurrency and Queue Management

Server-side compression is CPU and I/O intensive.

- **Queue**: Use a separate Minion queue (e.g., `background`) for `create_zip_archive` tasks.
- **Concurrency**: Limit the number of concurrent archival tasks to avoid saturating the server.

### 3. Crawler Protection

- Add `rel="nofollow"` to the "Download All" button in the UI.
- Add `/tests/*/archive` to `robots.txt` to explicitly discourage crawlers.

### 4. Error Handling and Responsiveness

Ensure that if Minion is not available, the system handles it gracefully without hanging the WebUI worker (e.g., by checking Minion availability first and failing fast or providing a clear error).

## Execution Steps

1.  **Restrict Access (Authentication)**:
    - Update `lib/OpenQA/WebAPI.pm` to move the `test_archive` route under the `$logged_in` or `$auth` bridge.
2.  **Optimize Task Execution**:
    - Update `lib/OpenQA/WebAPI/Controller/File.pm` to specify a lower-priority queue and concurrency limits when enqueuing the task.
3.  **UI Adjustments**:
    - Update `templates/webapi/test/downloads.html.ep` to add `rel="nofollow"`.
4.  **Robots.txt**:
    - Add a Disallow rule for archive paths.
5.  **Verification**:
    - Update existing tests (`t/60-archive-download.t`) to verify that unauthenticated requests are rejected.
    - Manually verify that the download still works for logged-in users.
