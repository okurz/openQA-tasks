# poo#167749 — Reserve complete worker hosts and host administration view

Tickets:

- https://progress.opensuse.org/issues/167749 (this task)
- https://progress.opensuse.org/issues/167746 (epic: Worker reservation/enable/disable)

Follow-up to `tasks/107_poo167749_reserve_worker.md` and `tasks/110_poo167749_reserve_worker_advanced.md`.
This execution plan covers extending `/admin/workers` to make host names clickable,
providing a dedicated host route showing joint configuration and past jobs across all worker
instances on a host, and making complete hosts reservable for maintenance.

## Problem

1. **Lack of host-level visibility**: Worker instances are registered and displayed individually
   (e.g., `worker35:1`, `worker35:2`) in the admin workers table (`/admin/workers`). While individual
   worker instances can be inspected at `/admin/workers/<id>`, host names in the table are plain text.
   There is no joint view showing aggregate host health, joint configuration (common settings vs.
   per-instance variations), or combined job history across all worker slots on that machine.
2. **Maintenance overhead and race conditions**: Maintenance (kernel updates, firmware flashing,
   reboots, hardware service) affects complete physical hosts. Reserving 20-30 individual slots
   manually requires dozens of API calls, lacks atomicity, and fails if instances restart or newly
   register during the maintenance window. A mechanism to reserve, inspect, and release complete hosts
   atomically is required.

## State of the Shipped Implementation

Worker reservations use existing `worker_properties`
(`OpenQA::WorkerReservation::RESERVATION_PROPERTIES`: `RESERVED_BY_ID`, `RESERVED_COMMENT`,
`RESERVED_T_CREATED`, `RESERVED_T_EXPIRES`, `RESERVED_WORKER_CLASS`), avoiding database schema
migrations.

| Concern                   | Location                                                                                                                |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Constants, validation     | `lib/OpenQA/WorkerReservation.pm` (`reservation_active`, `reservation_error`, `reservation_info`)                       |
| Per-worker business rules | `Result::Workers::reserve`/`release`/`is_reserved`/`reservation`/`accepts_classes`                                      |
| Bulk reservation lookup   | `ResultSet::Workers::active_reservations` (single query for all workers)                                                |
| Scheduler integration     | `Scheduler::Model::Jobs::determine_online_workers` and `_matching_workers`                                              |
| Registration              | `API::V1::Worker::_register` (find-or-create on `(host, instance)`)                                                     |
| REST API                  | `POST`/`DELETE /api/v1/workers/<id>/reservation` in `API::V1::Worker`                                                   |
| Audit logging             | `lib/OpenQA/WebAPI/Plugin/AuditLog.pm` (`@worker_events`)                                                               |
| CLI                       | `lib/OpenQA/CLI/reservation.pm`, `public/openqa-cli.yaml`                                                               |
| Admin UI                  | `templates/webapi/admin/workers/{index,show,worker_status,reserve_modal}.html.ep`, `assets/javascripts/admin_worker.js` |
| Documentation             | `docs/UsersGuide.md` (`#reserving_workers`), `docs/Installing.md`                                                       |

This plan builds on the above architecture without introducing schema version bumps or migrations.

## Design Decisions

1. **Fan-out over instances, no separate host entity.**
   Reserving a host writes reservation properties to every worker row of that host inside a single
   database transaction (`txn_do`), adding a `RESERVED_SCOPE` property (`host` or `instance`).
   - _Rationale_: Avoids adding a new table and migration. Read paths (`active_reservations`,
     `is_reserved`, scheduler matching) continue working seamlessly without any performance penalty.
2. **Dedicated host route with relaxed placeholder `<#worker_host>`.**
   Host names frequently contain dots (e.g. `worker35.qa.<internal>`). Mojolicious standard `<worker_host>`
   placeholder terminates at `.`. Using relaxed placeholder `<#worker_host>` ensures dotted host names
   route correctly to `/admin/worker_hosts/<#worker_host>` and `/admin/worker_hosts/<#worker_host>/ajax`.
3. **Clickable host names across admin UI.**
   In `/admin/workers` (`index.html.ep`), host names link to `/admin/worker_hosts/<#worker_host>`.
   In `/admin/workers/<id>` (`show.html.ep`), the host field also links to the host view.
