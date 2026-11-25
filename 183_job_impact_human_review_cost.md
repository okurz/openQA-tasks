# 183 Opt-in human review cost

Theme: `174_job_impact_theme_overview.md`. Depends on: 124, 127. This is
extended by 129 and 131 when they exist.

## Goal

Optionally include the estimated reviewer time in the € cost. Failed or
incomplete jobs, and the restarts that follow them, cost human attention, which
usually far exceeds the hardware cost. This is opt-in because putting a price
on human time is sensitive (decision).

## Commit 1: feat(config): add opt-in review cost factors

- `[job_impact]` gets these keys:
  - `reviewer_eur_per_hour`: empty means off.
  - `review_minutes_failed = 10`
  - `review_minutes_incomplete = 5`
  - `review_minutes_softfailed = 2`
  - `review_minutes_passed = 0`
  - `review_minutes_<other result>`: optional; a missing key means 0.
- Validate them in `read_config`.
- Tests: `t/config.t`.

## Commit 2: feat: include human review cost in assessment

- `OpenQA::JobImpact::assess` takes an optional `result` argument. If
  `reviewer_eur_per_hour` is set, it adds
  `cost.human = review_minutes{result} × eur_per_hour / 60` and includes it in
  `cost.total`.
- `compute_impact` (task 127) passes `$job->result` and stores `cost_human`.
- Restart estimate (task 129): the expected human cost of a re-run is the
  review cost weighted by the scenario's recent failure ratio. Use
  `review_minutes_failed × fail_ratio`, taken from the same history query.
  Document this approximation.
- UI (tasks 128 and 131):
  - Show "incl. ≈ X € reviewer time" as a separate line, never merged
    silently into the total.
  - Hide it entirely when the feature is off.
- Tests:
  - `t/job_impact.t`, data-driven: off by default; per-result minutes; an
    unknown result gives 0.
  - DB test: `cost_human` is stored.
  - UI test: the line is visible only when enabled.

## Acceptance

- With the default config, `cost_human` is NULL everywhere and nothing about
  human cost is visible in the UI.

## Status

Implemented on branch `feature/133_job_impact_human_review_cost`:

- Commit: `f19800af7 feat: add opt-in human review cost calculation`

Verification:

- `make tidy` and `make test-checkstyle` passed cleanly.
- `make test-gitlint` passed across all commits.
- Full statement coverage verified on all modified lines.
