# Dynamic Global Job Limit Based on System Load

Related issue: https://progress.opensuse.org/issues/198770

## Summary

Extend the openQA scheduler to dynamically adjust the effective global job
limit based on system load of the webUI host. The static `max_running_jobs`
becomes the upper ceiling; a new dynamic mechanism scales the effective limit
up or down within `[0, max_running_jobs]` based on configurable load
thresholds. Disabled by default (AC3).

## Definitions

**System load** (AC1): Linux load average from `/proc/loadavg` — specifically
the 1-minute, 5-minute, and 15-minute values. This is the same metric the
worker already uses in `_check_system_utilization`
(`lib/OpenQA/Worker.pm:808`). Load average captures CPU contention, I/O wait,
and runnable process count — the primary bottlenecks on an openQA webUI host
handling API requests, worker uploads, and filesystem operations.

## Design

### Architecture

```
openqa.ini [scheduler]
  max_running_jobs = 500          # hard ceiling (existing)
  dynamic_job_limit_enabled = 0   # feature switch (new, AC3)
  dynamic_job_limit_min = 50      # floor: never go below this (new)
  dynamic_job_limit_load_threshold = 0  # auto-detect: nproc * 0.85 (new)
  dynamic_job_limit_load_critical = 0   # auto-detect: nproc * 1.5 (new)
  dynamic_job_limit_step = 10     # scale increment/decrement (new)
  dynamic_job_limit_interval = 60 # seconds between adjustments (new)

                    ┌─────────────────────────────────┐
                    │  OpenQA::Scheduler::Model::Jobs  │
                    │  _allocate_jobs()                │
                    │                                  │
                    │  existing: $limit = config->{    │
                    │    scheduler}{max_running_jobs}   │
                    │                                  │
                    │  NEW: $effective = dynamic       │
                    │    job limit (if enabled) or     │
                    │    $limit (if disabled)          │
                    └───────────┬──────────────────────┘
                                │
                    ┌───────────▼──────────────────────┐
                    │  OpenQA::Scheduler::DynamicLimit  │
                    │  (new module)                     │
                    │                                  │
                    │  - Reads /proc/loadavg           │
                    │  - Maintains $effective_limit    │
                    │  - Adjusts conservatively on     │
                    │    each interval tick             │
                    └──────────────────────────────────┘
```

### Scaling Algorithm (AC2)

The algorithm runs every `dynamic_job_limit_interval` seconds (default 60s),
checked during each scheduler tick. The effective limit starts at
`dynamic_job_limit_min` on first enable.

```
load_1m, load_5m, load_15m = read /proc/loadavg
threshold = dynamic_job_limit_load_threshold  (or nproc * 0.85 if 0)
critical  = dynamic_job_limit_load_critical   (or nproc * 1.5 if 0)
step      = dynamic_job_limit_step
min_limit = dynamic_job_limit_min
max_limit = max_running_jobs

if max(load_1m, load_5m, load_15m) > critical:
    # Emergency: cut back aggressively
    effective_limit = max(min_limit, effective_limit - step * 3)
elif load_1m > threshold AND load_1m > load_5m:
    # Load rising above threshold: decrease conservatively
    effective_limit = max(min_limit, effective_limit - step)
elif max(load_1m, load_5m, load_15m) < threshold * 0.7:
    # Load well below threshold on all horizons: increase conservatively
    effective_limit = min(max_limit, effective_limit + step)
else:
    # Load near threshold or falling: hold steady
    no change

log_debug("Dynamic job limit adjusted: $effective_limit
           (load: $load_1m/$load_5m/$load_15m, threshold: $threshold)")
```

Key properties:

- **Conservative scaling up** (AC2): increases by `step` only when ALL load
  averages are well below threshold (70% factor provides hysteresis)
- **Faster scaling down**: decreases by `step` when rising above threshold,
  by `3*step` on critical overload
- **Trend-aware**: only decreases when load is rising (`load_1m > load_5m`),
  mirroring the worker's `_check_system_utilization` approach
- **Bounded**: never goes below `min_limit` or above `max_running_jobs`
- **Time-gated**: runs at most once per `interval` seconds, preventing
  oscillation

### Config Variables

| Variable                           | Default | Section       | Description                                                          |
| ---------------------------------- | ------- | ------------- | -------------------------------------------------------------------- |
| `dynamic_job_limit_enabled`        | `0`     | `[scheduler]` | Feature switch. `0` = disabled (AC3), `1` = enabled                  |
| `dynamic_job_limit_min`            | `50`    | `[scheduler]` | Floor for the dynamic limit                                          |
| `dynamic_job_limit_load_threshold` | `0`     | `[scheduler]` | Load avg above which scaling down starts. `0` = auto (nproc \* 0.85) |
| `dynamic_job_limit_load_critical`  | `0`     | `[scheduler]` | Load avg for emergency cutback. `0` = auto (nproc \* 1.5)            |
| `dynamic_job_limit_step`           | `10`    | `[scheduler]` | Jobs to add/remove per adjustment                                    |
| `dynamic_job_limit_interval`       | `60`    | `[scheduler]` | Minimum seconds between adjustments                                  |

