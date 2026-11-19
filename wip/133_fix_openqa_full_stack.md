# Execution Plan: Fix openQA Full-Stack Race Condition (poo#91902 / 490 Error)

This document outlines the atomic, independent tasks required to resolve the transient HTTP 490 (`Failed modules: boot`) race condition encountered during full-stack tests upon job restarts.

## Task 1: Decouple HTTP 490 Retries from `OPENQA_WORKER_CONNECT_RETRIES`

**Objective (1.A):** Ensure that the specific HTTP 490 response (missing module sync issue) receives a dedicated retry budget, independent of the global connection retry limits used to speed up tests.

*   **Target File:** `lib/OpenQA/Worker/WebUIConnection.pm`
*   **Implementation Steps:**
    1.  Locate `evaluate_error()`.
    2.  Modify the logic where `$$remaining_tries` is evaluated and decremented.
    3.  Add a condition: if `$error_code == 490`, ensure that `$$remaining_tries` has a guaranteed minimum floor (e.g., `$$remaining_tries = 3 if $$remaining_tries < 3;`) before decrementing, or track 490-specific retries in a separate counter.
    4.  Add/update tests in `t/api/04-jobs.t` or `t/24-worker-settings.t` to verify that a worker attempts to retry on a 490 error at least 3 times even if `OPENQA_WORKER_CONNECT_RETRIES=1`.
*   **Commit:** `fix(worker): Ensure minimum retries for HTTP 490 (missing modules)`

## Task 2: Robust `test_order` Transmission

**Objective (1.B):** Ensure the worker continues to include `test_order` in the status payload until the webUI acknowledges its receipt, preventing out-of-order API issues.

*   **Target File:** `lib/OpenQA/Worker/Job.pm`
*   **Implementation Steps:**
    1.  Introduce a state variable (e.g., `$self->{_test_order_acknowledged}`).
    2.  In the status construction logic (around lines 744-752), attach `$status{test_order}` not only if `$changed_schedule` or `not $current_test_module`, but also if `!$self->{_test_order_acknowledged}`.
    3.  In the response handler for the status post (where the worker receives a 200 OK from the server), set `$self->{_test_order_acknowledged} = 1` if `test_order` was successfully included in that payload.
    4.  Ensure that if `test_order.json` changes on disk, `_test_order_acknowledged` is reset to `0`.
*   **Commit:** `fix(worker): Resend test_order until acknowledged by server`

## Task 3: Server-Side Resilience for Missing Modules

**Objective (1.C):** Improve the server-side handling in `Jobs::update_status` to be more resilient when receiving results for modules that haven't been registered yet.

*   **Target File:** `lib/OpenQA/Schema/Result/Jobs.pm`
*   **Implementation Steps:**
    1.  Locate the section in `update_status` processing `$status->{result}` and collecting `@failed_modules`.
    2.  Before immediately returning a 490 error for a missing module (if `update_module` returns false), check if `$status->{test_order}` is present in the *same* payload.
    3.  If `test_order` is present, ensure `insert_test_modules` is completely processed and committed *before* attempting `update_module`. (Alternatively, if the job has 0 modules currently in the DB but is in a `RUNNING` state, temporarily buffer the result or auto-vivify the module to prevent dropping the payload).
    4.  Write/update unit tests in `t/api/04-jobs.t` to simulate a payload containing both `test_order` and `result` for a previously unknown module to guarantee it processes without a 490 error.
*   **Commit:** `fix(api): Handle results robustly if test_order is in same payload`
