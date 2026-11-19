# History Isolation API Implementation Plan

## Analysis of UI vs API parity

The user asked if point 3 (Enhancing `latest` & `overview` grouping) is the most important to bring the API up to the UI's level.

Actually, the UI **only** offers history isolation on the specific **Job Details** page in the "Next & Previous results" tab (via `job_next_previous_ajax` and `strict_scenario_checkbox.html.ep`). 
The UI's global `overview` page does **not** currently group by isolation keys (it calls `complex_query_latest_ids` which strictly groups by `MAIN_SETTINGS`).

Therefore, implementing **Point 1 (A Dedicated Job History Endpoint)** is what directly achieves 1:1 parity with what the UI currently does.

## Step 1: Add Job History API Endpoint (Parity with UI)
* Adds `GET /api/v1/jobs/:jobid/history` to `lib/OpenQA/WebAPI/Controller/API/V1/Job.pm`.
* Exposes `strict`, `isolation_keys`, `previous_limit`, and `next_limit`.
* Wraps the existing `$schema->resultset('Jobs')->next_previous_jobs_query(...)` (the exact same method the UI uses).

## Step 2: Global List & Overview Support (Beyond UI parity)
* Allowing `/api/v1/jobs?latest=1` to separate jobs by isolation keys involves modifying `latest_jobs` in `ResultSet/Jobs.pm` to append isolation values to the deduplication `$key`.
* Allowing `/api/v1/jobs/overview` to separate jobs by isolation keys is more complex as `complex_query_latest_ids` runs a SQL `GROUP BY` on `MAIN_SETTINGS`. This will require either an API consumer passing specific `isolation_keys` as query parameters (so we can JOIN and GROUP BY those specific settings) or complex DB lateral joins.

## Recommendation
I recommend starting with **Step 1** because it natively provides the exact "strict history" feature the UI has, giving API consumers the ability to track a job's isolated history. After that, we can tackle **Step 2** to extend this concept globally.

