# Plan - Address Review Comment on `REPO_MIRROR_HOST` Unexpanded Variables

## Motivation
In PR #6655, a review comment points out that worker-level variables (like `%REPO_MIRROR_HOST%`) are not expanded during `openqa-clone-job` execution (which runs on the client/caller's side), but are instead meant to be resolved by the worker when it executes the job. The recent commits (which added a `die` when any variable is unexpanded) cause cloning to fail when these worker-level variables are present in any of the job's settings or inside repository URLs.

## Design Choices
1. **Remove aggressive `die` on unexpanded variables**: In `collect_incident_repos`, we should not crash/die if some settings have unexpanded placeholders. Many jobs use worker-level settings/variables that are not meant to be expanded at clone-time.
2. **Handle unexpanded variables in repository URLs gracefully**: If an incident repository URL (e.g., from `INCIDENT_REPO` or SCC addon test repos) contains unexpanded variables, we cannot verify its availability. Instead of failing the clone job, we should skip verification for that specific URL and print/log a warning.
3. **Verify other repository URLs**: If some repository URLs can be fully expanded, we still verify them normally.
4. **Implementation details**:
   - In `lib/OpenQA/Script/CloneJobSUSE.pm` `collect_incident_repos`:
     - Retain `OpenQA::JobSettings::expand_placeholders($settings)` check to see if there is an expansion error (e.g. circular reference), and `die` on error.
     - Remove the `die` on any unexpanded variable in the whole `$settings`.
     - Pass the array of unexpanded variables `$unexpanded` to `verify_incident_repos` (or check inside it).
   - In `verify_incident_repos`:
     - Check if the repository URL contains any of the unexpanded variables (using `grep { $incident =~ /%\Q$_\E%/ } @$unexpanded`).
     - If it does, print/warn that it is being skipped and why.
     - Otherwise, test its availability via `ua->get`.
5. **Test adaptations**:
   - Update tests in `t/35-script_clone_job_suse.t` to assert that:
     - Unexpanded variables in job settings do NOT cause `detect_maintenance_update` to throw/die.
     - Repository URLs containing unexpanded variables are skipped from verification with a warning, and do not cause failure.

## Benefits
- Restores the ability to clone jobs that have worker-level or other unexpanded variables in their settings or repository URLs.
- Retains robust checks for actually-available, fully-expanded repository URLs.
- Provides helpful, non-fatal warnings when verification is skipped due to unexpanded placeholders.