4. **Joint configuration and aggregated job history.**
   The host view (`/admin/worker_hosts/<#worker_host>`) aggregates:
   - Worker instances summary (slot numbers, statuses, current jobs, last seen).
   - Joint configuration: identifies common properties shared across all instances (e.g., `CPU_ARCH`,
     `ISOTOVIDEO_INTERFACE_VERSION`) and highlights per-instance differences.
   - Combined worker classes badge list.
   - Joint previous jobs DataTable querying `assigned_worker_id => {-in => \@worker_ids}` via
     `/admin/worker_hosts/<#worker_host>/ajax`.
5. **All-or-nothing acquisition.**
   Reserving a host is atomic. If any worker instance on the host is already reserved by another user,
   the operation fails with 409 Conflict identifying the conflicting instances. Admins can override
   using `force=1`.
6. **Newly registering instances inherit active host reservations.**
   In `API::V1::Worker::_register`, when a worker registers without its own reservation, it inherits
   any active `scope=host` reservation from sibling instances on the same host. This prevents fresh or
   restarted instances from picking up production jobs during machine maintenance.
7. **Symmetric release semantics.**
   Releasing a host clears reservations across all instances on that host. If any instance is reserved
   by another user and the caller is not an admin, release fails with 403 Forbidden without modifying
   any instances. Releasing a single instance of a host-scoped reservation is permitted (partial
   hand-back).
8. **One audit event per host operation.**
   Emits `worker_host_reserve` and `worker_host_release` with payload
   `{host, instances => [ids], comment, expires, worker_class}`. Adding these to `@worker_events`
   in `AuditLog.pm` prevents silent dropping.
9. **Support for verification class (`worker_class`).**
   Inheriting from plan 110, reserving a complete host accepts an optional `worker_class` tag to place
   an entire machine into verification mode in one call.
10. **Unified reservation modal.**
    The reserve modal provides scope selection ("This instance" vs. "All N instances on `<host>`")
    when triggered from `/admin/workers`, and defaults to whole-host reservation when triggered from
    the host view.

## Risks & Mitigations

- **Dotted hostnames in routes**: Standard route placeholders stop at `.`.
  _Mitigation_: Use `<#worker_host>` in `lib/OpenQA/WebAPI.pm` for all host-related routes.
- **Fixture count assertions**: Fixtures (`t/fixtures/02-workers.pl`) contain two workers on `localhost`
  asserted by existing tests.
  _Mitigation_: Create separate hosts with multiple instances dynamically inside new test cases.
- **Large job history query**: Querying jobs across all instances on a 30-instance host could be slow.
  _Mitigation_: Reuse `OpenQA::WebAPI::ServerSideDataTable` with indexed `assigned_worker_id` condition
  and paginated limits.
- **Unknown/missing hosts**: Handling worker rows with `undef` or empty hostnames.
  _Mitigation_: Render 'unknown' text without link if host is absent; return 404 on host view for
  non-existent hosts.

---

## Tasks

### T1 — Model: Reserve/release complete host and registration inheritance

Commit type: `feat(workers): Support whole-host reservation and inheritance`

Motivation:
Provide atomic host-level reservation and release mechanisms in the schema layer, and ensure newly
registering instances inherit active host reservations during maintenance.

Design Choices:

- Add `RESERVED_SCOPE` property key to `OpenQA::WorkerReservation` with `SCOPE_HOST` and
  `SCOPE_INSTANCE` constants.
- Extend `Result::Workers::reserve` with optional `scope` parameter (default `instance`).
- Implement `ResultSet::Workers::reserve_host($host, $user, %args)` and
  `release_host($host, $user, %args)`:
  - Enforce all-or-nothing transactional execution (`txn_do`).
  - Detect conflicts across all instances on the host; raise 409 Conflict naming offenders.
  - Support admin `force` override and optional `worker_class`.
  - Validate permissions on release; raise 403 if foreign-owned instances exist without admin privileges.
- Extend `API::V1::Worker::_register`: if the worker has no active reservation, copy active `scope=host`
  reservation properties from any sibling instance on the same host.

Tests:

- `t/38-workers-table.t`:
  - Reserve multi-instance host atomically; assert all instances reserved with `scope=host`.
  - Conflict on one instance aborts entire reservation without partial state.
  - Admin `force` overrides conflicts.
  - Releasing a host clears all instances; non-admin release fails when instances are foreign-owned.
  - Releasing single instance of a host reservation leaves remaining instances intact.
  - Passing `worker_class` to `reserve_host` sets class across all instances.
- `t/api/01-workers.t`:
  - Register new worker on an active host-reserved machine; assert inherited reservation properties.
  - Ensure expired host reservation is not inherited.

Acceptance:
`COVERAGE=1 make test-unit-and-integration TESTS="t/38-workers-table.t t/api/01-workers.t"` passes
with clean line coverage.

---

