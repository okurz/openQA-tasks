# 175 Job impact model, config defaults and methodology doc

Theme: `174_job_impact_theme_overview.md`. Depends on: nothing.

## Goal

Build a pure, side-effect-free calculation module with configurable factors and
documented defaults. All later tasks build on it.

## Commit 1: feat(config): add [job_impact] section with defaults

- `lib/OpenQA/Setup.pm` `default_config()`: add `job_impact`:

| Key                           | Default    | Source / rationale                                                                               |
| ----------------------------- | ---------- | ------------------------------------------------------------------------------------------------ |
| `enabled`                     | 1          | Display only, so on by default                                                                   |
| `model_version`               | 1          | Bumped when the formula changes                                                                  |
| `currency`                    | `EUR`      | Display symbol is derived from it                                                                |
| `slot_power_w`                | `` (empty) | When set, a fixed per-slot wattage overrides the component model (bare metal, IPMI, s390, svirt) |
| `slot_base_w`                 | 20         | Idle share of the host per worker slot                                                           |
| `cpu_w`                       | 10         | W per vCPU at typical load (CCF midpoint for x86 servers)                                        |
| `mem_w`                       | 0.392      | W per GB RAM (CCF)                                                                               |
| `pue`                         | 1.5        | Typical enterprise data centre                                                                   |
| `grid_g_per_kwh`              | 300        | Rough EU grid mix average                                                                        |
| `eur_per_kwh`                 | 0.20       | Rough EU industrial electricity price                                                            |
| `hw_eur_per_slot_hour`        | 0.01       | Amortized hardware per slot                                                                      |
| `embodied_g_per_slot_hour`    | 1          | Amortized embodied carbon per slot                                                               |
| `default_vcpus`               | 1          | Used when `QEMUCPUS` is not set                                                                  |
| `default_ram_mb`              | 1024       | Used when `QEMURAM` is not set                                                                   |
| `history_runs`                | 10         | N runs used for the scenario median                                                              |
| `allow_job_setting_overrides` | 0          | Anti-gaming default                                                                              |
| `methodology_url`             | ``         | Optional link to a local policy page; defaults to the openQA docs                                |

- `read_config`:
  - Parse `[job_impact:<CLASS>]` sections from `ini_config` into
    `$config->{job_impact_by_class}{<CLASS>}`.
  - Validate the numeric keys with `looks_like_number` and require them to be
    > = 0.
  - Log a warning for an invalid value and fall back to the default. Follow the
    pattern of `_validate_worker_reservation_config`.
- `etc/openqa/openqa.ini`: add a commented example `[job_impact]` section and a
  `[job_impact:qemu_ppc64le]` example.
- Tests:
  - Extend `t/config.t`: the defaults are present; a class section is parsed;
    an invalid value falls back to the default with a warning (use
    `Test::Warnings`/`combined_like`).

## Commit 2: feat: add OpenQA::JobImpact calculation module

- New file `lib/OpenQA/JobImpact.pm`. It has no database or app access; the
  factors are passed in.
  - `resolve_factors(%args)`
    - Arguments: `config` (base hash), `by_class` (hash),
      `worker_class` (comma string), `worker_props` (hash),
      `job_settings` (hash).
    - Returns a hash ref with the merged factors and
      `sources => {key => 'default|ini|ini_class:<X>|worker|job'}`.
  - `resources(\%settings, \%factors)`
    - Returns `{vcpus, ram_gb}`.
    - Takes values from `QEMUCPUS`/`QEMURAM` and ignores values that are not
      numeric.
  - `power_w(\%resources, \%factors)`: `slot_power_w` if set, otherwise the
    component formula.
  - `assess(seconds => $s, resources => ..., factors => ...)` - Returns `{seconds, energy_kwh, carbon_g, cost => {energy, hardware,
total}, model_version}`. - Undefined or negative seconds return undef.
  - `upper_bound_seconds(\%settings)`:
    - `MAX_JOB_TIME` (default 7200, the worker default) × `TIMEOUT_SCALE`
      (default 1).
    - Read the worker defaults from `lib/OpenQA/Worker/Job.pm` and reuse a
      shared constant if one exists. Otherwise add the constant to
      `OpenQA::Constants` and use it in both places (a separate refactor
      commit before this one).
  - `format_estimate($assessment, $currency)`
    - Returns e.g. `≈ 0.042 €` / `≈ 12 g CO₂e`.
    - Two significant digits; switch to kg above 1000 g.
- Tests: new `t/job_impact.t`, data-driven:
  - A table of `{description, settings, factors, seconds, expected}` rows,
    checked with `is_deeply`/`within` (`Test::Number::Delta`, or compare to a
    rounded value).
  - Cover precedence: each level overrides the previous one; job overrides
    apply only when allowed; the first matching worker class wins.
  - Cover `slot_power_w` vs the component model, missing or non-numeric
    `QEMURAM`, zero or undef duration, the upper bound, and formatting
    boundaries (g→kg, small €).

## Commit 3: docs: add job impact methodology

- New page `docs/JobImpact.md`, linked from `docs/index.md` and the Installing
  guide's config section. Contents:
  - Terminology (LCIA, functional unit, categories).
  - Formula and the meaning of each factor, with references (GSF SCI,
    ISO/IEC 21031, CCF, FinOps showback).
  - The precedence order and config examples for `openqa.ini` and
    `workers.ini`.
  - Accuracy disclaimer: estimates may be off by 2–3×, and how to calibrate
    with measured wattage, e.g. IPMI/RAPL averages per slot.
  - Snapshot semantics and `model_version`.
  - No backfill: only jobs that finish after the feature is enabled get
    records.
- Check that the docs build (`tools/generate-documentation` if present)
  produces no new warnings.

## Acceptance

- `t/config.t` and `t/job_impact.t` are green with 100% statement coverage of
  `lib/OpenQA/JobImpact.pm` and the new `Setup.pm` lines.

## Status

Implemented on branch `feature/124_job_impact_model_and_config`:

- Commit 1: `656fef19f feat(config): add [job_impact] section with defaults`
- Commit 2: `6c50c3796 feat: add OpenQA::JobImpact calculation module`
- Commit 3: `0bc7d8ca1 docs: add job impact methodology`

Verification:

- `make tidy` and `make test-checkstyle` passed cleanly.
- `make test-gitlint` passed across all commits.
- `COVERAGE=1 make test-unit-and-integration TESTS="t/config.t t/job_impact.t"`:
  all tests passed with 100% statement coverage across all new lines in
  `lib/OpenQA/JobImpact.pm` and `lib/OpenQA/Setup.pm`.
