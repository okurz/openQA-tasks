# poo#167749 — Simple system to reserve (and temporarily) disable openQA worker instances

Tickets:

- https://progress.opensuse.org/issues/167749 (this task, no description)
- https://progress.opensuse.org/issues/167746 (epic: Worker reservation/enable/disable)

Epic motivation (summary): worker hardware is often dedicated test hardware
that humans and other systems compete for. Allow users to
reserve/enable/disable worker instances with a comment and time tracking,
leveraging existing users + audit log, optionally reminding people to give the
systems back.

## Scope

**In scope**: reservation of individual worker _instances_, REST API, admin
UI, audit events, configurable defaults/limits, CLI support, documentation.

**Explicitly out of scope** (see "Follow-ups"): reservation of worker _class
combinations_, reminder notifications, shutting down the worker service,
hardware power control, reservation queues/waitlists.

## Design decisions

These are decisions, not options. Deviating during implementation requires
updating this document first.

1. **Reservation _is_ enable/disable.** The epic's three verbs collapse into
   one mechanism: reserving a worker disables it, cancelling the reservation
   enables it again. An indefinite reservation by an admin is what "disabled"
   means. No separate `enabled` flag, no second state machine.
2. **Instance-level only.** No worker class combinations. Taking a whole host
   out of rotation means reserving its slots — supported via multi-select in
   the UI and multiple IDs on the CLI. This is the single largest
   simplification in this plan; see "Cost of dropping class reservations".
