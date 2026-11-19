# 134 — Worker circuit breaker: auto-quarantine on consecutive backend setup failures

Refs: poo#208230, poo#201144, bsc#1265624. Complements (does not replace) salt-states-openqa `tasks/020_poo208230_better_monitoring_for_failed_job_clusters.md`.

## 1. Problem analysis — why the worker is not marked broken today

On s390x, QEMU deadlocks in kernel `exit_mmap` during teardown. The `openqa-worker` daemon stays alive and keeps polling; each job fails *inside* the test harness during backend setup/teardown (`svirt`/`bootloadr_zkvm`: `virsh define failed ... domain already exists`, `virsh destroy ... SIGKILL: Device or resource busy`, `LIBSSH2_ERROR_TIMEOUT`, `cannot acquire state change lock`). Blast radius ~15-20 jobs / 12h, QE not notified.

The broken-state machinery exists but never triggers:

- `lib/OpenQA/Worker.pm` `sub status` (~line 271) reports `status => 'broken'` + `reason` only when `set_current_error_based_on_availability` (~line 756, backed by `check_availability` ~line 717) returns a reason. `check_availability` only knows about cache service, stray QEMU, pool dir, worker address, job locks (`Limited by configured lock ...`), load (`_check_system_utilization` ~line 873). A hypervisor that deadlocks per-job matches none of these.
- Webui side `lib/OpenQA/WebSockets/Controller/Worker.pm` (~line 137): on a `worker_status` message, `workers.error` is written via `$worker->seen({error => $current_worker_error})` only if the worker self-reports `broken`. Since it never does, `workers.error` stays NULL → salt-states telegraf query `broken_workers` (`monitoring/telegraf/telegraf-webui.conf:90`, filtered by `broken_ignore_reasons` at line 88) stays 0 → Grafana `Broken workers alert` (`monitoring/grafana/alerting/dashboard-WebuiDb.yaml:181`) never fires.
- Job-level reasons (`lib/OpenQA/Worker/Job.pm`, `lib/OpenQA/Constants.pm`): the s390x failures end with `WORKER_SR_DONE` (isotovideo exit 0, see `lib/OpenQA/Worker/Engines/isotovideo.pm` ~line 497: `exit_status == 0 ? WORKER_SR_DONE : WORKER_SR_DIED`) and a FAILED result — indistinguishable from a genuine test failure at first glance. `WORKER_SR_SETUP_FAILURE`/`WORKER_EC_CACHE_FAILURE`/`WORKER_EC_ASSET_FAILURE` only cover failures *before* isotovideo starts (`_handle_engine_startup` ~line 272, `_setup_error_category`).
- Dispatcher exclusion already works *given* a broken report: webui only sends `grab_job`/`grab_jobs` in response to a `free` status, and `lib/OpenQA/Worker/CommandHandler.pm` `_can_grab_job` (~line 134) rejects grabs while `current_error` is set; `_accept_or_skip_next_job_in_queue` (Worker.pm ~line 555) skips queued (incl. multi-machine sub-queue) jobs with `WORKER_SR_BROKEN` when `current_error_is_fatal`. So the fix is entirely worker-side: make the circuit breaker feed `check_availability`.

## 2. Design

### 2.1 Per-instance consecutive counter

- In-memory state on the worker instance object: `self->{_consecutive_backend_setup_failures}` (plus `self->{_quarantine_logged}` to log the transition once). Not persisted to disk: a daemon restart (`systemctl restart openqa-worker@N`) is a clean slate — deliberate, see §3.
- Incremented in `OpenQA::Worker::_handle_job_status_changed` (Worker.pm ~line 813) on the `stopped` event, next to the existing `failed_jobs` bookkeeping (~line 835: `$queue->{failed_jobs}->{$job_id} = $reason if $reason ne WORKER_SR_DONE || !$event_data->{ok}`).

### 2.2 Classification: backend setup failure vs test failure

Compute a boolean in `OpenQA::Worker::Job` (new `_is_backend_setup_failure($reason, $state, $result)`) and add it to the `stopped` event payload (`_stop_step_5_finalize` ~line 620 currently emits `stopped => {ok => $ok, reason => $reason}` → extend with `backend_setup_failure => 0|1`). Signals, in order:

1. Structural (no regex):
   - `reason eq WORKER_SR_SETUP_FAILURE` (any `_setup_error_category`: `WORKER_SR_SETUP_FAILURE`, `WORKER_EC_CACHE_FAILURE`, `WORKER_EC_ASSET_FAILURE`) — isotovideo never started.
   - `reason eq WORKER_SR_DIED` — isotovideo exit code != 0 (harness died; covers teardown-crash variants).
   - `reason eq WORKER_SR_TIMEOUT` only in the setup phase — same discriminator as `_format_reason` (~line 542): `!$self->{_engine}` means `setup exceeded MAX_SETUP_TIME`.