### T2 — REST API: Worker host reservation endpoints and audit events

Commit type: `feat(api): Add worker host reservation endpoints and audit events`

Motivation:
Expose REST API endpoints to reserve and release complete worker hosts and record dedicated audit events.

Design Choices:

- In `lib/OpenQA/WebAPI.pm`:
  - `$api_ro->post('/worker_hosts/<#host>/reservation')->to('worker#reserve_host')`
  - `$api_ro->delete('/worker_hosts/<#host>/reservation')->to('worker#release_host')`
  - Add API route descriptions in `%api_description`.
- In `lib/OpenQA/WebAPI/Controller/API/V1/Worker.pm`:
  - `reserve_host`: validate parameters (`comment`, `duration`, `force`, `worker_class`), delegate to
    `reserve_host`, emit `openqa_worker_host_reserve` audit event, render JSON response.
  - `release_host`: delegate to `release_host`, emit `openqa_worker_host_release`, render JSON response.
  - Prevent deleting individual worker instances while covered by active host reservation unless `force=1`.
  - Document endpoints in POD (`=item`).
- In `lib/OpenQA/WebAPI/Plugin/AuditLog.pm`:
  - Register `worker_host_reserve` and `worker_host_release` in `@worker_events`.

Tests:

- `t/api/01-workers.t`:
  - Happy path `POST /api/v1/worker_hosts/<#host>/reservation` and `DELETE`.
  - Dotted hostname support (e.g. `worker01.infra.opensuse.org`).
  - Permission checks: operator required; foreign release requires admin.
  - Conflict response 409 listing conflicting instances; `force=1` override.
  - Verify audit rows emitted for `worker_host_reserve` and `worker_host_release`.
  - Unknown host returns 404.

Acceptance:
`COVERAGE=1 make test-unit-and-integration TESTS=t/api/01-workers.t` passes with clean line coverage.

---

### T3 — CLI: Worker host reservation in openqa-cli

Commit type: `feat(cli): Add worker-host option to reservation command`

Motivation:
Allow operators to reserve and release entire worker hosts directly via `openqa-cli`.

Design Choices:

- In `lib/OpenQA/CLI/reservation.pm`:
  - Add `--worker-host=s` option, mutually exclusive with positional `WORKER_ID`.
  - Route requests to `/api/v1/worker_hosts/<host>/reservation` when `--worker-host` is supplied.
  - Forward `--comment`, `--duration`, `--force`, `--class`, and `--release`.
- In `public/openqa-cli.yaml`:
  - Document `--worker-host` under `reservation` subcommand.
- Update auto-generated CLI completions if applicable.

Tests:

- `t/43-cli-reservation.t`:
  - Usage error when neither or both `WORKER_ID` and `--worker-host` are supplied.
  - Reserve complete host via `--worker-host <HOST> --comment ... --duration ...`.
  - Release host via `--worker-host <HOST> --release`.
  - Tag host with `--class` and verify API response.

Acceptance:
`COVERAGE=1 make test-unit-and-integration TESTS=t/43-cli-reservation.t` passes with clean line coverage.

---

### T4 — Admin UI: Host view route with joint configuration and past jobs

Commit type: `feat(ui): Add worker host view with joint configuration and jobs`

Motivation:
Provide a unified view for a worker host similar to `/admin/workers/<id>`, showing all instances,
joint configuration, overall reservation status, and aggregated job history across all instances.

Design Choices:

- In `lib/OpenQA/WebAPI.pm`:
  - `$pub_admin_r->get('/worker_hosts/<#worker_host>')->name('admin_worker_host_show')->to('workers#show_host')`
  - `$pub_admin_r->get('/worker_hosts/<#worker_host>/ajax')->name('admin_worker_host_previous_jobs_ajax')->to('workers#host_previous_jobs_ajax')`
- In `lib/OpenQA/WebAPI/Controller/Admin/Workers.pm`:
  - `show_host`: query all workers matching `host => $worker_host`. Return 404 if none found.
  - Compute instance statistics (online, busy, idle, reserved, dead).
  - Aggregate configuration: extract common properties shared by all instances, per-instance differences,
    and distinct worker classes.
  - Compute overall host reservation status (unreserved, fully reserved, partially reserved).
  - `host_previous_jobs_ajax`: ServerSideDataTable response for `Jobs` matching
    `assigned_worker_id => {-in => \@worker_ids}`.
- New template `templates/webapi/admin/workers/show_host.html.ep`:
  - Host summary card and reservation status card (with Reserve/Release host buttons).
  - Worker instances table with status badges and links to individual worker pages.
  - Joint configuration panel displaying shared properties and instance-specific differences.
  - Previous jobs DataTable (displaying test name, worker instance slot, result, and finished timestamp).
