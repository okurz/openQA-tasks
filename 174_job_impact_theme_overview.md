# 174 Job Impact Assessment – theme overview

## Goal

Make the economic cost (€) and environmental impact (g CO₂e) of openQA job
execution visible, mainly where users decide to restart a job. This should lead
to fewer blind restarts. Retries remain possible and are never blocked.

## Terminology (replaces "footprint")

The theme uses the term **impact assessment**. It comes from ISO 14040/14044
Life Cycle Impact Assessment (LCIA), where it means measuring **impact
categories** per **functional unit**. Here the functional unit is one job
execution, and there are three categories:

- `energy` (kWh)
- `carbon` (g CO₂e)
- `cost` (€)

Names used in code:

| Purpose        | Name                                                |
| -------------- | --------------------------------------------------- |
| Config section | `[job_impact]` (plus `[job_impact:<WORKER_CLASS>]`) |
| Module         | `OpenQA::JobImpact` (pure functions)                |
| Table          | `job_impacts`                                       |
| Worker keys    | `JOB_IMPACT_*`                                      |
| API field      | `impact`                                            |
| UI label       | "Estimated impact"                                  |

Alternatives considered:

- "footprint": casual wording, and it suggests carbon only.
- "resource accounting": implies billing-grade accuracy.
- "SCI": names only the carbon score.

## Decisions (from review)

- Restart UI **only shows** the estimate. A confirmation dialog above a
  threshold is **opt-in** (task 130).
- Human review cost is **opt-in** (task 133).
- Grid carbon intensity is a **static** configured value. A dynamic API is out
  of scope.
- **Only new jobs** get impact records. There is no backfill.
- Automatic retries (`RETRY`, `auto_clone_regex`) are legitimate. A night-time
  retry can finish before reviewers start their workday, which saves review
  time. Blind manual restarts are worse: they add hardware cost **and** block
  product workflows again until the new jobs finish. So the restart origin
  (user, `RETRY`, `auto_clone`) is recorded, and the impact of each origin is
  reported separately. The reports also include the **added latency** that a
  restart causes.

## Industry practices applied

- **Green Software Foundation SCI (ISO/IEC 21031):** carbon = `E × I + M`
  per functional unit, where E is energy, I is grid carbon intensity and M is
  the embodied share.
- **Cloud Carbon Footprint methodology:**
  - Energy = (vCPU-h × W/vCPU + GB-h × W/GB) × PUE.
  - Defaults: memory 0.392 W/GB; PUE is configurable.
- **FinOps Foundation:**
  - _Showback_ (making cost visible) comes before any _chargeback_ (billing
    teams).
  - Report unit economics (€ per job, per build, per job group).
  - Allocate costs by job group, which plays the role of tags.
- **Transparent estimates:**
  - Show the "≈" prefix and round to two significant digits.
  - Link to a methodology page.
  - Store the model version and the resolved factors with every record.
- **Snapshot the factors at completion:** changing a factor later does not
  rewrite history.
- **Nudge at the decision point, without dark patterns:** information comes
  first and friction is opt-in.
- **Per-job settings cannot override factors by default:** this prevents
  gaming the numbers. An admin can opt in.

## Model (summary, details in 124)

```
hours  = (t_finished - t_started) / 3600
power  = slot_power_w  ||  slot_base_w + vcpus*cpu_w + ram_gb*mem_w     (W)
energy = power * hours * pue / 1000                                      (kWh)
carbon = energy * grid_g_per_kwh + embodied_g_per_slot_hour * hours      (g)
cost   = energy * eur_per_kwh + hw_eur_per_slot_hour * hours
         [+ review_minutes{result} * reviewer_eur_per_hour / 60]   (opt-in)
```

The input values come from:

- `vcpus` = `QEMUCPUS` (default 1).
- `ram_gb` = `QEMURAM` in MiB / 1024 (default 1).
- The duration estimate for a **future** job, in order of preference:
  1. the duration of the job being restarted;
  2. the median duration of the last N runs of the same scenario;
  3. `MAX_JOB_TIME × TIMEOUT_SCALE`, marked as an upper bound.

## Factor precedence (most specific wins)

1. `default_config()` in `lib/OpenQA/Setup.pm`
2. `openqa.ini` `[job_impact]`
3. `openqa.ini` `[job_impact:<WORKER_CLASS>]`, using the first matching class
   of the job
4. `workers.ini` `JOB_IMPACT_*` keys, reported as worker properties
5. Job settings `JOB_IMPACT_*`, only if `allow_job_setting_overrides = 1`

## Task breakdown

Each task is a separate branch or PR with atomic commits.

| Task | Title                                                                | Depends on         |
| ---- | -------------------------------------------------------------------- | ------------------ |
| 124  | Model, config defaults and validation, methodology doc               | –                  |
| 125  | Worker-reported impact factors (`workers.ini`)                       | 124                |
| 126  | Record the restart origin on cloned jobs                             | –                  |
| 127  | `job_impacts` snapshot table, filled on job completion               | 124 (125 optional) |
| 128  | Expose the impact in the job API and on the job details page         | 127                |
| 129  | Restart estimate (cluster sum) in API, UI and CLI                    | 124, 127           |
| 130  | Opt-in restart confirmation threshold                                | 129                |
| 131  | Showback aggregates: build, group, overview, retry waste and latency | 126, 127           |
| 132  | Impact metrics in `/admin/influxdb/jobs`                             | 127 (126)          |
| 133  | Opt-in human review cost                                             | 124, 127           |

Parallelization:

- 124 and 126 can start immediately.
- 125, 127 and 129 follow 124.
- 128, 131, 132 and 133 can then run in parallel.
- 130 comes last.

## Cross-cutting requirements

- `make tidy` and `make test-checkstyle` pass, and `make test-gitlint` passes
  after committing.
- Every task uses `COVERAGE=1 make test-unit-and-integration TESTS=...` and
  `make check-line-coverage`, with full statement coverage of new lines.
- The feature is disabled with `[job_impact] enabled = 0`. The default is 1 for
  display, because the impact is shown only as an estimate.
- No JavaScript inline in templates. Use ES6 in `assets/javascripts/`.
- No computation per job on list pages. Read stored values or aggregate in SQL.
- Commits follow Conventional Commits. `feat` commits explain the motivation.
  Wrap at 50/80.

## Out of scope

- Dynamic grid intensity (Electricity Maps and similar).
- Backfilling historical jobs.
- Chargeback or billing.
- Blocking restarts.
