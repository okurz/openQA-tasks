# 091 197483 Abort results cleanup early

## Motivation
As identified in #197123, openQA can enqueue 35k+ cleanup+archiving minion jobs because a delayed and longer-running cleanup can iterate through all job groups and enqueue archiving jobs for all of them, or delete everything.
We should abort the `limit_results_and_logs` processing loop early by checking `df` inside the loop, rather than only at the very beginning of the minion task.

## Plan
1. In `lib/OpenQA/Task/Utils.pm`, implement `is_disk_usage_below_percentage(%args)` which performs the `df` check and returns a string message if the disk space is below the configured threshold (meaning we have enough free space). Refactor `finish_job_if_disk_usage_below_percentage` to use it.
2. In `lib/OpenQA/Task/Job/Limit.pm` inside the `limit_results_and_logs` while loop (`while (my $group = $groups->next)`), call `is_disk_usage_below_percentage`. If it returns a truthy message, log it with `$job->note(early_abort => $message)` and `last;` to break the loop. This will skip iterating over the rest of the groups and skip enqueuing more `archive_job_results` tasks, while still allowing the screenshot cleanup part of the task to run.
3. We should also do the same for `lib/OpenQA/Task/Asset/Limit.pm` inside its main loop, if there is a main loop. Let's add it in the `for my $asset (@$assets)` loop? Wait, `#197480` is "Abort assets cleanup soon". The ticket says "Look into #197480 how asset cleanup was adapted", maybe it was NOT adapted, but we should adapt BOTH? The AC3 says: "Any newly introduced tweaking parameters are configured alongside already existing parameters". Wait, no new parameters needed if we just use `asset_cleanup_max_free_percentage` and `result_cleanup_max_free_percentage`! But maybe we can just do the results cleanup for now, as the task is explicitly "Abort *results* cleanup soon". Actually, both loops can be aborted early.

4. Add tests for early abort in `t/42-df-based-cleanup.t` or `t/42-minion-job-cleanup.t`.

Let's execute this.