2. poo#208230 case (`reason eq WORKER_SR_DONE`, `!ok`, result FAILED/CRASHED/INCOMPLETE): count only if BOTH gates hold —
   - boot gate: the job never got past boot, proxied by no `screen*.png` in the pool directory (evaluate before `_clean_pool_directory` runs; the flag is computed in Job.pm before the event, so ordering is safe). A genuine flaky test failure has screenshots → never counted.
   - signature gate: the os-autoinst status `component`/`msg` already available to `_format_reason`'s `$state` matches a configurable regex. Default `WORKER_BACKEND_SETUP_FAILURE_REGEX` (new constant in `lib/OpenQA/Constants.pm`): `qr/virsh|domain already exists|cannot acquire state change lock|Device or resource busy|LIBSSH2_ERROR_TIMEOUT|SIGKILL/i`. Config override `BACKEND_SETUP_FAILURE_REGEX` (worker config, see §2.4).

Neutral reasons (never increment, never reset): `WORKER_SR_API_FAILURE`, `WORKER_COMMAND_*` (quit/cancel/obsolete), skips, parent-chain skips — those are not evidence about the hypervisor.

### 2.3 Broken-state write + exact message

New fatal branch in `OpenQA::Worker::check_availability` (after cache/QEMU checks, before the job-lock guard block):

```
return (0, "Quarantine: $n consecutive backend setup failures on hypervisor $host")
  if $counter >= threshold && threshold > 0
```

- availability `0` → `current_error_is_fatal` → `status()` sends `status => 'broken'` with that reason → webui writes `workers.error` verbatim (`seen({error => ...})`) → visible on `/admin/workers`, counted by both telegraf queries (`broken_workers`, `broken_worker_instances`) because the message matches none of the `broken_ignore_reasons` filters (`graceful disconnect%`, `limited%`, `%Cache service queue already full %`, `%average load%exceeding%`, `Worker cache not available via http://127.0.0.1%`). Do not prefix with `limited`/`worker broken`; keep the literal word `Quarantine:` as the grep handle.
- `$n` = counter, `$host` = `settings->global_settings->{WORKER_HOSTNAME} // '?'`. Example: `Quarantine: 3 consecutive backend setup failures on hypervisor s390x-worker1`.
- Log once on transition (`_quarantine_logged`), e.g. `log_warning('Quarantine: ...')`; subsequent status updates stay silent.

### 2.4 Config knobs (defaults in `lib/OpenQA/Worker/Settings.pm`, documented in `etc/openqa/workers.ini` + `docs/Installing.md`)

- `QUARANTINE_AFTER_BACKEND_SETUP_FAILURES` (default `3`; `0` disables the feature). Env alias `OPENQA_WORKER_QUARANTINE_AFTER_BACKEND_SETUP_FAILURES` comes free via Settings.pm's env overlay (~line 39). Default constant `DEFAULT_QUARANTINE_AFTER_BACKEND_SETUP_FAILURES` next to `DEFAULT_CRITICAL_LOAD_AVG_THRESHOLD` (~line 53 pattern).
- `BACKEND_SETUP_FAILURE_REGEX` (optional; falls back to the compiled-in constant).

## 3. Reset semantics

- Counter resets to 0 on any job that reached execution and did not classify as backend setup failure (PASSED, or genuine FAILED with boot evidence).
- Quarantine is a soft break: the worker stops accepting/grabbing jobs but the daemon stays alive and keeps sending `broken` status (keeps `t_updated` fresh → the 1h window in the Grafana queries holds). No auto-reboot, no `systemd` involvement, no `stop()` call.
- Clearing: restart the instance (`systemctl restart openqa-worker@N`) — in-memory counter resets; or a human/monitor via the existing admin path. Once counter < threshold, the next `check_availability` returns no reason and the next status update clears `workers.error` automatically.
- While quarantined no jobs run, so the counter cannot self-reset; that is intended (a dead hypervisor must not be probed again every hour).

## 4. Atomic tasks (one commit each)

Commit style: conventional 50/80 (`feat(worker): ...`), cf. repo history (`fix(navbar): ...`).

1. **Config knob + default** — `lib/OpenQA/Worker/Settings.pm` (`DEFAULT_QUARANTINE_AFTER_BACKEND_SETUP_FAILURES = 3`, `//= ` default like `CRITICAL_LOAD_AVG_THRESHOLD`), `etc/openqa/workers.ini` commented entry, `docs/Installing.md` paragraph.
   `feat(worker): Add QUARANTINE_AFTER_BACKEND_SETUP_FAILURES config knob`
2. **Failure classification** — `lib/OpenQA/Constants.pm` (`WORKER_BACKEND_SETUP_FAILURE_REGEX`), `lib/OpenQA/Worker/Job.pm` (`_is_backend_setup_failure`, pool-dir boot gate, extend `stopped` event payload in `_stop_step_5_finalize`).
   `feat(worker): Classify consecutive backend setup failures per job`
3. **Counter state storage** — `lib/OpenQA/Worker.pm` `_handle_job_status_changed`: increment/reset/neutral logic on `event_data->{backend_setup_failure}`, saturate at threshold, `_quarantine_logged` transition log.
   `feat(worker): Track consecutive backend setup failures in worker state`
