# Task 135 (strata): Stabilize t/33-developer_mode.t — deterministic upload progress at pause

- Ticket: [poo#208245](https://progress.opensuse.org/issues/208245)
- Branch: `feature/135_poo208245_stabilize_full_stack_test`
- CI reference: https://github.com/os-autoinst/os-autoinst/actions/runs/38382984848/job/115247744421?pr=3123
- Sibling plan: `tasks/188_poo208245_stabilize_full_stack_test.md` (full-stack.t / missing job module, already implemented on this branch)

## Problem statement

`t/33-developer_mode.t` fails in the os-autoinst "openQA Fullstack" CI with:

```
Failed test 'Wait for (?^u:"outstanding_images":[1-9]*) timed out'
  at t/lib/OpenQA/Test/FullstackUtils.pm line 145
Bailout called. Further testing stopped: Test failed. BAIL OUT!
```

The failing run is flaky: the same PR produced a successful run (38382997264) minutes later. The PR content (dependabot bump of `actions/upload-artifact`) is unrelated.

## Analysis

Per upload cycle the worker posts upload progress to the liveviewhandler twice — before
image upload (`outstanding_images` = pending count) and after (`outstanding_images` = 0),
`lib/OpenQA/Worker/Job.pm:828-838`. Both posts are skipped when the progress info is
unchanged (`lib/OpenQA/Worker/Job.pm:927-938`).

During the 600 s `assert_screen` timeout the worker uploads every screenshot in each cycle
(interval 1 s with a liveview viewer connected, `lib/OpenQA/Worker/Job.pm:684`), and
`_ignore_known_images` (`lib/OpenQA/Worker/Job.pm:824`) drops images the web UI already
knows. At the pause `images_to_send` is therefore empty, both progress posts report 0, both
are skipped, and the developer console receives no `outstanding_images` message.

The test (t/33-developer_mode.t:240-245) waits for `"outstanding_images":[1-9]*` starting at
`$pause_start` (the `set_assert_screen_timeout":0` response, i.e. **before** the pause). It
passes only if a progress message with a non-zero count happens to land in that window. That
is incidental, not a property of the pause — hence the race.

The invariant the test should verify is: at the pause the worker uploads results up to the
current module, so the needle editor can be opened. Observable as
`upload_up_to_current_module:1` followed by `outstanding_images:0`.

## Architecture & proposed solution

Two independent changes, in this order:

1. **Worker**: post upload progress unconditionally on the transition into paused, bypassing
   the change detection. This makes the progress snapshot at the pause deterministic and
   improves the live UI (developer sees the upload state at the pause).
2. **Test**: assert the invariant (`upload_up_to_current_module` reached, then
   `outstanding_images:0`) instead of requiring a non-zero intermediate count.

The worker change alone does not fix the test (the forced snapshot reports 0 when nothing is
pending). The test change alone fixes the CI failure but loses the "progress reported while
uploading" coverage. Both together are the robust combination.

## Atomic tasks

### Task A — worker: force progress post on pause transition

Files: `lib/OpenQA/Worker/Job.pm`, `t/24-worker-jobs.t`

1. In `_upload_results_step_0_prepare`, after reading
   `$status{test_execution_paused}` (`lib/OpenQA/Worker/Job.pm:733`), detect the transition
   from not-paused to paused and set `$self->{_force_progress_post} = 1`. Keep the previous
   paused state in `$self->{_prev_test_execution_paused}`.
2. In `post_upload_progress_to_liveviewhandler` (`lib/OpenQA/Worker/Job.pm:916`), consume the
   flag with `delete` and skip the "progress unchanged" early return when it is set:

   ```perl
   my $force = delete $self->{_force_progress_post};
   return Mojo::IOLoop->next_tick($callback) unless $progress_changed || $force;
   ```

3. Unit test in `t/24-worker-jobs.t` following the existing "Dynamic schedule" pattern
   (status file written explicitly, `$client->sent_messages` inspected): run an upload cycle
   with `test_execution_paused: 1` in the status file twice with identical progress, and
   assert an `upload_progress` POST to `/liveviewhandler/api/v1/jobs/<id>/upload_progress`
   on the transition and none on the unchanged repeat. Test descriptions, no in-file comments.

Commit: `fix(worker): Post upload progress unconditionally on pause` with motivation +
details, referencing poo#208245 and the CI run.

Acceptance: unit test passes; new branch covered; `make tidy`, `make test-checkstyle` pass.

### Task B — test: assert the upload invariant at the pause

Files: `t/33-developer_mode.t`

Replace t/33-developer_mode.t:240-248 with:

```perl
my $reached_pos = wait_for_developer_console_like(
    $driver, qr/"upload_up_to_current_module":1/, 'upload reached the current module',
    ONE_MINUTE, $pause_start);
my $upload_done_pos = wait_for_developer_console_like(
    $driver, qr/"outstanding_images":0/, 'image upload has finished', ONE_MINUTE, $reached_pos);
```

Keep the `window.lastWaitForDevelConsoleMsgMatch` update (lines 249-251) and the existing
comment about message ordering if it stays accurate; drop the `[1-9]` expectation.

Commit: `test(devel-mode): Assert upload reached the current module at pause` with
motivation + details, referencing poo#208245 and the CI run.

Acceptance: test passes locally; no `[1-9]` expectation left; `make tidy`,
`make test-checkstyle` pass.

### Task C — campaign verification (no code change)

Race fixes cannot be proven by a single run. Methodology as used for the existing branch
commits:

1. Baseline: `make test-with-database TESTS=t/33-developer_mode.t` for N runs (N ≥ 100),
   record hits of `outstanding_images` timeout.
2. With Task A + Task B applied: same campaign, record hits.
3. Record the rate with a 95% Wilson CI in the commit message / ticket, as done for
   bf3a9f2b3 / a467d5a37 / 27137e564.

Deliverable: numbers in the ticket, no code change.

### Task D — coverage and CI check

- `COVERAGE=1 make test-unit-and-integration TESTS=t/24-worker-jobs.t` then
  `make check-line-coverage` for the new lines in `lib/OpenQA/Worker/Job.pm`.
- `COVERAGE=1 make test-unit-and-integration TESTS=t/33-developer_mode.t` (fullstack) for the
  test change.
- `make test-gitlint` after each commit.
- Push to `okurz` remote and open the PR against `os-autoinst/openQA` only after explicit
  user confirmation.

## Sequencing and interactions

- Task A and Task B touch different files; A is a behavior change, B is a test change →
  separate atomic commits, A first.
- The existing branch commits (`2167e01a6`, `27137e564`, `a467d5a37`, `bf3a9f2b3`) touch
  `lib/OpenQA/Worker/Job.pm` (`_upload_results_step_0_prepare`, `$finished` branch) and
  `t/full-stack.t`. Task A edits the same function; rebase on top of the existing commits to
  avoid conflicts.
- `t/full-stack.t` diagnostics from the existing branch are not used by
  `t/33-developer_mode.t` (they live in `show_job_info`); no reuse expected.

## Out of scope

- Changes in os-autoinst: `outstanding_images` is emitted by the openQA worker
  (`lib/OpenQA/Worker/Job.pm:924`), not by isotovideo.
- Increasing the `ONE_MINUTE` timeout: the message never arrives, so a longer timeout does
  not help.
- Making a non-zero `outstanding_images` deterministic by delaying uploads: harms the live UI.
- Pushing, PR creation, and any remote operation without user confirmation.
