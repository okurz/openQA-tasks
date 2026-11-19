# Plan: Scaled Worker Load Check Periods (Ticket 203478)

## Critical Review of the Approach

Does the approach make sense? **Yes, absolutely.**

The root cause of the "boot avalanche" is the 5-second sampling lag of the OS's `load_avg`. During a trigger wave, all idle worker instances read a low load average simultaneously (because the QEMU processes haven't generated enough CPU ticks to reflect in `/proc/loadavg` yet) and accept jobs at the exact same millisecond. 

By introducing an intermediate state that applies a delay formula (`factor * load + rand(jitter)`), we artificially stagger the workers. 
1. The first worker to wake up from its sleep picks up a job and starts QEMU.
2. The subsequent workers, waking up a few seconds later, will re-read `load_avg`.
3. By the time they wake up and re-read, the 5-second OS lag has passed, and `/proc/loadavg` will reflect the true spiked load from the first worker. 
4. If the newly read load crosses `CRITICAL_LOAD_AVG_THRESHOLD`, the subsequent workers will reject the job, effectively breaking the synchronized avalanche.

**Caveat regarding Synchronous Blocking:**
Since `_check_system_utilization` is called within the worker's synchronous flow, a blocking `sleep()` will stall the `Mojo::IOLoop` for that specific worker process. While this pauses websocket processing (like responding to pings), it is an acceptable trade-off provided the calculated delay is reasonably short (e.g., typically under 15-20 seconds). Given your confirmation that synchronous blocking is intended, this approach provides the highest "bang for buck" in preventing load storms without the complexity of inter-worker IPC or file locks.

## Execution Plan

### Task 1: Configuration & Settings Implementation
**Objective:** Introduce the new load limiting parameters to the configuration parser and documentation, balancing detail and reducing duplication.
- **Actions:**
  - Update `lib/OpenQA/Worker/Settings.pm` to define defaults and read `WORKER_LOAD_LOW_LIMIT` (default 4), `WORKER_LOAD_FACTOR` (default 1), and `WORKER_LOAD_JITTER` (default 5).
  - Add logic to allow overriding via ENV variables.
  - Update `etc/openqa/workers.ini` to include comprehensive comments explaining the delay formula and the commented-out default settings.
  - Update `docs/Installing.md` to revise the paragraph about system load and thrashing. Describe conceptually how openQA staggers job acceptance under load, remove the redundant `CRITICAL_LOAD_AVG_THRESHOLD` ini block, and instruct users to check `workers.ini` for tuning parameters.
- **Commit:** `feat(worker): Add settings for load-proportionate scheduling delays`

### Task 2: Implement Load-Proportionate Delay Logic and Tests
**Objective:** Modify the worker's load checking mechanism to utilize the new settings and stagger job acceptance.
- **Actions:**
  - Update `lib/OpenQA/Worker.pm` `_check_system_utilization`:
    - Add the fast-path: if `$load->[0] < WORKER_LOAD_LOW_LIMIT`, immediately return `undef` (accept job).
    - If load is >= `WORKER_LOAD_LOW_LIMIT` but below `CRITICAL_LOAD_AVG_THRESHOLD`, calculate the delay: `my $delay = $factor * $load->[0] + rand($jitter);`.
    - Log the intent to sleep (e.g., `log_debug("Load is $load->[0]. Sleeping for $delay seconds before re-checking to prevent load storms.");`).
    - Execute a blocking `sleep($delay)` (using `Time::HiRes::sleep` for fractional seconds).
    - Re-fetch `load_avg()`.
    - Perform the critical threshold check (`max(@$load) > $threshold ...`) on the *new* load. Return the error string if it now exceeds the threshold.
  - Update `t/24-worker-overall.t` (and/or `t/24-worker-settings.t`):
    - When testing `CRITICAL_LOAD_AVG_THRESHOLD`, explicitly set `WORKER_LOAD_FACTOR = 0` and `WORKER_LOAD_JITTER = 0` to prevent the unit tests from taking a long time.
    - Mock `sleep` or add a specific test block to verify that the sleep logic is triggered correctly without blocking the CI for the full jitter duration. Ensure coverage reaches `100%` for the new lines.
- **Commit:** `feat(worker): Delay and re-check load to prevent boot avalanches`
  - Reference: `Related issue: https://progress.opensuse.org/issues/203478`
