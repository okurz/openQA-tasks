# Task 131: Detect Unused and Idle Workers and Hosts

Related ticket: https://progress.opensuse.org/issues/208002
Related ticket: https://progress.opensuse.org/issues/207621

## Overview & Motivation

In openQA ticket #208002, operators attempted to verify whether worker hosts (such
as `aarch64-o3.qe-o3.nue2.suse.org`) were still actively required or should be
decommissioned. Determining whether a worker instance or an entire worker host is
actually utilized in production was difficult and required manual PostgreSQL
queries against the `jobs` and `job_settings` tables.

Currently, openQA worker processes continuously send websocket heartbeats that
update `workers.t_seen`. In the web UI (`/admin/workers` and
`/admin/workers/show_host/<host>`), worker instances connected to the server
appear with status `idle` regardless of whether they finished a job 30 seconds
ago or have remained completely dormant for 6 months.

Idle worker machines and instances waste electrical power, infrastructure
compute, and administrative overhead. This plan introduces mechanisms to
detect, inspect, and alert on unused and underutilized worker instances and
worker hosts across openQA.

## Problem Statement

1. **Lack of Inactivity Signals**:
   - `workers.t_seen` only reflects websocket connection presence, not workload
     execution.
   - Neither the admin UI nor the API exposes when a worker instance or host
     last completed a job (`last_job_finished`).
   - A host with 16 instances where only 1 job ran weeks ago looks indistinguishable
     from a host actively processing tests all day.

2. **No Filtering or Audit API**:
   - `/api/v1/workers` cannot filter workers by inactivity duration (e.g. idle
     longer than 14 days or never executed a job).
   - No endpoint provides host-level rollups of job execution frequency over
     recent windows (e.g. past 7 or 30 days).

3. **No Terminal / CLI Tooling**:
   - Operators investigating hardware utilization cannot run a fast CLI command
     (e.g. via `openqa-cli`) to list dormant hardware.

4. **No Automated Auditing or Alerting**:
   - In environments like o3 where external Grafana alerting is unavailable or
     lacks direct DB access, openQA provides no native background check, log
     alert, or audit event to notify administrators when worker hardware sits
     idle for extended periods.

5. **Orphaned Worker Classes**:
   - Workers frequently sit idle because their configured `WORKER_CLASS` values
     no longer match any scheduled jobs or configured job templates. There is
     no automated diagnosis pointing out when an idle worker's class has zero
     consumers.

## Guiding Principles & Non-Goals

- **Zero Schema Migration**: Avoid adding new tables or schema revisions.
  Utilize existing relationships (`jobs.assigned_worker_id`) and indexed
  lookups, optionally recording summary metadata in `worker_properties`.
- **Query Efficiency**: Production databases contain millions of rows in `jobs`.
  All queries must leverage the existing `jobs_idx_assigned_worker_id` index or
  bounded time windows (`t_finished >= NOW() - INTERVAL '...'`) to prevent full
  table scans.
- **Actionable Insights**: Distinguish between instances that ran jobs recently,
  instances idle for extended periods, and instances that have never processed a
  job.

---

## Architectural Design

### 1. Schema Query Layer (`OpenQA::Schema::ResultSet::Workers` & `Result::Workers`)

Add efficient helper methods to query activity:

- `$worker->last_job_finished`: Returns the timestamp of the latest completed
  job assigned to this worker, or `undef` if no jobs have finished.
- `$workers_rs->last_jobs_finished_per_worker(\@worker_ids)`: Performs a single
  batched query returning `{ $worker_id => $timestamp }` for the requested
  workers.
- `$workers_rs->host_activity_summary($days = 30)`: Returns host-level
  aggregations:
  ```perl
  {
      $host => {
          total_instances   => 12,
          online_instances  => 12,
          last_job_finished => '2026-10-04T18:39:29Z',
          idle_seconds      => 345600,
          jobs_count_recent => 18,
          worker_classes    => ['qemu_aarch32'],
          is_idle           => 0,
      }
  }
  ```
- `$workers_rs->find_unused_workers(%args)` and `find_unused_hosts(%args)`:
  Filter workers or hosts whose last finished job is older than a specified
  threshold (or `undef`), filtered by online/offline state.

