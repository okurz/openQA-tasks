# poo#167749 — Reserve complete worker hosts

Tickets:

- https://progress.opensuse.org/issues/167749 (this task)
- https://progress.opensuse.org/issues/167746 (epic)

Follow-up to `tasks/107_poo167749_reserve_worker.md`, implemented on branch
`feature/107_poo167749_reserve_worker_3_reserve_for_non_production_verification`
(PR https://github.com/os-autoinst/openQA/pull/7748). This plan covers the first
of the two additional ideas from the last ticket comment: _reserve complete
worker hosts_.

The second idea, keeping reserved workers usable for verification jobs, is
planned separately in `tasks/110_poo167749_reserve_worker_advanced.md`. The two
features are independent; either can ship first. See "Interaction with 110"
below.

## Problem

Worker instances are individual processes registering individually, so a
reservation covers one instance. Maintenance, however, happens per machine: a
host running 20 instances has to be drained as a unit. Doing that instance by
instance is 20 API calls, is not atomic, and silently misses instances that
register while the maintenance is in progress.

## State of the shipped implementation

The merged design deviates from plan 107 in one relevant point: the reservation
is **not** stored in new `workers` columns but in `worker_properties`
(`OpenQA::WorkerReservation::RESERVATION_PROPERTIES` = `RESERVED_BY_ID`,
`RESERVED_COMMENT`, `RESERVED_T_CREATED`, `RESERVED_T_EXPIRES`). No schema
version bump, no migration. Relevant entry points:

| Concern                   | Location                                                                                                                |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Constants, expiry         | `lib/OpenQA/WorkerReservation.pm` (`reservation_active`, `reservation_error`)                                           |
| Per-worker business rules | `Result::Workers::reserve`/`release`/`is_reserved`/`reservation`                                                        |
| Bulk lookup               | `ResultSet::Workers::reserved_worker_ids` (one query for all workers)                                                   |
| Registration              | `API::V1::Worker::_register` (find-or-create on `(host, instance)`)                                                     |
| API                       | `POST`/`DELETE /api/v1/workers/<id>/reservation` in `API::V1::Worker`                                                   |
| Audit                     | `lib/OpenQA/WebAPI/Plugin/AuditLog.pm` worker event list                                                                |
| CLI                       | `lib/OpenQA/CLI/reservation.pm`, `public/openqa-cli.yaml`                                                               |
| UI                        | `templates/webapi/admin/workers/{index,show,worker_status,reserve_modal}.html.ep`, `assets/javascripts/admin_worker.js` |
| Docs                      | `docs/UsersGuide.md` "Reserving workers" (`#reserving_workers`)                                                         |

This plan builds on that and must not reintroduce a migration.

## Design decisions

1. **Fan-out over instances, no host-level record.** Reserving a host writes the
   existing reservation properties to every worker row of that host inside one
   transaction, plus a new `RESERVED_SCOPE` property (`host` or `instance`).
   There is no separate host reservation entity.

   Rejected: a `worker_host_reservations` table. It needs a schema bump and a
   migration, introduces a second reservation store, and forces an "effective
   reservation" resolution into every read path (`is_reserved`, `info`, `stats`,
   scheduler, API filter) — exactly the complexity plan 107 avoided.

   Cost of the fan-out: writes scale with the instance count (tens, irrelevant)
   and the reservation only covers instances existing at reserve time. That gap
   is closed by decision 3.

2. **All-or-nothing acquisition.** A partially reserved host is worse than an
   unreserved one for maintenance. If any instance conflicts (already reserved by
   somebody else), nothing is written and the request fails with 409 naming the
   conflicting instances. Admins can override with `force`.

3. **Newly registering instances inherit an active host reservation.** In
   `_register`, a worker without its own reservation adopts an active
   `scope=host` reservation from a sibling instance of the same host. This covers
   the common case "reserve host, re-image it, instance count changes". Without
   it a fresh instance would silently accept production jobs on a host under
   maintenance.

4. **Release is symmetric but not all-or-nothing in the other direction.**
   Releasing a host releases every active reservation on that host regardless of
   scope, so an operator does not have to know how an instance got reserved; it
   fails with 403 without releasing anything if any of them is owned by somebody
   else and the caller is not an admin. Releasing a single instance of a
   host-scoped reservation is allowed and only affects that instance. Partial
   hand-back of a host is a valid workflow; partial acquisition is not.