### Interaction with Existing Gates

The dynamic limit integrates as a **replacement** for the static
`max_running_jobs` value in `_allocate_jobs()`. The existing disk-space gate
(`results_storage_above_threshold`) remains independent and takes precedence
(checked first). The flow becomes:

```
_allocate_jobs():
  1. Disk space gate (existing, unchanged)
  2. $limit = dynamic_limit_enabled ? effective_dynamic_limit : max_running_jobs
  3. if $limit >= 0 && $running >= $limit: return empty (existing logic)
  4. $max_allocate = min(MAX_JOB_ALLOCATION, $limit - $running) (existing logic)
  5. ... allocation loop (existing, unchanged)
```

## Implementation Steps

### Step 1: New Module `lib/OpenQA/Scheduler/DynamicLimit.pm`

Create a new module that encapsulates the dynamic limit logic:

```perl
package OpenQA::Scheduler::DynamicLimit;
use Mojo::Base -base, -signatures;
```

Responsibilities:

- Reuse `OpenQA::Worker::_load_avg()` by extracting it to a shared utility
  (see Step 2), or duplicate the simple 5-line helper
- Maintain `$effective_limit` as instance state
- Maintain `$last_adjustment_time` to enforce the interval
- Method `effective_limit($config)`: returns the current dynamic limit,
  performing an adjustment if the interval has elapsed
- Method `_adjust($load, $config)`: implements the scaling algorithm above
- Auto-detect `nproc` via `Sys::CPU::cpu_count()` or
  `Mojo::File->new('/proc/cpuinfo')` parsing for threshold auto-calculation

**Files to create:**

- `lib/OpenQA/Scheduler/DynamicLimit.pm`

### Step 2: Extract `_load_avg` to Shared Utility

Move the `_load_avg` function from `lib/OpenQA/Worker.pm:796-806` to a shared
location to avoid code duplication:

**Option A (preferred):** Add `load_avg()` to `lib/OpenQA/Utils.pm` alongside
the existing `check_df()` / `results_storage_above_threshold()` system
utilities.

**Option B:** Keep `_load_avg` in Worker.pm and duplicate the 5-line function
in DynamicLimit.pm. Simpler but introduces duplication.

Decision: Use **Option A** for zero duplication.

**Files to modify:**

- `lib/OpenQA/Utils.pm` — add `load_avg()` function
- `lib/OpenQA/Worker.pm` — replace `_load_avg()` with call to
  `OpenQA::Utils::load_avg()`

### Step 3: Add Config Defaults

Add the new config variables to `lib/OpenQA/Setup.pm` in the `scheduler`
section of `default_config()` (around line 137):

```perl
scheduler => {
    max_job_scheduled_time => 7,
    max_running_jobs => -1,
    dynamic_job_limit_enabled => 0,
    dynamic_job_limit_min => 50,
    dynamic_job_limit_load_threshold => 0,
    dynamic_job_limit_load_critical => 0,
    dynamic_job_limit_step => 10,
    dynamic_job_limit_interval => 60,
},
```

Add corresponding documentation comments to `etc/openqa/openqa.ini` in the
`[scheduler]` section (around line 425).

**Files to modify:**

- `lib/OpenQA/Setup.pm`
- `etc/openqa/openqa.ini`

### Step 4: Integrate into Scheduler

Modify `lib/OpenQA/Scheduler/Model/Jobs.pm` to use the dynamic limit:

1. Instantiate `OpenQA::Scheduler::DynamicLimit` as a singleton (or attribute
   on the Jobs model singleton)
2. In `_allocate_jobs()` (line 52), replace the direct config read with:
   ```perl
   my $limit = $self->_effective_job_limit;
   ```
3. Add method `_effective_job_limit`:
   ```perl
   sub _effective_job_limit ($self) {
       my $config = OpenQA::App->singleton->config->{scheduler};
       return $config->{max_running_jobs} unless $config->{dynamic_job_limit_enabled};
       return $self->dynamic_limit->effective_limit($config);
   }
   ```
4. Update the log messages to indicate whether the limit is dynamic or static.

**Files to modify:**

- `lib/OpenQA/Scheduler/Model/Jobs.pm`

### Step 5: Update UI to Show Dynamic Limit Info

Extend the running jobs API response and frontend display:

1. In `lib/OpenQA/WebAPI/Controller/Test.pm` `list_running_ajax()` (line 335):
   add `dynamic_job_limit` to the JSON response when the dynamic limit is
   active, showing both the current effective limit and `max_running_jobs`.