3. **Plain columns on `workers`, no extra table.** With a 1:1 relation there
   is nothing to normalise, join or garbage-collect.
   - Rejected: `worker_properties` (no FK to `users`, no typed timestamps, and
     that namespace is owned by the worker's own capabilities).
   - Rejected: a `worker_reservations` table (only justified by class
     reservations, which are out of scope).
4. **Scheduler-level exclusion only.** The worker daemon and the websocket
   protocol are untouched. A reserved worker stays registered, keeps sending
   status and stays visible in the admin table; it is simply never offered a
   new job. Reserve/release is instant and needs no restart.
5. **A running job is never interrupted.** Reserving a busy worker takes
   effect when its current job finishes. The UI must show
   `Reserved (finishing job N)`. Do not add a kill path.
6. **Expiry is evaluated, not swept.** "Reserved" means
   `reserved_by_id IS NOT NULL AND (t_reservation_expires IS NULL OR
t_reservation_expires > now())`. No Minion task, no timer, no systemd unit,
   no spec-file change. Consequence: expiry is fail-open — if anything stops
   working, workers return to the pool rather than staying disabled.
7. **Exactly one definition of "reserved".** `ResultSet::Workers` exposes the
   SQL condition; `Result::Workers::is_reserved` is the Perl-side predicate
   implemented on top of the same semantics. Scheduler, API, UI and `stats`
   all go through these two, never through ad-hoc conditions.
8. **`status` gains `reserved`, ranked after `running`**: `dead`, `broken`,
   `running`, `reserved`, `idle`. Existing consumers only compare against
   `dead` (API delete gate, admin controller), so this is backwards
   compatible. `info` additionally always exposes a `reservation` hash so
   clients never parse labels.
9. **Reservations survive worker re-registration.** `_register` does a
   find-or-create on `(host, instance)`, so the row and its reservation
   persist. This is required behaviour, not an accident: the common case is
   "reserve the machine, then reboot/re-image it manually".
10. **Permissions**: operator or above may reserve. A user may release their
    own reservation; admins may release or override any. Overriding someone
    else's reservation requires admin plus explicit `force`.

### Cost of dropping class reservations

Honest accounting of what decision 2 gives up: there is no way to say "keep
any `tap`-capable worker free for me". Users must know and pick concrete
instances. For the stated use case — dedicated physical test hardware wired to
specific worker instances — that is the natural granularity anyway. If demand
for class reservations appears, the columns from decision 3 can be superseded
by a table without changing the API surface, because all callers go through
the ResultSet/Result methods of decision 7.

### What dropping class reservations simplifies

| Area           | With class combos                                                                                                | Instance-only                              |
| -------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| Schema         | extra table, two nullable target columns, mutual-exclusion check, cascade rules                                  | 4 columns on `workers`                     |
| Resolution     | "effective reservation" = own OR first matching class reservation                                                | direct column read                         |
| Class matching | normalise/sort class strings, reuse `check_class`, keep in sync with `_matching_workers`                         | none                                       |
| Scheduler      | prefetch reservations per tick, Perl-side filter, N+1 risk                                                       | one extra SQL clause in the existing query |
| API            | worker sub-resource _plus_ a `/worker_reservations` collection                                                   | one sub-resource, 2 verbs                  |
| Edge cases     | orphan class reservations, worker changes `WORKER_CLASS` while reserved, overlapping instance+class reservations | none                                       |
| UI             | separate reservation management view                                                                             | buttons in the existing table              |

## Configuration

New `[worker_reservation]` section in `openqa.ini`, added to
`OpenQA::Setup::default_config()` (`lib/OpenQA/Setup.pm:116`). Drop-in files
are handled generically by `OpenQA::Config::lookup_config_files`, so no extra
work is needed for `openqa.ini.d/`.

| Key                  | Default | Meaning                                                  |
| -------------------- | ------- | -------------------------------------------------------- |
| `default_duration`   | `5h`    | preselected duration when no explicit expiry is given    |
| `max_duration`       | `5d`    | upper bound selectable by operators                      |
| `admin_max_duration` | `0`     | upper bound for admins; `0` means unlimited (indefinite) |
| `comment_required`   | `1`     | whether a comment is mandatory                           |

Durations accept `<n>[smhd]`; a plain integer is seconds. `0` means
unlimited and is only accepted where the applicable maximum allows it.

Two hard requirements when adding these keys:

- `t/config.t:158` (`openqa.ini documentation check`) fails unless every new
  key is documented in `etc/openqa/openqa.ini`.
- `OpenQA::Utils` has `change_sec_to_word` (seconds → `5h`) but no inverse.
  Add a symmetric `parse_duration` next to it and use it for both config
  parsing and API input, so there is one format across ini, API, CLI and UI.

## Risks / things to verify during implementation

- `ResultSet::Workers::stats` re-derives status buckets independently of
  `Result::Workers::status`. Both must change together or the admin statistics
  line will contradict the table.
- `assets/javascripts/admin_worker.js` hard-codes the status column index `4`
  and the status filter option list. Both must be updated.
- Fixtures `t/fixtures/02-workers.pl` contain exactly two workers and several
  tests assert hard-coded counts (`t/api/12-admin-workers.t`,
  `t/ui/15-admin-workers.t`). Create reserved workers inside new subtests
  instead of changing fixtures.
- Timestamp comparisons must use the database clock consistently; openQA
  already has `DB_TIMESTAMP_ACCURACY` handling in `Workers::dead` — follow the
  same approach rather than comparing Perl `time` against DB values.

## Tasks

Each task is independently committable and must leave the test suite green.
T1 blocks the rest; T6 can be written in parallel but is committed last so it
documents shipped behaviour.

---

### T1 — Schema, config and model layer

Commit type: `feat`

Changes:

- `lib/OpenQA/Schema.pm`: bump `$VERSION` 105 → 106.
- `lib/OpenQA/Schema/Result/Workers.pm`: new columns
  - `reserved_by_id` bigint, nullable, FK → `users.id`, `on_delete => 'SET NULL'`
  - `reservation_comment` text, nullable
  - `t_reserved` timestamp, nullable
  - `t_reservation_expires` timestamp, nullable (NULL = indefinite)

  plus `belongs_to reserved_by => Users`, `is_reserved`, `reservation_info`,
  `reserve(%args)`, `release($user)`; `status` returns `reserved` after the
  `running` check; `info` gains `reservation`.
  `reserve`/`release` hold all business rules (permission, duration limits,
  comment requirement, conflict) so API, UI and CLI share one implementation.

- `lib/OpenQA/Schema/ResultSet/Workers.pm`: `not_reserved_condition` (the
  single SQL definition) and a `reserved` bucket in `stats`, with reserved
  workers excluded from `free_active_workers` so the buckets still sum up.
- `lib/OpenQA/Setup.pm`: `[worker_reservation]` defaults, duration parsing and
  validation with a warning + fallback on invalid values (matching how
  `worker_timeout` and `auto_clone_regex` are handled).
- `lib/OpenQA/Utils.pm`: `parse_duration`.
- `etc/openqa/openqa.ini`: document all four keys.
- Migration artefacts generated via `./script/initdb --prepare_init` and
  `./script/upgradedb --prepare_upgrade`: `dbicdh/_source/deploy/106/*`,
  `dbicdh/PostgreSQL/deploy/106/*`,
  `dbicdh/PostgreSQL/upgrade/105-106/001-auto.sql`.

Tests:

- `t/16-utils.t`: parametrised `parse_duration` cases including invalid input
  and round-tripping against `change_sec_to_word`.
- `t/config.t`: defaults present, invalid duration falls back with a warning,
  documentation check passes.
- `t/38-workers-table.t`: parametrised subtest table covering — reserved
  worker reports `reserved`; busy reserved worker still reports `running`;
  dead reserved worker still reports `dead`; expired reservation is not
  reserved; indefinite reservation stays reserved; release restores `idle`;
  reserving an already-reserved worker conflicts; admin `force` overrides;
  non-owner release is refused; duration above the applicable maximum is
  refused; missing comment refused/allowed per config; `stats` buckets sum up.

Acceptance: `make test-unit-and-integration TESTS=t/38-workers-table.t` (also
`t/16-utils.t`, `t/config.t`) passes; `COVERAGE=1` run plus
`make check-line-coverage` shows no uncovered new lines.

---

### T2 — Scheduler skips reserved workers

Commit type: `feat`

Changes:

- `lib/OpenQA/Scheduler/Model/Jobs.pm`: extend the search in
  `determine_online_workers` (`:32-41`) with
  `ResultSet::Workers::not_reserved_condition`. This single spot covers both
  `schedule()` and `_allocate_jobs()`. No prefetch, no Perl-side pass, no
  extra query.
- Ensure the rejection bookkeeping (`%rejected` in `_matching_workers`) still
  yields a useful reason so a job blocked only by reservations says so instead
  of degrading to a generic "no matching worker".
- Confirm and test that a job already running on a newly reserved worker is
  not cancelled.

Tests:

- `t/05-scheduler-mocked.t`: one of the three mocked workers reserved → not
  allocated.
- `t/04-scheduler.t`: subtest `job grab (worker reserved)` — reserve the only
  matching worker, assert the job stays scheduled; release, assert it is
  assigned; assert a running job survives reservation; assert an expired
  reservation does not block scheduling.

---

### T3 — REST API and audit events

Commit type: `feat`

Changes:

- `lib/OpenQA/WebAPI.pm`, worker route block (`:370-376`):
  - `$api_ro->post('/workers/<workerid:num>/reservation')` → `worker#reserve`
    (also used to extend/modify an existing own reservation)
  - `$api_ro->delete('/workers/<workerid:num>/reservation')` → `worker#release`
  - `$api_description{...}` entries for both
- `lib/OpenQA/WebAPI/Controller/API/V1/Worker.pm`:
  - `reserve`: params `comment`, `duration` (default `default_duration`,
    `0` = indefinite), `force` (admin only). 400 validation, 403 insufficient
    role, 404 unknown worker, 409 conflict.
  - `release`: 404 if not reserved, 403 if neither owner nor admin.
  - `list`: optional `reserved=0|1` filter.
  - `delete`: refuse deleting a reserved worker unless admin with `force`,
    so a reservation is never dropped silently.
  - POD `=item` blocks for every new action — they feed the API help page.
- `lib/OpenQA/WebAPI/Plugin/AuditLog.pm`: add `worker_reserve worker_release`
  to the worker event list (`:20`) and emit `openqa_worker_reserve` /
  `openqa_worker_release` with worker, user, comment and expiry. Events not
  registered there are silently dropped.

Tests:

- New subtests in `t/api/01-workers.t`: happy path reserve/release,
  unauthenticated 403, non-operator 403, conflict 409, admin `force` override,
  release by other user 403 and by admin 200, invalid duration 400, duration
  over the maximum 400, indefinite allowed for admin and refused for operator,
  missing comment per config, audit rows with the expected payload,
  `reserved` filter on `/workers`, delete of a reserved worker refused, and
  reservation surviving a re-registration via `POST /workers`.

---

### T4 — Admin UI

Commit type: `feat`

Changes:

- `templates/webapi/admin/workers/worker_status.html.ep`: `Reserved` badge
  with user, comment, `timeago` since `t_reserved`, remaining time or
  `indefinitely`, and `Reserved (finishing job N)` while still busy.
- `templates/webapi/admin/workers/index.html.ep`: reserved count in the
  statistics card; per-row reserve/release button for operators; multi-select
  checkboxes plus a bulk reserve/release action so a whole host can be taken
  out of rotation in one step (the mitigation promised in decision 2).
- `templates/webapi/admin/workers/show.html.ep`: reservation panel with
  owner, comment, since, expires and the reserve/release form.
- `assets/javascripts/admin_worker.js`: `reserveWorker()` / `releaseWorker()`
  via `fetchWithCSRF` against the T3 endpoints; modal with comment field
  (required per config) and duration selector prefilled with
  `default_duration` and capped at the applicable maximum, with an
  `indefinite` option only for admins; add `Reserved` to the status filter
  `<select>`; derive the status column index from the header cell instead of
  hard-coding `4`.
- `lib/OpenQA/WebAPI/Controller/Admin/Workers.pm`: pass reservation info
  through `_extend_info`, add the reserved count and the effective config
  limits to the stash.

Tests:

- `t/ui/15-admin-workers.t`: reserved badge, status filter option, reserve via
  modal, release, bulk action, button visibility for non-operators, comment
  requirement enforcement.
- `t/api/12-admin-workers.t`: assert `reservation` present in the JSON.

Acceptance: Selenium subtests pass; `make test-checkstyle` (eslint/prettier)
clean.

---

### T5 — openqa-cli support

Commit type: `feat`

Changes:

- New `lib/OpenQA/CLI/worker.pm` following the `archive.pm` pattern
  (`OpenQA::Command` subclass, `description`, `usage` via
  `OpenQA::CLI->_help('worker')`, `get_opt`):
  - `openqa-cli worker list [--reserved]`
  - `openqa-cli worker reserve <id>... --comment TEXT [--duration 5h] [--force]`
  - `openqa-cli worker release <id>...`
- `public/openqa-cli.yaml`: `worker:` block under `subcommands:` with summary,
  usage line and options.
- Human-readable output by default, `--json` passthrough via the existing
  `handle_result` machinery — do not reimplement formatting.

Tests:

- New `t/43-cli-worker.t` modelled on `t/43-cli-schedule.t`: embedded
  `OpenQA::WebAPI` daemon, `OPENQA_CLI_RETRIES=0`, assert usage output,
  argument validation, multiple IDs, and the three operations against the live
  API.

Acceptance: `openqa-cli worker --help` matches the YAML; tests pass.

---

### T6 — Documentation

Commit type: `docs`

Changes:

- `docs/Installing.md`: new `### Reserving workers` section after
  `### Worker settings` (`:1082-1116`) and next to
  `#### Stopping/restarting workers without interrupting currently running
jobs` (`:1145`), covering: reservation = disable, cancellation = enable;
  no job interruption; no service shutdown; reservations survive worker
  restarts; permissions; the `[worker_reservation]` keys and their defaults.
- `docs/Installing.md` audit event list (`:1537-1541`): add the new events.
  The pre-existing omission of `worker_delete` there is a separate commit.
- `docs/Client.md` / `docs/UsersGuide.md`: `openqa-cli worker` examples plus
  the equivalent raw calls, so the API is usable even without T5:

  ```
  openqa-cli api -X POST workers/42/reservation comment='manual testing' duration=5h
  openqa-cli api -X DELETE workers/42/reservation
  ```

- `docs/WritingTests.md` `### Assigning jobs to workers` (`:661`): one
  sentence that reserved workers are skipped by the scheduler, cross-linking
  the new section.

---

## Verification (every task)

```
make tidy
make test-checkstyle
COVERAGE=1 make test-unit-and-integration TESTS=<the tests touched>
make check-line-coverage
make test-gitlint
```

Commit messages: conventional commits, 50/80 rule, body with Motivation,
Design Choices, Benefits, and a trailing
`Related issue: https://progress.opensuse.org/issues/167749`.

## Follow-ups (separate tickets under epic #167746)

- Reminder notifications before expiry. openQA has no user notification
  channel today, so this needs its own design; do not bolt a mail stack onto
  this ticket.
- Audit event when a reservation expires (currently expiry is implicit; the
  expiry time is already recorded in the `worker_reserve` event).
- Reservation of worker class combinations, if per-instance granularity turns
  out to be insufficient in practice.
- Reservation queue/waitlist and "who is waiting for this machine".
- Interaction with `PARALLEL_ONE_HOST_ONLY` and
  `Scheduler::WorkerSlotPicker` when only some slots of a host are reserved —
  verify during T2 and split out if it turns out non-trivial.
