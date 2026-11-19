# Plan: poo#205737 — Use openQA reservation for manual testing hardware assets

**Ticket:** https://progress.opensuse.org/issues/205737  
**Related Tickets:** https://progress.opensuse.org/issues/167749, https://progress.opensuse.org/issues/167746

---

## Motivation

Many dedicated hardware assets in Quality Engineering (QE) are allocated for manual testing and remain idle between manual testing sessions, leading to under-utilization compared to openQA automated testing. Historical reservation methods (such as wiki pages, chat messages, or spreadsheets) are unstructured, lack automated expiration, provide poor visibility, and prevent automated test workloads from utilizing idle capacity.

With the base worker reservation system in openQA (#167749), openQA can manage hardware reservations natively. This plan focuses on addressing tester experience, operational friction, safeguards against abrupt expiration or state pollution, and advanced reservation capabilities.

---

## Scope & Objectives

### In Scope

1. **User Experience & Social Friction Mitigations**:
   - **Job Drain Visibility:** Expose active job details, runtime, and allow quick cancellation if immediate access is required.
   - **Expiration Safeguards:** Provide seamless in-place extension of active reservations to prevent abrupt auto-expiration mid-test.
   - **State Isolation:** Prevent leftover manual test state from failing subsequent automated runs via post-reservation sanity/reset hooks.
   - **Low-Friction UI/CLI:** Fast CLI commands and intuitive WebUI interactions with ticket linking.
2. **Feature Extensions**:
   - **In-place Reservation Extension:** API, CLI (`openqa-cli reservation extend <id> --by=2h`), and WebUI support.
   - **Upcoming Expiration Notifications:** Proactive warnings (via Minion / webhooks / audit log) before reservations expire.
   - **Post-Reservation Reset Hook:** Automatic worker sanity / reset trigger upon reservation release.
   - **Advance / Scheduled Reservations:** Support booking future reservation windows (`from=... to=...`) with scheduler lookahead.
3. **Documentation**:
   - Best practices and workflow guides for manual testers in `docs/UsersGuide.md`.

### Out of Scope

- Initial worker host provisioning and basic worker configuration (already covered by existing openQA infrastructure).
- External IPMI/power-switch automation outside existing backend hooks.

---

## Operational Architecture & Workflow

```
+--------------------------------------------------------------------+
|                           Worker Idle                              |
|          (openQA schedules automated test jobs normally)           |
+---------------------------------+----------------------------------+
                                  |
                                  | 1. Tester reserves worker
                                  |    (WebUI or `openqa-cli reservation`)
                                  v
+--------------------------------------------------------------------+
|                     Reserved: Finishing Job                        |
|   - Displays running job info & ETA                                |
|   - Allows emergency job abort if urgent                           |
+---------------------------------+----------------------------------+
                                  |
                                  | 2. Job completes / aborted
                                  v
+--------------------------------------------------------------------+
|                         Reserved: Active                           |
|   - Tester performs manual testing; worker bypassed                |
|   - Reservation survives reboots & re-imaging                      |
|   - In-place duration extension available                          |
|   - Proactive expiration notifications sent prior to expiry        |
+---------------------------------+----------------------------------+
                                  |
                  +---------------+---------------+
                  |                               |
  3a. Tester explicitly releases   3b. Reservation duration expires
      (`openqa-cli reservation -d`)     (Automatic fail-open release)
                  |                               |
                  +---------------+---------------+
                                  v
+--------------------------------------------------------------------+
|                    Post-Reservation Reset Hook                     |
|          (Optional cleanup / sanity script executed)               |
+---------------------------------+----------------------------------+
                                  |
                                  v
+--------------------------------------------------------------------+
|                           Worker Active                            |
|             (Returned to automated scheduling rotation)            |
+--------------------------------------------------------------------+
```

---

## Detailed Implementation Tasks

### Task 1: In-Place Reservation Extension (API, CLI, WebUI)

- **API (`Worker.pm`):** Add endpoint / parameter to extend `t_reservation_expires` without dropping or re-creating the reservation.
- **CLI (`lib/OpenQA/CLI/reservation.pm`):** Add `extend` subcommand:
  ```bash
  openqa-cli reservation extend <worker_id> --by=2h
  ```
- **WebUI (`admin_worker.js`, `reserve_modal.html.ep`):** Add "Extend" button and preset duration dropdown in the active reservation modal.

### Task 2: Expiration Warning Notifications

- **Minion Background Task:** Periodic check for reservations expiring within a configurable threshold (e.g., 15–30 minutes).
- **Notification Dispatch:** Emit audit events and trigger notification hooks (Matrix/Slack webhook, email) with direct one-click extension links and CLI commands.

### Task 3: Post-Reservation Reset / Sanity Check Hook

- **Worker Transition Hook:** When a worker leaves the `reserved` state, trigger an optional configured script (e.g., `/usr/lib/openqa/script/worker-reset-hook`) or mark the worker for a health check before accepting new scheduler jobs.
- **Fail-Safe Mode:** If the reset script fails, mark the worker as `broken` to prevent automated tests from running on polluted state.

### Task 4: Advance & Scheduled Reservations

- **Schema & Model:** Add support for `t_reservation_starts` in addition to `t_reservation_expires` or a queue of upcoming reservation windows.
- **Scheduler Integration:** Scheduler checks upcoming reservations and avoids assigning long-running jobs that would exceed the scheduled start window.
- **UI / CLI:** Display upcoming reservations in `/admin/workers` and allow advance booking via CLI/WebUI.

### Task 5: Job Drain Usability & Emergency Abort

- **Admin UI / CLI:** Clearly display current job ID, test name, and running duration when a worker is in `Reserved (finishing job N)`.
- **Emergency Abort:** Provide an authorized direct shortcut to abort the running job and immediately claim the worker.

### Task 6: Documentation & User Guide

- Update `docs/UsersGuide.md` with:
  - Step-by-step reservation and extension workflows.
  - Advance booking and notification setup.
  - Guidelines on resetting machines after manual testing.

---

## Verification & Testing Plan

1. **Unit & Integration Tests**:
   - `t/38-workers-table.t`: Test reservation extension, expiration calculation, and scheduled reservations.
   - `t/api/01-workers.t`: Test extension endpoint, validation, permission checks, and conflict handling.
   - `t/ui/15-admin-workers.t`: Test UI modal for extending reservations and displaying job drain status.
   - `t/04-scheduler.t`: Verify scheduler respects advance reservations and post-reservation reset states.
2. **Coverage Verification**:
   - `COVERAGE=1 make test-unit-and-integration TESTS=t/api/01-workers.t`
   - `make check-line-coverage`
3. **Linting & Code Quality**:
   - `make tidy`
   - `make test-checkstyle`
   - `make test-gitlint`

---

## Acceptance Criteria

- **AC1:** Testers can extend active reservations in-place via CLI (`openqa-cli reservation extend`) and WebUI.
- **AC2:** Proactive notifications warn testers before reservations expire with direct extension options.
- **AC3:** Post-reservation reset hook prevents hardware state pollution from impacting automated test suites.
- **AC4:** Advance/future reservation windows can be scheduled and are respected by the openQA scheduler.
- **AC5:** Full test coverage, clean test runs, and complete documentation in `docs/UsersGuide.md`.