4. **Broken-state write (quarantine branch)** — `lib/OpenQA/Worker.pm` `check_availability`: fatal `(0, "Quarantine: ... on hypervisor ...")` branch; no webui change needed (`seen({error})` path already generic).
   `fix(worker): Quarantine instance via fatal availability error`
5. **Dispatcher exclusion + tests** — no new dispatcher code (existing `_can_grab_job` reject + `grab_job` only on `free` status + sub-queue skip with `WORKER_SR_BROKEN` already cover it). Data-driven subtests:
   - `t/24-worker-overall.t`: availability subtest returns `(0, 'Quarantine: 3 consecutive ...')` at threshold; `status` subtest emits `broken` with that reason; `accept or skip next job` subtest asserts queued sub-queue jobs are skipped with `WORKER_SR_BROKEN` (multi-machine case); `t/24-worker-settings.t`: default `3`, `0` disables, env override works.
   - `t/24-worker-jobs.t`: `_is_backend_setup_failure` case table (desc-carrying rows: `WORKER_SR_SETUP_FAILURE` → 1, `WORKER_SR_DIED` → 1, setup timeout → 1, execution timeout → 0, `WORKER_SR_DONE`+FAILED+screenshots → 0, `WORKER_SR_DONE`+FAILED+no screenshots+`virsh define failed` msg → 1, `WORKER_SR_API_FAILURE` → neutral); `stopped` event payload carries the flag.
   - `t/38-workers-table.t`: webui `workers.error` set from broken status, message survives display/API.
   `test(worker): Cover backend setup failure quarantine circuit breaker`
6. **NEWS/docs note** — no `NEWS`/`CHANGELOG` file exists in the repo; the note lands in `etc/openqa/workers.ini` comment block + `docs/Installing.md` (same files as task 1, but a separate docs commit with the user-facing description and the poo reference).
   `docs(worker): Document worker auto-quarantine circuit breaker`

Order 1→6; each commit compiles and passes `make tidy`/`make test-checkstyle` before commit (AGENTS.md requirement).

## 5. Edge cases & safety

- **Genuine flaky tests**: double gate (no boot screenshots AND signature regex match). A test that booted and fails later is never counted; a boot failure with unknown msg is not counted until the regex list is extended — conservative by default.
- **Only pre-boot failures counted**: structural reasons are by definition before/at harness start; the DONE-case requires missing boot evidence. Execution timeouts (`_engine` set) and `WORKER_SR_DIED` after boot: DIED is counted deliberately (harness crash is infra, not test logic) — call this out in the test case table.
- **Multi-machine jobs**: quarantining mid-subsequence leaves the remaining queued sub-jobs skipped with `WORKER_SR_BROKEN` → INCOMPLETE with reason `worker broken: Quarantine: ...`. That string is not matched by salt-states `incomplete_ignore_reasons` (filters `quit%`, `tests died%`, `isotovideo died: Could not find %...`, `no test modules scheduled/uploaded%`, `asset failure: Failed to download%`) → visible in `incompletes_not_restarted_last_24h` and re-cloneable by the normal retry path. No new code.
- **Double quarantine**: counter saturates at threshold; `check_availability` branch is idempotent; transition logged once via `_quarantine_logged`. Skipped jobs emit no `stopped` event with the flag, so no re-increment loop.
- **Grafana greppability**: message must not match `broken_ignore_reasons` (verified against all five patterns; `Quarantine:` prefix chosen deliberately; do not reuse `limited`/`worker broken` prefixes). Status updates keep flowing while broken → `t_updated > now-1h` window holds.
- **Threshold 0** disables the feature entirely (no counter side effects).
- **`LOCK_NAME` throttling interplay**: quarantine branch precedes the lock-guard block in `check_availability` so a quarantined worker reports fatal even when a lock would only yield `(2, 'Limited ...')`.
- **Not persisted**: a crashed/restarted worker loses the counter; acceptable — a restart is a human action and the alert already fired.

## 6. Verification

```
perl -cw lib/OpenQA/Worker.pm lib/OpenQA/Worker/Job.pm lib/OpenQA/Worker/Settings.pm lib/OpenQA/Constants.pm
make tidy-perl && make test-checkstyle          # AGENTS.md: must pass before commits
make test-compile                               # t/compile/*.t
make test-with-database TESTS="t/24-worker-overall.t t/24-worker-jobs.t t/24-worker-settings.t t/38-workers-table.t"
COVERAGE=1 make test-with-database TESTS="t/24-worker-overall.t t/24-worker-jobs.t t/24-worker-settings.t"
make check-line-coverage                        # strict statement coverage of new lines
make test-t                                     # full t/*.t sweep before push
```

(`test-with-database` is the repo's runner target, `Makefile:298`; `TESTS` selects individual files, `Makefile:13-16`; `check-line-coverage` at `Makefile:410-412`.)
