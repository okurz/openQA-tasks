# 142: Server-Side Based Pagination for Scheduled Jobs Table

## Context and Objective

On `/tests`, the `#scheduled` DataTables table loads its content via AJAX from `/tests/list_scheduled_ajax`.
Currently, the endpoint returns a capped array of jobs (up to `generic_default_limit` = 1000 rows, or `generic_max_limit` = 10000 via `limit` parameter).
While PR #8027 provides the server-computed `total_count` and `blocked_count` for the header and info callback, the table itself remains client-side (`serverSide: false`).
Because DataTables operates on the client side with only the capped subset in memory, the pagination controls cannot browse through jobs beyond the cap.

The objective of this task is to transition `#scheduled` to true DataTables server-side processing (`serverSide: true`), matching existing patterns like `admin_worker.js`, `audit_log.js`, and `admin_needle.js`.
This enables full, scalable pagination across tens of thousands of scheduled jobs while requesting only the visible page window (e.g. 10 to 100 rows per request), reducing backend serialization overhead and browser memory footprint.

---

## Technical Approach & Architecture

1. **Protocol Standard**: Follow DataTables Server-Side Processing protocol (DataTables v2):
   - Request parameters: `draw`, `start`, `length`, `order[i][column]`, `order[i][dir]`, `search[value]`.
   - Response parameters: `draw`, `recordsTotal`, `recordsFiltered`, `data`, alongside existing domain fields (`total_count`, `blocked_count`, `job_skipped_by_disk_limits`).
2. **Backward Compatibility**:
   - If `draw` parameter is absent (direct script / non-DataTables API call), preserve the existing array/object behavior with `limit` parameter.
   - When `draw` is present, respect `start` (as SQL `offset`) and `length` (as SQL `rows`), bounded by `generic_max_limit`.
3. **Database Efficiency**:
   - `Jobs` resultset already supports `offset` and `rows` via DBIx::Class.
   - Use index-backed queries (`idx_jobs_state`, `jobs_idx_blocked_by_id`).
   - Single-query aggregate for total and blocked counts using SQL `FILTER (WHERE ...)`.

---

## Task Breakdown

### Task 1: Backend Support for DataTables Pagination in `list_scheduled_ajax`
- **File**: `lib/OpenQA/WebAPI/Controller/Test.pm`, `t/ui/01-list.t`
- **Goal**: Accept DataTables request arguments (`draw`, `start`, `length`, `order`).
  - Extract and validate `draw` (integer), `start` (integer >= 0), `length` (integer >= 0).
  - Map column index in `order[0][column]` to sortable columns: `0 => me.id`, `1 => me.TEST`, `2 => me.priority`, `3 => me.t_created`.
  - Pass `offset => $start` and `rows => $length` to `$jobs_rs->search(...)`.
  - Format response JSON with `draw`, `recordsTotal => $total_count`, `recordsFiltered => $total_count` (or search-filtered count when text search is applied).
  - Keep `total_count` and `blocked_count` in response for UI heading updates.
- **Verification**: Unit and API tests verifying that calling with `draw=1&start=10&length=10` returns proper slice, headers, and pagination envelope.

### Task 2: Frontend Transition to `serverSide: true`
- **File**: `assets/javascripts/tests.js`
- **Goal**: Configure `#scheduled` DataTables instance for server-side processing:
  - Add `serverSide: true`, `processing: true`.
  - Remove custom `layout.bottomStart.info` callback override, letting DataTables handle standard `Showing X to Y of Z entries` natively across all pages.
  - Update `dataSrc` handler to read `total_count`, `blocked_count`, and warnings from the JSON response to update `#scheduled_jobs_heading` and disk space warnings without breaking pager state.
- **Verification**: Selenium UI tests verifying page navigation (clicking next page requests `start=...` from server and renders next batch).

### Task 3: Test Adaptations & Verification
- **File**: `t/ui/01-list.t`
- **Goal**:
  - Add test coverage for multi-page scheduled listings under Selenium.
  - Assert that pagination buttons allow browsing through records beyond the first page window.
  - Verify that sorting by column triggers appropriate server-side ordering.
- **Verification**: `COVERAGE=1 make test-unit-and-integration TESTS=t/ui/01-list.t` and `make check-line-coverage`.

---

## Approvals

| Decision | Approver | Date |
|---|---|---|
| Keep PR #8027 minimal (as squashed on current branch) | user (`okurz`) | 2026-10-29 |
| Create dedicated plan `tasks/142_server_side_scheduled_table.md` for full server-side pagination | user (`okurz`) | 2026-10-29 |

---

## Gates

| Commit | Verification Command |
|---|---|
| Commit 1 (Backend: server-side pagination support) | `make tidy && COVERAGE=1 make test-unit-and-integration TESTS=t/ui/01-list.t && make check-line-coverage && make test-gitlint` |
| Commit 2 (Frontend: enable `serverSide: true` on `#scheduled`) | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/ui/01-list.t && make test-gitlint` |

---

## Session starter

```markdown
Continue with task `tasks/142_server_side_scheduled_table.md` to switch `#scheduled` DataTables to `serverSide: true`.
Load skills: `perl-dev`, `git-workflow`, `testing`.
Branch: create feature branch `feature/142_server_side_scheduled_table` from `origin/master`.
Commit unit: Start with Task 1 (backend support for DataTables pagination in `list_scheduled_ajax`).
Confirm with user before any push or pull request creation.
```
