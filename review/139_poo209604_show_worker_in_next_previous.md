# Plan: Show "worker instances" in "next & previous table"

## Overview & ACs

**Motivation:**
The "next & previous" job results starting from job details pages help to find out various sources of problems. To distinguish problems on specific worker instances or worker hosts it would help to optionally show the used worker instances in "next & previous table".

**Acceptance criteria:**

- AC1: "Next & previous" job results shows used worker instances
- AC2: The table is still reasonably wide with no horizontal scrollbar by default

## Architecture & Design decisions

- **Backend:** `lib/OpenQA/WebAPI/Controller/Test.pm::job_next_previous_ajax` fetches `JobNextPrevious` rows. To avoid N+1 queries, we gather all `assigned_worker_id`s from the results and fetch the associated `Workers` objects in one go. We inject a `worker => { id => ..., host => ..., name => ... }` sub-object into each returned data row.
- **Frontend Template:** Add an explicit `<th>Worker</th>` column right after `Finished` in `templates/webapi/test/job_next_previous.html.ep`.
- **Frontend JavaScript:** In `assets/javascripts/job_next_previous.js`, add `{data: 'worker', defaultContent: ''}` to `columns`, and a `renderWorker` method that links to `/admin/workers/:id` using `row.worker.name` (`host:instance_id`). Additionally, adjust the `colSpan` logic when a limiting `note` is present so it spans the newly added column properly (`cells[1].colSpan = 4`).
- **UI Test:** Mock an `assigned_worker_id` on test job `99946`/`99947` in `t/ui/16-tests_job_next_previous.t` and verify that the HTML output displays `myworker:1` successfully.

## Approvals

Decision: Approve adding an explicit Worker column
Approver: User (poo#209604)
Date: 2026-10-30

## Gates

Verification commands per commit:

```bash
make tidy
make test-checkstyle
COVERAGE=1 make test-unit-and-integration TESTS="t/ui/16-tests_job_next_previous.t t/10-jobs.t"
make check-line-coverage
```

## Session starter

```bash
git checkout feature/139_poo209604_show_worker_in_next_previous
```

### Tasks

1. **feat(webui): Add worker instance to next & previous results**
   - [x] Modify `lib/OpenQA/WebAPI/Controller/Test.pm` to fetch worker data via `assigned_worker_id` efficiently and attach it to API payload.
   - [x] Update `templates/webapi/test/job_next_previous.html.ep` to include the `<th>Worker</th>` header.
   - [x] Update `assets/javascripts/job_next_previous.js` to render the column, link it to `/admin/workers/:id`, and adjust the note row colspan.
   - [x] Add mocked workers to `t/ui/16-tests_job_next_previous.t` to ensure the column renders correctly and doesn't break limits.

### Status

- Builder phase completed: code and tests implemented.
- Fixer phase completed: review, edge-case testing, in-file test comments removal, 100% statement coverage, tidy & checkstyle clean.
- Pre-push review completed: reviewed by strata-builder, all findings and nits addressed, verdict ready.