5. **One audit event per host operation**, not one per instance:
   `openqa_worker_host_reserve` / `openqa_worker_host_release` with payload
   `{host, instances => [ids], comment, expires}`. Fanning out N per-instance
   events would drown the audit log for a 20-slot host. Both names must be added
   to the worker event list in `AuditLog.pm`, otherwise the events are dropped
   silently.

6. **No new UI buttons.** The existing reserve modal gains a scope selector
   ("This instance" / "All N instances on `<host>`"). One code path, no extra
   column, no multi-select machinery.

## Risks / things to verify during implementation

- Mojolicious placeholders: a worker host contains dots, so the route needs the
  relaxed form `<#host>`; the standard `<host>` placeholder stops at `.`.
- `openqa-cli` already owns a global `--host` option for the target web UI. The
  worker host option must be named differently (`--worker-host`) or users will
  silently target the wrong server.
- `t/fixtures/02-workers.pl` contains two workers on the same host with
  hard-coded counts asserted in `t/api/12-admin-workers.t` and
  `t/ui/15-admin-workers.t`. Create additional hosts and instances inside new
  subtests, do not touch fixtures.
- Reserving a host removes all its slots at once, which is the desired behaviour
  for `PARALLEL_ONE_HOST_ONLY` clusters but changes what
  `Scheduler::WorkerSlotPicker` sees; cover it with a test, since the picker
  degrades to "any host" in some paths.
- Host reservations are per web UI. A worker connected to several web UIs is only
  reserved on the one where the reservation was made. Document it, do not try to
  solve it.
- `_register` runs on every worker (re-)registration. The inheritance lookup must
  be a single query and must not run when the worker already holds a
  reservation.

## Tasks

Each task is independently committable and must leave the test suite green.
T1 blocks T2 and T3.

---

### T1 — Model: reserve and release a whole host

Commit type: `feat`

Changes:

- `OpenQA::WorkerReservation`: add `RESERVED_SCOPE` to `RESERVATION_PROPERTIES`
  and `SCOPE_HOST`/`SCOPE_INSTANCE` constants.
- `Result::Workers::reserve`: write `RESERVED_SCOPE`, defaulting to `instance`;
  `reservation` exposes `scope`.
- `ResultSet::Workers::reserve_host($host, $user, %args)` and
  `release_host($host, $user, %args)`: resolve all instances of the host, run the
  per-instance `reserve`/`release` inside one `txn_do`, collect conflicts and
  rethrow a single `reservation_error` (`conflict`/`forbidden`) naming the
  offending instances; return the affected worker ids.
- Both reuse `Result::Workers::reserve`/`release`; no second copy of the
  permission, duration and comment rules.

Tests:

- `t/38-workers-table.t`, parametrised subtest table: host with three instances
  reserved in one call; a conflict on one instance aborts all and leaves no
  partial state; admin `force` overrides; host release frees all instances
  including instance-scoped ones; release refused when one instance is owned by
  somebody else and nothing is released; releasing a single instance of a host
  reservation leaves the others reserved; unknown host raises the expected error;
  expiry is identical across all instances.

---

### T2 — Newly registering instances inherit a host reservation

Commit type: `feat`

Changes:

- `API::V1::Worker::_register`: after find-or-create, if the worker has no active
  reservation of its own, adopt an active `scope=host` reservation from the
  sibling instance of the same host with the newest `RESERVED_T_CREATED`. Copy
  owner, comment, `t_created` and `t_expires` verbatim so the whole host expires
  at the same moment.
- Log at info level when a reservation is inherited; otherwise this is a
  surprising state when debugging why a fresh worker takes no jobs.

Tests:

- `t/api/01-workers.t`: reserve a host, register a new instance on it, assert the
  new instance is reserved with identical owner and expiry; register an instance
  on an unreserved host and assert it is not reserved; re-register an instance
  holding its own instance-scoped reservation and assert the host reservation
  does not overwrite it; assert an expired host reservation is not inherited.

---

### T3 — API and audit events

Commit type: `feat`

Changes:

- `lib/OpenQA/WebAPI.pm`: `$api_ro->post('/worker_hosts/<#host>/reservation')` →
  `worker#reserve_host` and the matching `delete` → `worker#release_host`, plus
  `%api_description` entries.