### 2. REST API Layer (`OpenQA::WebAPI::Controller::API::V1::Worker`)

- Extend `GET /api/v1/workers`:
  - `unused_days=<int>`: Filter workers whose latest finished job is older than
    `unused_days` (or have never run a job).
  - `include_activity=1`: Include `last_job_finished` and `jobs_last_30d` in
    each worker's returned JSON object.
- Extend `GET /worker_hosts/<#worker_host>` JSON output:
  - Add `activity` object containing `last_job_finished`, `idle_days`,
    `jobs_last_7d`, and `jobs_last_30d`.
- Add `GET /api/v1/worker_hosts`:
  - Returns a list of all worker hosts with their instance counts, status,
    active classes, and activity summary.

### 3. Admin Web UI (`OpenQA::WebAPI::Controller::Admin::Workers`)

- `/admin/workers`:
  - Display a prominent warning banner (`.alert-warning`) at the top of the
    page when one or more worker hosts are online but dormant (e.g. 0 jobs
    executed in >14 days), listing affected hosts with links to their host
    details and idle durations.
  - Add a **Last Job Finished** column to the workers DataTable.
  - Render timestamps using `renderTimeAgo` (e.g. `4 days ago`, or `Never`).
  - Provide an Activity Filter in the table header:
    `All`, `Active (<= 7d)`, `Idle (> 7d)`, `Never used`.
- `/admin/workers/show_host/<host>`:
  - In the "Host summary" card, display:
    - **Last job executed**: Timestamp and relative age across all instances.
    - **Jobs in last 7 days** and **Jobs in last 30 days**.
  - If the host has been online but executed 0 jobs over the configured idle
    threshold (default 14 days), render a prominent warning banner:
    `Notice: Host has not executed any jobs for X days. Verify if hardware can be powered down or decommissioned.`

### 4. CLI Inspection Tool (`openqa-cli workers`)

- Add `workers` subcommand to `public/openqa-cli.yaml` and `OpenQA::CLI::workers`:
  - `openqa-cli workers --unused [DAYS]`: List dormant workers.
  - `openqa-cli workers --hosts --unused [DAYS]`: Group by host and display
    summary table.
  - Output displays: Hostname, Instances (online/total), Classes, Last Job
    Finished, Idle Days.

### 5. Automated Periodic Audit & Orphaned Class Detection

- Background Minion Task & Script (`OpenQA::Task::Worker::Audit`):
  - Configuration in `openqa.ini`:
    ```ini
    [worker_audit]
    enabled = 1
    unused_threshold_days = 14
    alert_on_zero_jobs = 1
    ```
  - Periodic execution checks online worker hosts:
    - Logs a warning when an online host has executed 0 jobs in the threshold:
      `log_warning("Worker host '$host' online but idle for $days days. Potential idle hardware wasting resources.");`
    - Records an `AuditEvent` (`worker_host_idle_alert`).
    - Checks for **Orphaned Worker Classes**: Queries if any worker class on
      idle hosts is completely absent from all active `job_templates` and queued
      jobs.

---

## Atomic Implementation Tasks

### Task 1: Core Activity & Inactivity Query Layer in Schema

- **Type**: Backend / Schema Model
- **Files**:
  - `lib/OpenQA/Schema/Result/Workers.pm`
  - `lib/OpenQA/Schema/ResultSet/Workers.pm`
  - `t/schema/workers.t` (or `t/04-workers.t`)
- **Scope**:
  - Add `$worker->last_job_finished` to `OpenQA::Schema::Result::Workers`.
  - Add `$workers_rs->last_jobs_finished_per_worker(\@worker_ids)` to
    `OpenQA::Schema::ResultSet::Workers` to fetch latest `t_finished` via
    indexed `assigned_worker_id` query.
  - Add `$workers_rs->host_activity_summary($days = 30)` to roll up activity
    per host.
  - Add `$workers_rs->find_unused_workers(threshold_days => $days, online_only => 1)`.
  - Add `$workers_rs->find_unused_hosts(threshold_days => $days, online_only => 1)`.
