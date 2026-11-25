# 131 Showback aggregates: build, job group, overview, retry waste, latency

Theme: `174_job_impact_theme_overview.md`. Depends on: 126, 127.

## Goal

FinOps-style showback: unit economics per build and job group, and the impact
of re-runs separated by origin. This makes visible whether automatic retries or
manual restarts are the main source of retry cost.

It also reports the **added latency** of restarts (time-to-signal): how much
longer the product workflow waited because of a re-run. This shows that blind
manual restarts cost more than hardware time.

## Commit 1: feat: add impact aggregation resultset methods

- `lib/OpenQA/Schema/ResultSet/JobImpacts.pm`, `aggregate(%cond)`:
  - Filters: `group_id`, `BUILD`, `DISTRI`/`VERSION`, time range on
    `jobs.t_finished`.
  - Runs **one** SQL query joining `jobs`, grouped by `restart_origin`
    (NULL = first run).
  - Returns `{total => {jobs, seconds, energy_kwh, carbon_g, cost_total},
by_origin => {first_run => ..., user => ..., retry => ...,
auto_clone => ..., system => ...}}`.
- `added_latency(%cond)`:
  - For clones with origin X, sum `clone.t_finished - original.t_finished`
    (self-join on `jobs.clone_id`).
  - Report it per origin in hours.
- Tests: `t/job_impact_aggregate.t`, with fixtures for a group with first runs,
  user restarts, `RETRY` retries and auto clones:
  - totals and per-origin values;
  - latency per origin;
  - an empty result returns zeroes;
  - check `EXPLAIN` manually and note the result in the PR.

## Commit 2: feat(api): add impact aggregation endpoint

- `GET /api/v1/job_groups/:id/impact?build=…&from=…&to=…` and
  `GET /api/v1/impact?distri=…&version=…&build=…` (for the test overview).
- Validate the params with `$self->validation` and the existing patterns.
- Tests: `t/api/` covering the param validation and the returned structure.

## Commit 3: feat(webui): show impact on group, build and overview pages

- Job group page (`templates/webapi/main/group_overview.html.ep`):
  - A collapsible "Estimated impact (last 30 days)" card showing the totals
    and a breakdown table "first runs / manual restarts / automatic retries /
    auto-clone".
  - Each row shows €, g CO₂e, worker hours and added latency.
  - Load the card lazily via the API in `assets/javascripts/job_impact.js`.
- Build rows (`group_builds.html.ep`/`build_progressbar.html.ep`):
  - Show a small "≈ X €" in each build row's tooltip only. There is no extra
    column, to avoid clutter.
  - Fetch the values in one batched query for all visible builds, never per
    row.
- Test overview (`overview.html.ep`): a summary line above the table, e.g.
  "Estimated impact of shown jobs: ≈ … (re-runs: ≈ …, of which manual ≈ …)".
- Parent group page: optional, only if it is cheap with the same query.
  Otherwise move it to a follow-up.
- Tests:
  - `t/ui/` group overview and tests overview: the card or summary line is
    present with fixture values, and absent when disabled.

## Acceptance

- Page render time is not measurably affected, because aggregates are fetched
  lazily or in a single query.
- Numbers match the sum of `job_impacts` for the filter; tests check this
  invariant.

## Status

Implemented on branch `feature/131_job_impact_showback_aggregates`:

- Commit: `1a1b15750 feat: add job impact aggregation and showback metrics`

Verification:

- `make tidy` and `make test-checkstyle` passed cleanly.
- `make test-gitlint` passed across all commits.
- Full statement coverage verified on all modified lines.
