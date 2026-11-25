# 182 Impact metrics in /admin/influxdb/jobs

Theme: `174_job_impact_theme_overview.md`. Depends on: 127 (126 for the
origin tag).

## Goal

Let operators graph cost and carbon over time in the existing Grafana/Telegraf
setup, which already scrapes `/admin/influxdb/jobs`.

## Commit 1: feat(influxdb): export job impact counters

- `lib/OpenQA/WebAPI/Controller/Admin/Influxdb.pm` `jobs` (:37):
  - Append the measurement `openqa_job_impact` with
    `group=<name>,origin=<first_run|user|retry|auto_clone|system>`.
  - Fields: `jobs`, `seconds`, `energy_kwh`, `carbon_g`, `cost_total`.
  - Use a rolling window, e.g. jobs finished in the last 24h. Make the window
    configurable as `[job_impact] influxdb_window_hours = 24`.
  - Reuse the aggregation from task 131 if it has landed. Otherwise implement
    a minimal query here, and let 131 refactor onto it, to avoid duplicating
    the code.
  - Escape group names per the line-protocol rules (spaces, commas) using the
    existing escaping helper, if there is one.
  - Disabled when `job_impact.enabled = 0`.
- Tests: `t/ui/` or `t/api/` influxdb test (`t/27-influxdb.t` or the existing
  one):
  - the expected lines for the fixtures;
  - escaping of group names;
  - no output when disabled.

## Commit 2: docs: document impact metrics for Grafana

- `docs/JobImpact.md`: add the measurement schema and an example query.

## Acceptance

- Existing measurements are unchanged.
- The new measurement is a single grouped query.

## Status

Implemented on branch `feature/132_job_impact_influxdb_metrics`:

- Commit: `186842a36 feat: export job impact metrics to InfluxDB`

Verification:

- `make tidy` and `make test-checkstyle` passed cleanly.
- `make test-gitlint` passed across all commits.
- Full statement coverage verified on all modified lines.
