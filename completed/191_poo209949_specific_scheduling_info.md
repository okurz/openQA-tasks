# Task 142: Make openQA scheduler reasons specific for standalone and parallel jobs

- Ticket: [poo#209949](https://progress.opensuse.org/issues/209949)
- Branch: `feature/poo209949_oqa2_large_mem_scheduling`

## Approvals

- Decision: Implement specific scheduling reasons distinguishing standalone job worker classes, parallel cluster single-host constraints, and parallel cluster missing worker classes.
- Approver: User
- Date: 2026-11-09

## Gates

- Verification: `COVERAGE=1 make test-unit-and-integration TESTS=t/05-scheduler-mocked.t && make check-line-coverage && make tidy && make test-checkstyle`

## Session starter

```bash
git status
make test-unit-and-integration TESTS=t/05-scheduler-mocked.t
```

## Requirements & Problem Statement

On `/tests` and in individual job dependency views (e.g. `tests/<id>#dependencies`), jobs frequently display the generic status:
`Scheduling info: no matching worker is free`

In the `/tests` scheduled jobs popover, hundreds of jobs are lumped into:
`754 job(s): no matching worker is free`
in contrast to specific messages like:
`31 job(s): no free workers for class pc_azure_sap`

This message masks the actual reason why a job cannot be scheduled:

1. **Standalone jobs**: Matching free workers were present at the start of the scheduler tick, but were claimed by higher-priority jobs earlier in the cycle. The message does not mention which worker class was needed (`@needed`).
2. **Parallel cluster host constraints**: When `PARALLEL_ONE_HOST_ONLY` is required (e.g. for TAP networking), `WorkerSlotPicker` empties `matching_workers` if no single host provides enough matching slots. The job then receives the generic `no matching worker is free` instead of indicating that no single host has sufficient free slots.
3. **Parallel cluster sub-jobs**: When a specific sub-job in a cluster cannot find a free matching worker, it receives `no matching worker is free` without specifying its requested worker class. Furthermore, other sub-jobs that already had workers tentatively picked receive `no matching worker for all other jobs in the parallel cluster is free` only if they were the main job `$j`, while others get the generic fallback.

## Root Cause Analysis

In `lib/OpenQA/Scheduler/Model/Jobs.pm`:

- When a job has zero free workers at the beginning of the scheduler tick (`_matching_workers`), line 99 sets:
  `$has_matching_online ? "no free workers for class @needed" : "no workers online for requested class @needed at all"`
- However, if matching free workers existed at the start of the tick, the job enters `_allocate_jobs`.
- If `pick_slots_with_common_worker_host` returns empty slots due to host affinity constraints, or if `_pick_worker_for_sub_job` fails because workers were claimed by higher priority jobs or another cluster sub-job, line 162 falls back to:
  `'no matching worker is free'`
  This completely drops `@needed` and cluster context.

## Proposed Solution

1. **Host-affinity constraint failure**:
   In `lib/OpenQA/Scheduler/Model/Jobs.pm`, if `WorkerSlotPicker->pick_slots_with_common_worker_host` returns defined empty slots (`defined $slots && !@$slots`):
   Set reason to `'no matching worker is free on a single host for parallel cluster'` for all jobs in the cluster.
2. **Standalone jobs (`@tobescheduled == 1`)**:
   If allocation fails and no class limit was exceeded:
   Set reason to `@needed ? "no free workers for class @needed" : 'no matching worker is free'`.
3. **Parallel clusters (`@tobescheduled > 1`)**:
   - For the specific sub-job that failed to find a free worker:
     Set reason to `@needed ? "no matching worker for class @needed is free in parallel cluster" : 'no matching worker is free in parallel cluster'`.
   - For all other sub-jobs in the cluster (including those whose tentatively picked worker was discarded):
     Set reason to `'no matching worker for all other jobs in the parallel cluster is free'`.
4. **Tests and Coverage**:
   - Extend `t/05-scheduler-mocked.t` to verify:
     - Specific reason for standalone job when free worker is taken by higher-priority job.
     - Specific reason for parallel cluster single-host constraint failure.
     - Specific reason for parallel cluster sub-job missing worker class vs waiting siblings.
   - Verify strict statement coverage with `COVERAGE=1` and `make check-line-coverage`.

## Progress Log

- [x] Phase 1: Planning and task breakdown
- [x] Phase 2: Implementation in `lib/OpenQA/Scheduler/Model/Jobs.pm`
- [x] Phase 3: Test adaptations and additions in `t/05-scheduler-mocked.t`
- [x] Phase 4: Verification (`COVERAGE=1`, `make check-line-coverage`, `make tidy`, `make test-checkstyle`, `make test-gitlint`)
- [x] Phase 5: Commit via git-workflow (commit `f6c84d77e`)