- `API::V1::Worker`: `reserve_host`/`release_host` reusing `_apply_reservation`
  for error rendering; the response reports `host` and the affected `instances`.
  POD `=item` blocks for both — they feed the API help page.
- `AuditLog.pm`: register `worker_host_reserve worker_host_release`.
- `API::V1::Worker::delete`: refuse deleting an instance covered by an active
  host reservation, with the rule already used for instance reservations.

Tests:

- `t/api/01-workers.t`: happy path reserve/release by host; a host name with dots
  resolves through the route; non-operator 403; conflict 409 listing the
  conflicting instance; admin `force`; release by a foreign user 403 with nothing
  released; unknown host 404; exactly one audit row per operation with the
  expected payload; the `reserved` filter on `/workers` lists all instances.

---

### T4 — CLI support

Commit type: `feat`

Changes:

- `lib/OpenQA/CLI/reservation.pm`: `--worker-host HOST` selecting the host
  endpoint, mutually exclusive with the positional worker id (die with usage
  otherwise). Deliberately not `--host`, which is the global target-host option.
- `public/openqa-cli.yaml`: document the option in the `reservation` block.
- Regenerate shell completions if `tools/generate-cli-completions` output is
  checked in.

Tests:

- `t/43-cli-reservation.t`: usage error when both a worker id and
  `--worker-host` are given and when neither is; reserve and release a host
  against the embedded web UI; `--worker-host` combined with `--release`.

---

### T5 — Admin UI scope selector

Commit type: `feat`

Changes:

- `reserve_modal.html.ep`: radio group "This instance" / "All N instances on
  `<host>`", hidden for single-instance hosts. Host and instance count come from
  `data-` attributes on the triggering button.
- `admin_worker.js`: pick the endpoint from the selected scope; keep a single
  `fetchWithCSRF` call path for both.
- `worker_status.html.ep`: the reservation popover states the scope
  ("Reserved (whole host)").
- `Controller::Admin::Workers`: stash the instance count per host, computed once
  from the already loaded worker list, not with a query per row.

Tests:

- `t/ui/15-admin-workers.t`: reserve a whole host through the modal and assert
  every instance of that host shows as reserved; release; scope selector hidden
  for single-instance hosts; popover text.

---

### T6 — Documentation

Commit type: `docs`

Changes:

- `docs/UsersGuide.md`, "Reserving workers": new subsection _Reserving a whole
  host_ covering the maintenance rationale, all-or-nothing acquisition,
  inheritance by newly registering instances, the release semantics of decision
  4, and that reservations are per web UI. Example:

  ```
  openqa-cli reservation --worker-host worker35 --comment "firmware update" --duration 1d
  openqa-cli reservation --worker-host worker35 --release
  openqa-cli api -X POST worker_hosts/worker35/reservation comment="firmware update" duration=1d
  ```

- `docs/Installing.md` audit event list: add `worker_host_reserve
worker_host_release`.

---

## Verification (every task)

```
make tidy
make test-checkstyle
COVERAGE=1 make test-unit-and-integration TESTS=<the tests touched>
make check-line-coverage
make test-gitlint
```

Commit messages: conventional commits, 50/80 rule, body with Motivation, Design
Choices, Benefits, and a trailing
`Related issue: https://progress.opensuse.org/issues/167749`.

## Interaction with 110 (verification class)

Independent, but they touch the same lines in five files:
`OpenQA::WorkerReservation` (`RESERVATION_PROPERTIES`), the `reserve` signature,
the reserve API action, the CLI option list and the reserve modal. Whichever
lands second resolves trivial conflicts and additionally has to:

- pass `worker_class` through the host reservation path, so a whole host can be
  put into verification mode in one call;
- include `worker_class` in the `worker_host_reserve` audit payload.

If 111 lands second, add that as one extra `feat` commit here.

## Open questions

- Should a host reservation appear as a single aggregated row in the admin
  workers table instead of N identical badges? Deferred: it changes the table's
  data model, and the popover from T5 already makes the scope obvious.
- Should a host reservation also cover instances that are currently `dead` and
  may come back? With the fan-out they are covered, since the reservation is
  written to the existing rows regardless of liveness. Confirm that this is
  wanted rather than surprising during T1.

## Follow-ups (separate tickets under epic #167746)

- Reservation queue/waitlist per host.
- Power control / IPMI integration for hosts under maintenance.
- Audit event when a reservation expires.
