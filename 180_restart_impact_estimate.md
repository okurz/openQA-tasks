# 180 Restart impact estimate (cluster sum) in API, UI and CLI

Theme: `174_job_impact_theme_overview.md`. Depends on: 124, 127.

## Goal

Show the expected cost of a restart **before** the user clicks, and show the
total already spent on previous attempts. This is display only; the opt-in
friction is task 130.

A restart duplicates the whole cluster (parallel and chained jobs, see
`auto_duplicate`/`cluster_jobs`), so the estimate is the sum over all jobs that
would be cloned. It honors the restart options `skip_parents`,
`skip_children` and `skip_ok_result_children`.

## Commit 1: feat: add restart impact estimation

- New function `OpenQA::JobImpact::estimate_restart` (or a method on Jobs,
  since it needs DB access; keep the math in `OpenQA::JobImpact`).
- Step 1: determine the jobs to clone with the same logic `duplicate` uses.
  Factor out the cluster selection into a reusable method in a separate
  `refactor:` commit first, so the logic is not duplicated.
- Step 2: estimate each job's duration, in order of preference:
  1. its own `job_impacts.seconds`;
  2. the median `seconds` of the last `history_runs` finished jobs with the
     same TEST/DISTRI/VERSION/FLAVOR/ARCH/MACHINE. Use one SQL query with
     `percentile_cont(0.5)`;
  3. `upper_bound_seconds`, flagged `upper_bound => 1`.
- Step 3: return `{jobs => n, seconds, energy_kwh, carbon_g, cost_total,
currency, upper_bound => bool}`.
- Step 4: compute the **previous attempts** total: the sum of `job_impacts`
  over the job's ancestor chain (`clone_id` back-links; reuse the
  `ancestors` logic). Group the total by `restart_origin` when task 126 is
  available.
- Tests (data-driven): `t/job_impact_restart.t`:
  - a single job;
  - a parallel cluster;
  - chained jobs with the skip options;
  - the history-median fallback;
  - the upper-bound fallback;
  - ancestor sums;
  - the feature disabled (returns undef).

## Commit 2: feat(api): add restart estimate endpoint and response field

- `GET /api/v1/jobs/:id/restart_estimate?skip_parents=…` returns the estimate
  JSON. Register the route in `lib/OpenQA/WebAPI.pm` next to `apiv1_restart`.
  It is read-only and has the same auth level as job GET.
- `POST /api/v1/jobs/:id/restart` and the bulk restart: add
  `impact_estimate` to the response. This is additive.
- Tests: `t/api/02-jobs.t`:
  - the endpoint returns the expected values for the fixtures;
  - 404 for an unknown job;
  - the restart response contains `impact_estimate`.

## Commit 3: feat(webui): show restart estimate at restart buttons

- Job details page (`infopanel.html.ep` :161–181):
  - Extend the existing restart help popover with:
    - "Restarting will run N job(s), estimated ≈ X € · ≈ Y g CO₂e (≈ Z h
      worker time)";
    - "Previous attempts so far: ≈ … (manual: …, automatic: …)";
    - a short hint: "Consider investigating first (Investigation tab)". Link
      to the existing investigation tab.
  - Load the estimate **lazily** via the new endpoint when the popover or
    restart dropdown opens. This adds no cost to page rendering.
  - New code goes into `assets/javascripts/job_impact.js` (ES6) and is wired
    up in `tests.js` `setupResultButtons()`.
- After the restart, the success message from `restartJob()` in `openqa.js`
  includes the estimate from the response.
- Test overview bulk restart (`restartJobsWithComment`): show the sum for the
  selected or visible jobs in the existing comment prompt. Compute it server
  side with one `restart_estimate` call per job batch, or reuse the
  aggregation from task 131 if it has already landed.
- Tests: `t/ui/18-tests-details.t`: opening the popover shows the estimate
  text (mock data). Bulk prompt text in `t/ui/10-tests_overview.t`.

## Commit 4: feat(client): print restart estimate in openqa-cli/clone-job

- `openqa-cli api -X POST jobs/:id/restart` already prints the JSON, so no
  change is needed.
- `script/openqa-clone-job`/`OpenQA::Script::CloneJob`: when the source host
  supports it, fetch `restart_estimate` and print one line:
  `Estimated impact: ≈ X € · ≈ Y g CO₂e for N job(s)`. Fail silently on 404,
  for older servers.
- Tests: `t/35-script_clone_job.t` with a mocked endpoint, covering both the
  present and the 404 case.

## Acceptance

- The estimate matches the cluster that a restart actually creates; tests
  compare it with the clone count of a real restart.
- There is no blocking and no extra click.

## Status

Implemented on branch `feature/129_restart_impact_estimate`:

- Commit: `8246a395b feat: add restart impact estimation in API, UI and CLI`

Verification:

- `make tidy` and `make test-checkstyle` passed cleanly.
- `make test-gitlint` passed across all commits.
- Full statement coverage verified on all modified lines.
