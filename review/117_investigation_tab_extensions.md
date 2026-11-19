# Investigation Tab Extensions

## 1. Context and Motivation
Following the epic defined in `tasks/116_openqa_retrigger_mitigation_plan.md` to mitigate the "retrigger and pray" anti-pattern, the Investigation tab in the openQA web UI needs to provide better actionable statistics and clear guidelines to reviewers.

This plan details the implementation steps to extend the Investigation tab with:
- Statistics on recent failures in the same scenario.
- Occurrences of the same module failures in the same build.
- Integration of `openqa-investigate` job results.
- A smart suggestion on whether to retrigger or investigate the failure deeper.

## 2. Execution Plan

### Task 1: Backend - Recent Scenario Failure Statistics
**Objective:** Fetch the count of recent failures in the same scenario to help identify flakiness or persistent regressions.
- **Changes in:** `lib/OpenQA/Schema/Result/Jobs.pm` (`investigate` sub).
- **Implementation:**
  - Using the list of `@previous` jobs currently fetched in `investigate`, take the most recent $N$ jobs (e.g., limit to 10).
  - Calculate statistics: total number of jobs evaluated vs. number of failed jobs.
  - Append this data to the returned hash (e.g. `same_scenario_statistics => { total => X, failed => Y }`).
- **Tests:** Adapt `t/api/29-investigate.t` or `t/ui/18-tests-details.t` to assert that these new properties exist in the JSON payload when a job has previous scenario runs.

### Task 2: Backend - Same Build & Module Failure Statistics
**Objective:** Look up if other jobs within the *same build* have failed in the *same test module(s)* to surface broad systemic issues.
- **Changes in:** `lib/OpenQA/Schema/Result/Jobs.pm` (`investigate` sub).
- **Implementation:**
  - Extract the failed modules of the current job.
  - Query jobs in the same `build` and `group_id` that are not the current job.
  - Filter these jobs based on whether they failed in one of the identical modules.
  - Append the count and IDs of these jobs to the returned hash (e.g. `same_build_module_failures`).
- **Tests:** Add test scenarios where multiple jobs in a build fail in the same module and verify the API returns the correct list/count.

### Task 3: Backend - `openqa-investigate` Results Integration
**Objective:** Surface automated `openqa-investigate` outcomes directly in the web UI.
- **Changes in:** `lib/OpenQA/Schema/Result/Jobs.pm` (`investigate` sub).
- **Implementation:**
  - Identify investigation jobs triggered by `os-autoinst-scripts/openqa-investigate`.
  - This can be done by querying the `JobSettings` table for `key => 'OPENQA_INVESTIGATE_ORIGIN'` where the value matches the current job's URI (e.g. `like => '%/t' . $self->id`).
  - Alternatively or additionally, parse the job's comments for the specific "Automatic investigation jobs" text block posted by the script.
  - Collate the status of these investigations (running, failed, passed) and append them to the returned hash.
- **Tests:** Insert mocked `openqa-investigate` origin settings into the test database and ensure the `investigate` response captures these jobs correctly.

### Task 4: Backend - Retrigger Suggestion Logic
**Objective:** Provide a boolean or textual recommendation if the reviewer should retrigger or not.
- **Changes in:** `lib/OpenQA/Schema/Result/Jobs.pm` (`investigate` sub).
- **Implementation:**
  - Combine data from Tasks 1-3.
  - Define simple heuristics:
    - If `openqa-investigate` confirmed an infra issue (or if test passed on investigate retry), suggest: `retry_recommended => 1` and a reason.
    - If scenario failure rate is 100% in the last 5 runs, or same module fails across 5+ jobs in the build, suggest: `retry_recommended => 0` and reason (persistent regression).
  - Expose this as `retrigger_suggestion` in the hash.
- **Tests:** Add specific unit tests to cover the various heuristic branches.

### Task 5: Frontend - UI Implementation
**Objective:** Update the Investigation tab to display the newly collected statistics gracefully.
- **Changes in:** `assets/javascripts/test_result.js`.
- **Implementation:**
  - Update `renderInvestigationTab(response)` to render HTML blocks for:
    - **Scenario Statistics:** e.g., "Failed 4 times out of the last 10 runs".
    - **Build Failures:** "3 other jobs in this build failed in module X".
    - **Investigation Jobs:** Links and statuses to spawned `openqa-investigate` runs.
    - **Suggestion:** A colored alert box (e.g., `alert-info` or `alert-warning`) explicitly stating whether a retry is recommended and why.
- **Tests:** Extend `t/ui/18-tests-details.t` utilizing the browser automation (`$driver`) to verify these UI elements appear when navigating to the Investigation tab.
