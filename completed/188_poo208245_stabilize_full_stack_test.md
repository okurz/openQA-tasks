# Task 135: Fix concurrent worker result uploads (full-stack.t "Failed modules: boot")

- Ticket: [poo#208245](https://progress.opensuse.org/issues/208245) (sporadic `t/full-stack.t` failure, High)
- Branch: `feature/135_poo208245_stabilize_full_stack_test` (local only)
- CI reference: https://github.com/os-autoinst/os-autoinst/actions/runs/37812359129/job/113520465570

## Root cause (confirmed from existing log, no new repro needed)

Evidence: `/tmp/opencode/repro_dbg/webui_223.log` (worker and webui share `OPENQA_LOGFILE`), job 7:

```
41.879 Asking worker 1 to start providing livestream for job 7     <- browser already on /tests/N
42.750 isotovideo has been started
42.750 Starting livelog                                            <- upload chain 1
42.750 status post ... / 42.752 status post ...                    <- chain 2 (next_tick), both in flight
42.774 Upload concluded / 42.775 Upload concluded                  <- repeats every second from now on
45.829 status post: test_order entries=3     current_module=boot   (chain 1)
45.830 status post: test_order entries=undef current_module=boot   (chain 2, 1 ms later)
45.841 webui: Job module 'boot' not found for job 7 (existing modules: 0)
45.857 490 response: Failed modules: boot (remaining tries: 0) -> api-failure
```

Mechanism in `lib/OpenQA/Worker/Job.pm`:

1. The browser asks for a livestream before the backend is running. `_add_livelog_viewers(1)`
   only increments the counter (`is_backend_running` is false).
2. `_handle_engine_startup` schedules `_upload_results` via `next_tick`, then calls
   `_add_livelog_viewers(0)`. That sees viewers 0 -> 1 and calls `_upload_results` immediately.
   Then the `next_tick` call starts a second upload.
3. `_upload_results` is not re-entrant. It sets `_is_uploading_results` but never checks it.
   Each chain's `_upload_results_step_3_finalize` sets `_upload_results_timer`, and the second
   one overwrites the first without removing it, so two upload chains run for the rest of the job.
   This is the "two status posts / two Upload concluded per cycle" the previous session saw.
4. Once `test_order.json` appears, chain 1 reads it and sets `_current_test_module`
   synchronously. Chain 2 runs 1 ms later, sees a current module, and posts `boot => running`
   without `test_order`. If the webui processes chain 2's request first, it has no module rows -> 490.
5. `t/lib/OpenQA/Test/Utils.pm:419` sets `OPENQA_WORKER_CONNECT_RETRIES=1`, so a single 490
   is fatal in tests. In production, 490 is retried (poo#91902) and the race heals after
   `RETRY_DELAY`. What stays in production: duplicate status posts and duplicate upload
   cycles for every job that already has a live viewer when isotovideo starts.

Job 6 in `full-stack.t` is affected because the test opens `/tests/6` before
`start_worker_and_assign_jobs`, so a viewer exists before the backend starts. The low hit rate
comes from request ordering at the webui, not from the double chain itself: the double chain
shows up in every such run.

## Assessment of the previous session's work

- The DB path analysis (`update_status` -> `update_module` -> 490) is correct.
- "Path construction is not the bug" is correct but irrelevant.
- `t_updated` exactly 2 h before `t_created`: a timezone artifact (`now()` in SQL vs. Perl-side
  timestamp, CEST = UTC+2). Not related. Drop it.
- Run 43 (`boot` row existed, result `canceled`): one unexplained hit with no webui log.
  Don't chase it unless it recurs after the fix.
- ~1,500 full-stack runs were spent where reading the existing debug log would have been
  enough. Don't do more loop campaigns.
- `2167e01a6` (cherry-pick, `if ($finished)`): its commit message is wrong. The final upload
  already sends `_full_test_order` via `_has_uploaded_logs_and_assets`. The change also uploads
  everything as soon as isotovideo reports `finished`, before logs and assets are uploaded.
  Unrelated behaviour change. **Drop it.**
- `bf3a9f2b3`, `a467d5a37` (`show_job_info` extensions): they didn't help find the cause.
  **Drop them.**
- `27137e564` (webui warning for a missing module): this is what made the log readable, and
  it's cheap. Optional: propose it as a separate small PR, or drop it to keep the fix PR
  focused. Its commit message has repro statistics that should go.

## Proposal

Fix it in the worker: one small commit plus a unit test. No webui change, and no changes to
`full-stack.t`.

### Fix: make `_upload_results` non-reentrant

In `_upload_results`, if `_is_uploading_results` is set, defer instead of starting a second chain:

```perl
return $self->once(uploading_results_concluded => sub { $self->_upload_results($callback) })
  if $self->{_is_uploading_results};
```

- When the ongoing upload ends, `finalize` sets the timer and emits the event. The deferred call
  removes that timer (existing code at the top of `_upload_results`), so only one chain is left.
- Callbacks of stop paths (`stop`, `_stop_step_*`) are kept and run after the ongoing upload.
  This matches `_invoke_after_result_upload`.
- Livelog start still triggers a prompt upload, right after the ongoing one.
- Check: `conclude_upload_if_ongoing` (Worker.pm:337, websocket loss) emits the event while the
  HTTP request may still be pending. With the guard, the deferred upload starts then. That's
  acceptable because it's the degraded path, but confirm with the existing tests around
  t/24-worker-jobs.t:567.

Rejected alternatives:

- Only reorder `_handle_engine_startup`: fixes the startup trigger but not re-entrancy from
  `start_livelog` during an ongoing upload.
- Always send `test_order` on every post: hides the symptom, adds payload, and two chains would
  still run.
- Webui creates module rows from the result payload: wrong layer, and the schedule metadata is
  missing.
- Raise `OPENQA_WORKER_CONNECT_RETRIES` in tests: hides real API failures in tests.

## Test adaptations (`t/24-worker-jobs.t`)

- Mock `client->send` to record calls and hold callbacks. Call `_upload_results` twice. Assert
  one `jobs/N/status` post is in flight. Release the first callback. Assert the second post
  starts only then and that only one `_upload_results_timer` exists afterwards.
- Startup scenario: livelog viewer registered before the engine runs (as at
  t/24-worker-jobs.t:816-828), then `_handle_engine_startup` / `_add_livelog_viewers(0)` plus
  the `next_tick`. Assert there are never two concurrent status posts.
- Existing livelog/upload subtests must still pass unchanged.
- `COVERAGE=1 make test-with-database TESTS=t/24-worker-jobs.t`, then `make check-line-coverage`.

## Verification

- `make tidy`, `make test-checkstyle`, `make test-gitlint`.
- Check without a hit-rate campaign: run `t/full-stack.t` 3 to 5 times with `OPENQA_LOGFILE`.
  Assert that no pair of `Upload concluded` lines a few ms apart appears for job 6/7. The double
  chain shows up in every affected run, so this check is reliable without waiting for a 0.5% hit.

## Steps

1. Reset the branch to `ebf995c11`. Keep `27137e564` on a separate branch if it will be proposed.
2. Implement the guard and the unit tests (one `fix(worker):` commit, motivation in the body,
   `Related issue: https://progress.opensuse.org/issues/208245`).
3. Run the verification above, then open the PR (only after the user approves).
4. Ticket comment: root cause in 3 lines, PR link. The os-autoinst CI picks up the fix through
   the openQA container/master it uses.

## Out of Scope

- os-autoinst changes.
- `show_job_info` diagnostics.
- Full-stack hit-rate campaigns.