2. In `assets/javascripts/tests.js` (line 277): update the heading text to
   distinguish between static and dynamic limiting:
   - Static: `"N jobs are running (limited by server config)"`
   - Dynamic: `"N jobs are running (dynamic limit: M of max_running_jobs)"`

**Files to modify:**

- `lib/OpenQA/WebAPI/Controller/Test.pm`
- `assets/javascripts/tests.js`

### Step 6: Tests

#### 6a: Unit Tests for `OpenQA::Scheduler::DynamicLimit`

Create `t/26-dynamic-job-limit.t`:

- Test `load_avg()` (after extraction to Utils.pm) with mocked
  `$ENV{OPENQA_LOAD_AVG_FILE}`
- Test scaling up: low load on all horizons → effective limit increases by step
- Test hold steady: load near threshold → no change
- Test scaling down: rising load above threshold → decreases by step
- Test emergency cutback: critical load → decreases by 3\*step
- Test floor enforcement: never goes below `dynamic_job_limit_min`
- Test ceiling enforcement: never goes above `max_running_jobs`
- Test interval gating: rapid calls don't trigger multiple adjustments
- Test disabled: returns `max_running_jobs` when
  `dynamic_job_limit_enabled = 0`
- Test auto-detection of threshold from nproc

#### 6b: Adapt Existing Scheduler Tests

Modify `t/04-scheduler.t`:

- Add subtests for scheduling with dynamic limit enabled
- Verify that when dynamic limit is lower than `max_running_jobs`, only
  the dynamic limit number of jobs are allocated
- Verify that when dynamic limit is disabled, behavior is unchanged

#### 6c: Adapt Worker Tests

Modify `t/24-worker-overall.t`:

- Verify that `_load_avg` replacement (now calling `OpenQA::Utils::load_avg`)
  still passes all existing tests (subtest 'worker load', lines 128-141)

#### 6d: Adapt UI Tests

Modify `t/ui/01-list.t`:

- Add test for dynamic limit display text in the running jobs heading

**Files to create:**

- `t/26-dynamic-job-limit.t`

**Files to modify:**

- `t/04-scheduler.t`
- `t/24-worker-overall.t`
- `t/ui/01-list.t`

### Step 7: Documentation

Update AsciiDoc documentation:

- `docs/WritingTests.asciidoc`: add section on dynamic job limits alongside
  existing `CRITICAL_LOAD_AVG_THRESHOLD` documentation (around line 752)
- Or add to a more appropriate admin-facing doc if one exists

**Files to modify:**

- `docs/WritingTests.asciidoc` (or appropriate admin doc)

## Execution Order and Dependencies

```
Step 2 (extract load_avg)
  ↓
Step 1 (DynamicLimit module — depends on shared load_avg)
  ↓
Step 3 (config defaults — independent, can be done early)
  ↓
Step 4 (scheduler integration — depends on Steps 1-3)
  ↓
Step 5 (UI update — depends on Step 4)
  ↓
Step 6 (tests — depends on Steps 1-5)
  ↓
Step 7 (documentation — depends on Steps 1-5)
```

Steps 2 and 3 can be done in parallel. Steps 6 and 7 can be done in parallel.

## Verification Checklist

- [ ] `make tidy` passes
- [ ] `make test-checkstyle` passes
- [ ] `make test-unit-and-integration TESTS=t/26-dynamic-job-limit.t` passes
- [ ] `make test-unit-and-integration TESTS=t/04-scheduler.t` passes
- [ ] `make test-unit-and-integration TESTS=t/24-worker-overall.t` passes
- [ ] `make test-unit-and-integration TESTS=t/ui/01-list.t` passes
- [ ] Feature disabled by default (AC3): no behavior change without config
- [ ] With `dynamic_job_limit_enabled = 1` and low load: limit scales up to
      `max_running_jobs` over time (AC2)
- [ ] With `dynamic_job_limit_enabled = 1` and high load: limit scales down
      to `dynamic_job_limit_min`
- [ ] Existing tests unaffected (no regressions)

## Risk Assessment

| Risk                                          | Mitigation                                                                                                      |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Oscillation (rapid up/down)                   | Interval gating (60s default) + hysteresis (70% factor for scale-up)                                            |
| Over-aggressive cutback starves jobs          | Floor (`dynamic_job_limit_min`) prevents going to zero                                                          |
| Load avg doesn't capture I/O-bound load well  | Load avg on Linux includes I/O wait; future enhancement could add memory/IO metrics                             |
| Config complexity                             | Sensible defaults + auto-detection of thresholds from nproc; only one switch to enable                          |
| Race between scheduler ticks                  | DynamicLimit is a singleton with monotonic time checks; thread-safe within the single-process scheduler         |
| Breaking existing `max_running_jobs` behavior | When disabled, code path is identical to current; `max_running_jobs` remains the hard ceiling even when enabled |