- In `assets/javascripts/admin_worker.js`:
  - Initialize `#previous_jobs` table for host view using `data-ajax-url`.

Tests:

- `t/api/12-admin-workers.t`:
  - Request `/admin/worker_hosts/<host>` returns 200 with instance and property data.
  - Request with unknown host returns 404.
  - Request `/admin/worker_hosts/<host>/ajax` returns ServerSideDataTable JSON with jobs from all instances.
- `t/ui/15-admin-workers.t`:
  - Navigate to `/admin/worker_hosts/<host>`; verify instances table, joint properties, and job list.

Acceptance:
`COVERAGE=1 make test-unit-and-integration TESTS="t/api/12-admin-workers.t t/ui/15-admin-workers.t"` passes.

---

### T5 — Admin UI: Clickable host names and reserve modal scope selection

Commit type: `feat(ui): Make host names clickable and add scope selection to reserve modal`

Motivation:
Allow operators to navigate seamlessly from the workers table to the host view and choose between
instance and host reservations in the modal.

Design Choices:

- In `templates/webapi/admin/workers/index.html.ep`:
  - In `<td class="host">`, link host names to `url_for('admin_worker_host_show', worker_host => $worker->{host})`.
  - Handle missing or 'unknown' host gracefully without link.
- In `templates/webapi/admin/workers/show.html.ep`:
  - Make host field clickable, linking to `admin_worker_host_show`.
- In `templates/webapi/admin/workers/reserve_modal.html.ep`:
  - Add scope radio buttons: "This instance (<name>)" vs. "All <N> instances on <host>".
  - Preselect host scope when invoked from `show_host.html.ep`.
- In `assets/javascripts/admin_worker.js`:
  - Direct request to `/api/v1/worker_hosts/<host>/reservation` when host scope is selected.
  - Support releasing complete host directly via `releaseHost(host)`.
- In `templates/webapi/admin/workers/worker_status.html.ep`:
  - Popover indicates `(whole host)` when reservation carries `scope=host`.

Tests:

- `t/ui/15-admin-workers.t`:
  - Verify host links in `/admin/workers` and `/admin/workers/<id>`.
  - Reserve whole host via modal on `/admin/workers` and assert all instances updated to reserved.
  - Reserve whole host from `/admin/worker_hosts/<host>` and release whole host.
  - Popover displays whole-host scope indicator.

Acceptance:
`COVERAGE=1 make test-unit-and-integration TESTS=t/ui/15-admin-workers.t` passes; `make test-checkstyle` clean.

---

### T6 — Documentation: User guide and audit log updates

Commit type: `docs: Document worker host administration view and reservations`

Motivation:
Document host administration view, clickable host navigation, and whole-host reservation workflows.

Design Choices:

- In `docs/UsersGuide.md`:
  - Add section _Worker Host Administration_ describing `/admin/worker_hosts/<host>`, joint configuration,
    and aggregate job history.
  - Update _Reserving workers_ (`#reserving_workers`) with _Reserving complete worker hosts_, covering:
    - Rationale for maintenance drainage.
    - All-or-nothing reservation semantics and conflict handling.
    - Automatic inheritance on worker registration.
    - Optional verification worker class for complete hosts.
    - `openqa-cli reservation --worker-host` examples.
- In `docs/Installing.md`:
  - Add `worker_host_reserve` and `worker_host_release` to the audit log events table.

Acceptance:
`make test-checkstyle` and doc link checks pass.

---

## Verification (Every Task)

Execute the following verification loop before committing any task:

```bash
make tidy
make test-checkstyle
COVERAGE=1 make test-unit-and-integration TESTS="<tests touched by task>"
make check-line-coverage
make test-gitlint
```

Commit message requirements:

- Conventional Commits format (`feat`, `fix`, `docs`, `refactor`).
- 50/80 physical hard-wrapping.
- Body sections: Motivation, Design Choices, Benefits (1-2 concise sentences each).
- Trailing ticket reference: `Related issue: https://progress.opensuse.org/issues/167749`.

## Open Questions & Future Extensions

- **Auto-grouping hosts in workers overview**: Should `/admin/workers` support a grouped accordion view
  collapsing instances by host? Deferred to keep table performance simple; clickable host links provide
  immediate access.
- **Power control / IPMI integration**: Future enhancement to trigger IPMI chassis power cycles directly
  from the host view when a host is reserved for maintenance.