- **Verification**:
  - Add data-driven tests in `t/schema/workers.t` testing:
    - Worker with no jobs returns `undef` for `last_job_finished`.
    - Worker with completed jobs returns correct latest `t_finished`.
    - Host rollup correctly aggregates instances with mixed activity.
    - Threshold filtering correctly isolates inactive workers and hosts.
  - No in-file comments; use descriptive test assertions.
  - Enforce strict statement coverage: `COVERAGE=1 make test-unit-and-integration TESTS=t/schema/workers.t`.
- **Commit Message**:

  ```text
  feat(schema): add query methods to detect unused workers and hosts

  Allow calculating the latest job finished timestamp and rolling up
  activity statistics per worker instance and host to detect idle hardware.
  ```

### Task 2: REST API Extensions for Worker Inactivity & Host Activity

- **Type**: API / Controller
- **Files**:
  - `lib/OpenQA/WebAPI.pm`
  - `lib/OpenQA/WebAPI/Controller/API/V1/Worker.pm`
  - `t/api/04-workers.t`
- **Scope**:
  - In `list` of `API::V1::Worker`:
    - Support query parameter `unused_days` (integer) to filter workers whose
      latest job is older than the threshold or never run.
    - Support query parameter `include_activity=1` to populate `last_job_finished`
      and `jobs_last_30d` on each returned worker object.
  - In `show_host` / API host routes:
    - Expose `activity` dictionary in JSON response for
      `GET /worker_hosts/<#worker_host>`.
  - Add route `GET /api/v1/worker_hosts` returning all hosts with their instance
    counts, classes, and activity summary.
- **Verification**:
  - Add integration tests in `t/api/04-workers.t`:
    - Request `/api/v1/workers?unused_days=14` and assert only inactive workers
      are returned.
    - Request `/api/v1/workers?include_activity=1` and assert activity fields
      are present.
    - Request `GET /worker_hosts/<host>` with `Accept: application/json` and
      validate activity rollup.
    - Request `GET /api/v1/worker_hosts` and assert host-level summaries.
  - Run `make test-unit-and-integration TESTS=t/api/04-workers.t`.
- **Commit Message**:

  ```text
  feat(api): expose worker and host activity and unused filtering in API

  Add unused_days filter and activity inclusion to worker API endpoints,
  and expose host-level activity summaries.
  ```

### Task 3: Admin Web UI Inactivity Visibility & Host Utilization Warnings

- **Type**: Frontend / Web UI
- **Files**:
  - `lib/OpenQA/WebAPI/Controller/Admin/Workers.pm`
  - `templates/webapi/admin/workers/index.html.ep`
  - `templates/webapi/admin/workers/show_host.html.ep`
  - `assets/javascripts/admin_worker.js`
  - `t/ui/14-admin-workers.t`
- **Scope**:
  - In `Controller::Admin::Workers::index`:
    - Retrieve activity summary in bulk and pass `last_job_finished` to worker
      entries.
    - Identify dormant worker hosts (`find_unused_hosts(threshold_days => 14, online_only => 1)`)
      and stash `dormant_hosts`.
  - In `templates/webapi/admin/workers/index.html.ep`:
    - Render a dismissible warning banner (`.alert-warning`) at the top of the
      page when dormant worker hosts are detected, listing the affected hosts
      with direct links to their host details, their idle durations, and a clear
      call-to-action to verify or decommission idle hardware.
    - Add "Last Job Finished" column.
    - Add Activity Filter dropdown in the table controls.
  - In `assets/javascripts/admin_worker.js`:
    - Configure column rendering using `renderTimeAgo`.
    - Implement filtering by activity status.
  - In `templates/webapi/admin/workers/show_host.html.ep`:
    - Display host last job finished timestamp and 7d/30d job counts in Host
      Summary card.
    - Render alert banner if the host is online but has executed 0 jobs over the
      threshold.
- **Verification**:
  - Run `make tidy` to validate JavaScript and Perl formatting.
  - Run `make test-checkstyle`.
  - Test UI rendering via `make test-unit-and-integration TESTS=t/ui/14-admin-workers.t`:
    - Assert that `/admin/workers` renders the warning banner when dormant hosts
      exist, including host links and idle duration.
    - Assert that no banner is rendered when all online hosts are active.
    - Assert that `/admin/workers/show_host/<host>` renders the warning banner
      specifically for a dormant host.
