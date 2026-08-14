# Motivation
The test `t/05-scheduler-full.t` occasionally fails due to a 60s timeout, or runs with extremely variable execution times (e.g., 16s to 46s). This is primarily caused by two issues:
1. The test spawns up to 50 unresponsive workers and 30 unstable workers as child processes. This enormous process creation overhead exhausts CPU resources, leading to timeouts in restricted environments.
2. The test relies on hardcoded loops with `sleep .1` or `sleep .5`, as well as arbitrary hardcoded iterations (e.g., waiting for `0 .. 12` workers when 30 are spawned), which makes synchronization fragile.

# Design Choices
1. **Reduce Worker Counts:** Change the number of spawned unresponsive and unstable workers from 50 and 30 down to 10. Since `OPENQA_SCHEDULER_MAX_JOB_ALLOCATION` is fixed to 10 at the top of the script, 10 workers are perfectly sufficient to test the "max allocation" and "heavy load" edge cases.
2. **Robust Synchronization:** Replace the manual `for` loops and `sleep` statements with the existing `wait_for` helper from `OpenQA::Test::Utils`. This allows for faster polling and explicit timeouts, preventing infinite hangs while speeding up execution when conditions are met early.
3. **Correct Wait Loop:** Fix the loop that waits for unstable workers to properly wait for all spawned instances (i.e. `1 .. $unstable_workers`) instead of the arbitrary `0 .. 12`.

# Benefits
- Vastly reduced CPU/memory footprint during the test run.
- Test execution time will be significantly lower and far more consistent.
- No more sporadic 1m timeouts, ensuring reliable CI and local execution.
