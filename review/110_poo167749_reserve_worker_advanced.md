# poo#167749 — Keep reserved workers usable for verification jobs

Tickets:

- https://progress.opensuse.org/issues/167749 (this task)
- https://progress.opensuse.org/issues/167746 (epic)

Follow-up to `tasks/107_poo167749_reserve_worker.md`, implemented on branch
`feature/107_poo167749_reserve_worker_3_reserve_for_non_production_verification`
(PR https://github.com/os-autoinst/openQA/pull/7748). This plan covers the
second of the two additional ideas from the last ticket comment: _still allow
scheduling non-production, verification openQA jobs on reserved instances_.

The first idea, reserving complete worker hosts, is planned separately in
`tasks/111_poo167749_reserve_worker_host.md`. The two features are independent;
either can ship first. See "Interaction with 111" below.

## Problem

Today a reservation removes a worker from scheduling entirely. The workflow it
is meant to replace does something more useful: an operator edits
`WORKER_CLASS` in `workers.ini`, e.g. `qemu_x86_64` → `qemu_x86_64_poo42`, and
restarts the worker. Production jobs asking for `qemu_x86_64` are no longer
picked up, but verification jobs can still be scheduled explicitly onto the
machine by requesting `qemu_x86_64_poo42`.

That workflow has three real costs: it needs a worker restart, it is silently
reverted by configuration management, and it is invisible in the web UI. The
reservation mechanism can provide the same capability without any of them.

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
| Scheduler exclusion       | `Scheduler::Model::Jobs::determine_online_workers`                                                                      |
| Class matching            | `Scheduler::Model::Jobs::_matching_workers` → `Result::Workers::check_class`                                            |
| API                       | `POST`/`DELETE /api/v1/workers/<id>/reservation` in `API::V1::Worker`                                                   |
| CLI                       | `lib/OpenQA/CLI/reservation.pm`, `public/openqa-cli.yaml`                                                               |
| UI                        | `templates/webapi/admin/workers/{index,show,worker_status,reserve_modal}.html.ep`, `assets/javascripts/admin_worker.js` |
| Docs                      | `docs/UsersGuide.md` "Reserving workers" (`#reserving_workers`)                                                         |

This plan builds on that and must not reintroduce a migration.

## Design decisions

1. **Reservation-scoped class tag; `WORKER_CLASS` is never written.** The
   reservation gains an optional `worker_class`, stored as
   `RESERVED_WORKER_CLASS`. The `WORKER_CLASS` property belongs to the worker
   and is overwritten by `update_caps` on every re-registration, so a value
   written from the web UI would be lost on the next worker restart. The tag
   lives in the reservation and is applied at matching time instead.

2. **Semantics: additive tag plus exclusivity.** While a worker holds a
   reservation with tag `T`:
   - its effective class set is `WORKER_CLASS ∪ {T}`;
   - it only matches jobs whose requested classes **contain** `T`.

   A job asking for `qemu_x86_64` is not matched; a job asking for
   `qemu_x86_64,poo167749` or just `poo167749` is. This reproduces the manual
   workflow without losing the capability classes, so verification jobs can
   still constrain on arch, `tap` and similar.

   Rejected: rewriting the classes with a suffix (`qemu_x86_64` →
   `qemu_x86_64_poo42`). It destroys multi-class matching and forces users to
   reconstruct every derived class name.

3. **Reserved without a tag keeps blocking completely.** The tag is opt-in; the
   default behaviour from plan 107 is unchanged.

4. **One predicate for class matching.**
   `Result::Workers::accepts_classes($needed, $reservation_class)` holds both
   rules and is called from `_matching_workers` instead of the inline
   `all { $worker->check_class($_) }`. The tag is passed in from the bulk lookup
   so the scheduler hot loop does not query properties per worker.

5. **A tagged worker is not "free".** `stats` keeps counting it under
   `reserved_workers` and out of `free_active_workers`: it is unavailable for
   production, which is what that number is read for. Documented explicitly.

6. **Tag validation** `qr/^[\w.:-]+$/`, rejected with 400 otherwise. A tag with a
   comma or whitespace would silently never match anything, since `WORKER_CLASS`
   is comma-separated.

## Risks / things to verify during implementation

- `ResultSet::Workers::reserved_worker_ids` returns `{id => 1}` and has three
  callers (`stats`, `determine_online_workers`, `API::V1::Worker::list`). The
  scheduler now needs the tag, not a boolean; T1 refactors this once instead of
  adding a second lookup method.
- This changes which workers `determine_online_workers` returns. Check that the
  "no workers online for requested class" reason strings built in
  `_allocate_jobs` stay truthful for jobs blocked only by the exclusivity rule —
  a job rejected because it lacks the tag must not be reported as "no workers
  online for class qemu_x86_64 at all".
- `Scheduler::WorkerSlotPicker` / `PARALLEL_ONE_HOST_ONLY`: a parallel cluster
  must not be split across a tagged worker and untagged ones. Matching happens
  before the picker, so this should hold by construction — assert it.
- `t/fixtures/02-workers.pl` has two workers with hard-coded counts asserted in
  `t/api/12-admin-workers.t` and `t/ui/15-admin-workers.t`. Create workers
  inside new subtests, do not touch fixtures.
- Reservations are per web UI. A worker connected to several web UIs is only
  tagged on the one where the reservation was made. Document it, do not try to
  solve it.

## Tasks

Each task is independently committable and must leave the test suite green.
T1 blocks T2.

---

### T1 — Refactor the bulk reservation lookup

Commit type: `refactor` (no behaviour change)

Changes:

- `ResultSet::Workers::reserved_worker_ids` → `active_reservations`, returning
  `{worker_id => {user_id, comment, t_created, t_expires, worker_class}}` built
  from the same single `WorkerProperties` query.
- Update the three callers to `keys %$reservations` / hash lookups:
  `ResultSet::Workers::stats`, `Scheduler::Model::Jobs::determine_online_workers`,
  `API::V1::Worker::list`.
- Move the property-hash → reservation-info conversion currently in
  `Result::Workers::_reservation_info` into `OpenQA::WorkerReservation` so the
  row-level and the bulk path share one mapping.

Tests:

- `t/38-workers-table.t`: adapt the existing reservation subtests to the new
  return shape; no new scenarios.

Acceptance: `t/38-workers-table.t`, `t/04-scheduler.t`, `t/api/01-workers.t`
green with unchanged behaviour.

---

### T2 — Model and scheduler: verification class

Commit type: `feat`

Changes:

- `OpenQA::WorkerReservation`: `RESERVED_WORKER_CLASS` property and a tag
  validation helper (decision 6).
- `Result::Workers::reserve`: accept and validate the tag; `reservation` exposes
  `worker_class`.
- `Result::Workers::accepts_classes($needed, $reservation_class = undef)`:
  true when the worker has all needed classes (existing `check_class` logic) and,
  if a tag exists, the needed set contains the tag.
- `Scheduler::Model::Jobs::determine_online_workers`: keep workers whose
  reservation carries a tag in the online pool; exclude only untagged ones.
- `Scheduler::Model::Jobs::_matching_workers`: call `accepts_classes` with the
  tag from `active_reservations`; drop the inline `all { check_class }`.
- Keep the rejection bookkeeping (`%rejected`, `current_reason`) truthful for
  jobs blocked only by the exclusivity rule.
- `ResultSet::Workers::stats`: tagged workers stay in `reserved_workers`.

Tests:

- `t/38-workers-table.t`, parametrised table: untagged reservation blocks
  everything; tagged with matching request accepts; tagged with non-matching
  request rejects; tag combined with a capability class; invalid tag rejected on
  `reserve`; `stats` buckets still sum up.
- `t/04-scheduler.t`: a job requesting the tag is assigned to the reserved
  worker; a job requesting only the production class stays scheduled with a
  truthful reason; releasing restores normal matching; a parallel cluster is not
  split onto a tagged worker.
- `t/05-scheduler-mocked.t`: tagged worker stays in the online set.

---

### T3 — API and audit payload

Commit type: `feat`

Changes:

- `API::V1::Worker::reserve`: `worker_class` parameter forwarded to the model,
  400 on an invalid tag; POD `=item` updated (it feeds the API help page).
- Audit payload of `openqa_worker_reserve` gains `worker_class`.
- `GET /workers/<id>` and `GET /workers` expose `worker_class` inside the
  existing `reservation` hash — no new top-level key, clients already parse that
  structure.

Tests:

- `t/api/01-workers.t`: reserve with a tag and assert it in the response and in
  the subsequent `GET`; invalid tag 400; tag present in the audit row; a
  reservation without a tag reports `worker_class` as absent, not empty string.

---

### T4 — CLI support

Commit type: `feat`

Changes:

- `lib/OpenQA/CLI/reservation.pm`: `--class|C=s`, forwarded as `worker_class`.
  Short option `-C` because `-c` is already `--comment`.
- `public/openqa-cli.yaml`: document it in the `reservation` block.
- Regenerate shell completions if `tools/generate-cli-completions` output is
  checked in.

Tests:

- `t/43-cli-reservation.t`: reserve with `--class` and assert the tag in the API
  response; invalid tag surfaces the API error message and a non-zero exit code.

---

### T5 — Admin UI

Commit type: `feat`

Changes:

- `reserve_modal.html.ep`: optional "Verification worker class" input with a
  hint that jobs must request this class explicitly.
- `admin_worker.js`: send the field; client-side pattern check mirroring
  decision 6 so the user gets feedback without a round trip.
- `worker_status.html.ep`: a tagged reserved worker renders as
  `Reserved (class <tag>)`; the popover shows the class next to owner, comment
  and expiry. Escape the tag like the other reservation values.
- `show.html.ep`: the reservation panel shows the class.

Tests:

- `t/ui/15-admin-workers.t`: reserve with a class through the modal, assert badge
  and popover content; invalid class shows the validation error without issuing a
  request.

---

### T6 — Documentation

Commit type: `docs`

Changes:

- `docs/UsersGuide.md`, "Reserving workers": new subsection _Keeping a reserved
  worker usable for verification_ covering the semantics of decision 2, why it
  replaces editing `WORKER_CLASS` in `workers.ini` (instant, no worker restart,
  not reverted by configuration management, visible in the web UI), that a
  tagged worker counts as reserved rather than idle in the statistics, and that
  reservations are per web UI. End-to-end example:

  ```
  openqa-cli reservation --class poo167749 --comment "poo#167749 verification" \
    --duration 1d <worker_id>
  openqa-clone-job --from openqa.suse.de 12345 WORKER_CLASS=poo167749
  openqa-cli reservation --release <worker_id>
  ```

- `docs/WritingTests.md`, "Assigning jobs to workers": one sentence that a
  reserved worker with a verification class only accepts jobs requesting that
  class, cross-linking `#reserving_workers`.

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

## Interaction with 111 (host reservations)

Independent, but they touch the same lines in five files:
`OpenQA::WorkerReservation` (`RESERVATION_PROPERTIES`), the `reserve` signature,
the reserve API action, the CLI option list and the reserve modal. Whichever
lands second resolves trivial conflicts and additionally has to:

- pass `worker_class` through the host reservation path, so a whole host can be
  put into verification mode in one call;
- include `worker_class` in the `worker_host_reserve` audit payload.

Add that as one extra commit to the second plan rather than pre-building it here.

## Open questions

- Auto-derive the tag from a bugref in the comment (`poo#167749` →
  `poo167749`)? Convenient but magic; left explicit until asked for.
- Offer a per-instance list of jobs scheduled for the tag in the worker details
  page, so an operator sees what the reservation is currently being used for?
  Deferred, needs a new query.

## Follow-ups (separate tickets under epic #167746)

- Reminder notifications before expiry (needs a notification channel first).
- Audit event when a reservation expires.