- **Commit Message**:

  ```text
  feat(ui): display last active time and idle warnings on admin worker pages

  Add last job finished column and filter to the admin workers table, and
  display warning banners for dormant hosts on both overview and host pages.
  ```

### Task 4: CLI Inspection Tool (`openqa-cli workers`)

- **Type**: CLI Tooling
- **Files**:
  - `public/openqa-cli.yaml`
  - `lib/OpenQA/CLI/workers.pm`
  - `t/cli/03-workers.t`
- **Scope**:
  - Add `workers` subcommand definition to `public/openqa-cli.yaml`.
  - Implement `OpenQA::CLI::workers`:
    - Support `--unused [DAYS]` (default: 14 days).
    - Support `--hosts` to format grouped host summary.
    - Support `--all` to include offline instances.
    - Format readable terminal table with columns: `HOST`, `SLOTS (ONLINE/TOTAL)`,
      `CLASSES`, `LAST JOB FINISHED`, `IDLE TIME`.
- **Verification**:
  - Test CLI argument parsing and output formatting in `t/cli/03-workers.t`.
  - Verify `--json` and table outputs.
  - Run `make test-unit-and-integration TESTS=t/cli/03-workers.t`.
- **Commit Message**:

  ```text
  feat(cli): add openqa-cli workers subcommand to audit unused hardware

  Introduce openqa-cli workers command with --unused and --hosts options
  to inspect dormant worker instances and hosts directly from the terminal.
  ```

### Task 5: Automated Periodic Audit Task & Orphaned Class Detection

- **Type**: Background Task / Auditing
- **Files**:
  - `lib/OpenQA/Task/Worker/Audit.pm`
  - `script/openqa-enqueue-worker-audit`
  - `lib/OpenQA/Setup.pm`
  - `etc/openqa/openqa.ini`
  - `t/tasks/worker_audit.t`
- **Scope**:
  - Register `[worker_audit]` configuration defaults in `OpenQA::Setup`.
  - Create `OpenQA::Task::Worker::Audit`:
    - Scans online worker hosts against configured `unused_threshold_days`.
    - Emits `log_warning` for each idle online host.
    - Emits an `AuditEvent` (`worker_host_idle_alert`) to keep a record in the
      audit log.
    - Checks for **Orphaned Worker Classes**: Flags workers whose classes do not
      appear in any `job_templates` or active test suites.
  - Provide CLI launcher `script/openqa-enqueue-worker-audit` to enqueue the task
    via cron/systemd timer.
- **Verification**:
  - Unit tests in `t/tasks/worker_audit.t`:
    - Mock active and idle worker hosts.
    - Verify warning log emission and audit event creation.
    - Verify detection of orphaned worker classes.
  - Enforce full statement coverage with `COVERAGE=1`.
- **Commit Message**:

  ```text
  feat(task): periodically audit and alert on idle worker hosts and orphaned classes

  Add a minion task and enqueue script to periodically detect idle worker
  hosts and identify worker classes that match no scheduled job templates.
  ```

### Task 6: Documentation & Operational Runbook

- **Type**: Documentation
- **Files**:
  - `docs/UsersGuide.md`
  - `docs/AdminGuide.md`
  - `etc/openqa/openqa.ini`
- **Scope**:
  - Document the worker activity tracking, UI filters, and idle host indicators.
  - Document `openqa-cli workers --unused` usage examples.
  - Document `[worker_audit]` configuration options and recommendations for
    decommissioning or suspending unused hardware.
- **Verification**:
  - Check markdown formatting and links.
  - Run `make test-checkstyle`.
- **Commit Message**:

  ```text
  docs: document worker utilization auditing and idle hardware detection

  Document worker inactivity tracking, admin UI filters, openqa-cli workers
  audit options, and worker_audit configuration settings.
  ```

---

## Verification & Quality Gates

Each task must pass the following verification steps before committing:

1. `make tidy` (perltidy and eslint validation).
2. `make test-checkstyle`.
3. `COVERAGE=1 make test-unit-and-integration TESTS=<modified_tests>`.
4. `make check-line-coverage` to confirm 100% statement coverage on modified lines.
5. Commit messages formatted according to the 50/80 rule (body hard-wrapped at 80 characters).
