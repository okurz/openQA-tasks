# poo208245: Fix sporadic t/full-stack.t failure

Ticket: https://progress.opensuse.org/issues/208245

## Observation

CI (os-autoinst/os-autoinst run 37812359129) fails in `t/full-stack.t` test 6:
job 6 (clone of job 5) ends `incomplete` with
`api failure: 490 response: Failed modules: boot`. No autoinst-log is uploaded.

## Analysis

- `lib/OpenQA/Schema/Result/Jobs.pm` `update_status`: if a result module cannot
  be matched to a job module, it returns `490` with "Failed modules: ...".
  This is intentional (poo#91902, PR #3868): the worker should retry the upload.
- `lib/OpenQA/Worker/WebUIConnection.pm` `send`/`evaluate_error`: with
  `OPENQA_WORKER_CONNECT_RETRIES=1` no retry happens. A 490 then becomes
  `api failure`, the job is set `incomplete`.
- `t/lib/OpenQA/Test/Utils.pm:406` (`start_worker`) sets
  `OPENQA_WORKER_CONNECT_RETRIES = 1`. This defeats the 490 retry in the
  full-stack test.
- Default `RETRY_DELAY` is 5s, so one retry is cheap.
- Root cause of the missing module is not confirmed. Seven local runs of
  `t/full-stack.t` all passed.

## Plan

1. Set `OPENQA_WORKER_CONNECT_RETRIES` to 2 in `t/lib/OpenQA/Test/Utils.pm`
   so one retry is allowed. Keep the fail-fast intent.
2. Verify:
   - `make tidy` and `make test-checkstyle`
   - `COVERAGE=1 make test-unit-and-integration TESTS=t/full-stack.t`
     (fullstack target, requires `OS_AUTOINST_BASEDIR`)
3. Commit with a conventional message (`fix(tests): ...`), no push.

## Open points

- A retry only helps if the missing module appears before the retry, or if the
  retried payload carries `test_order`. Not verified.
- If the failure recurs, investigate the worker `test_order` handling in
  `lib/OpenQA/Worker/Job.pm` (`_upload_results_step_0_prepare`).
