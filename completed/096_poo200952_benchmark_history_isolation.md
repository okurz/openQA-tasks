# Plan: Benchmark history-isolation query for "Next & Previous"

Related issue: https://progress.opensuse.org/issues/200952

## Goal

Decide the final implementation of history isolation in
`ResultSet::Jobs::next_previous_jobs_query` based on measured performance on a
production-scale database (osd / o3), not guesses. The current implementation
keeps the raw-SQL `JobNextPrevious` view for the base scenario and filters its
already-limited result set with correlated `job_settings` subqueries. We must
confirm this does not regress the endpoint before merging, and choose between:

- **A (current):** view + `id IN (SELECT job_id FROM job_settings WHERE key=? AND value=?)` filter.
- **B:** rewrite the view to `JOIN`/`EXISTS` the isolation keys inside the CTE.
- **C:** denormalize an isolation hash into a new indexed `jobs` column.

## What the queries actually look like

`job_settings` has indexes `idx_value_settings (key, value)` and
`idx_job_id_value_settings (job_id, key, value)`
(`lib/OpenQA/Schema/Result/JobSettings.pm:43`).

The generalized path is the unchanged view. The isolated path wraps the view and
adds, per isolation key, a condition of the form
`me.id IN (SELECT job_id FROM job_settings WHERE key = 'PR_ID' AND value = '1234')`
plus an `OR me.id = <current job id>` so the current job always anchors the
table.

## Benchmark method

Run on the production replica or a low-traffic window. All statements are
read-only (`SELECT` / `EXPLAIN`). Do NOT run `ANALYZE` writes or DDL.

Two ways to execute, pick one:

- **You run it:** copy-paste the SQL blocks below into
  `psql -d postgresql://openqa:<password>@openqa.suse.de/openqa` and paste the
  output back here.
- **I run it:** I execute the same statements via
  `psql -d postgresql://openqa:<password>@openqa.suse.de/openqa -c '<statement>'`
  one at a time and incorporate the results. Confirm you are OK with me issuing
  read-only queries against production before I do.

### Step 0: pick a realistic, heavily-reused scenario

Find a scenario with a long history (worst case for the view) to make the
measurement meaningful.

```sql
-- top 10 scenarios by number of done jobs (worst-case histories)
SELECT DISTRI, VERSION, FLAVOR, ARCH, TEST, MACHINE, count(*) AS n
FROM jobs
WHERE state = 'done'
GROUP BY DISTRI, VERSION, FLAVOR, ARCH, TEST, MACHINE
ORDER BY n DESC
LIMIT 10;
```

Also find how isolation keys are distributed today (if any exist yet). If none
exist in production, we simulate with an existing high-cardinality setting such
as `BUILD` to measure the subquery cost realistically.

```sql
-- candidate isolation-like settings by cardinality (proxy for PR_ID)
SELECT key, count(DISTINCT value) AS distinct_values, count(*) AS rows
FROM job_settings
WHERE key IN ('BUILD', 'PR_ID', 'PACKAGE_TESTED', 'FLAVOR')
GROUP BY key
ORDER BY rows DESC;
```

From Step 0 pick: `:distri :version :flavor :arch :test :machine`, a
`:current_id` (a recent job id in that scenario), and an isolation
`:iso_key` / `:iso_value` (use `BUILD` + one of its values as the proxy if
`PR_ID` is absent).

### Step 1: baseline — generalized view (current production behavior)

```sql
EXPLAIN (ANALYZE, BUFFERS, TIMING)
WITH allofjobs AS (
    SELECT me.* FROM jobs me
    WHERE me.state = 'done'
      AND me.result NOT IN ('skipped','obsoleted','parallel_failed','parallel_restarted','user_cancelled','user_restarted')
      AND me.DISTRI = :'distri' AND me.VERSION = :'version' AND me.FLAVOR = :'flavor'
      AND me.ARCH = :'arch' AND me.TEST = :'test' AND me.MACHINE = :'machine'
)
(SELECT *, 'l' AS source FROM jobs
    WHERE DISTRI = :'distri' AND VERSION = :'version' AND FLAVOR = :'flavor'
      AND ARCH = :'arch' AND TEST = :'test' AND MACHINE = :'machine'
    ORDER BY id DESC LIMIT 1)
UNION (SELECT *, 'n' AS source FROM allofjobs WHERE id > :current_id ORDER BY id ASC LIMIT 100 + 1)
UNION (SELECT *, 'p' AS source FROM allofjobs WHERE id < :current_id ORDER BY id DESC LIMIT 400 + 1)
UNION (SELECT *, 'c' AS source FROM jobs WHERE id = :current_id)
ORDER BY id DESC;
```

Note: the six values above are the exact `ABORTED_RESULTS` from
`lib/OpenQA/Jobs/Constants.pm:89` (skipped, obsoleted, parallel_failed,
parallel_restarted, user_cancelled, user_restarted). The view uses six `?`
placeholders for them.

### Step 2: option A — view wrapped with the isolation subquery (as implemented)

```sql
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT * FROM (
    WITH allofjobs AS (
        SELECT me.* FROM jobs me
        WHERE me.state = 'done'
          AND me.result NOT IN ('skipped','obsoleted','parallel_failed','parallel_restarted','user_cancelled','user_restarted')
          AND me.DISTRI = :'distri' AND me.VERSION = :'version' AND me.FLAVOR = :'flavor'
          AND me.ARCH = :'arch' AND me.TEST = :'test' AND me.MACHINE = :'machine'
    )
    (SELECT *, 'l' AS source FROM jobs
        WHERE DISTRI = :'distri' AND VERSION = :'version' AND FLAVOR = :'flavor'
          AND ARCH = :'arch' AND TEST = :'test' AND MACHINE = :'machine'
        ORDER BY id DESC LIMIT 1)
    UNION (SELECT *, 'n' AS source FROM allofjobs WHERE id > :current_id ORDER BY id ASC LIMIT 100 + 1)
    UNION (SELECT *, 'p' AS source FROM allofjobs WHERE id < :current_id ORDER BY id DESC LIMIT 400 + 1)
    UNION (SELECT *, 'c' AS source FROM jobs WHERE id = :current_id)
    ORDER BY id DESC
) me
WHERE me.id = :current_id
   OR me.id IN (SELECT job_id FROM job_settings WHERE key = :'iso_key' AND value = :'iso_value');
```

### Step 3: option B — isolation folded into the CTE via EXISTS

```sql
EXPLAIN (ANALYZE, BUFFERS, TIMING)
WITH allofjobs AS (
    SELECT me.* FROM jobs me
    WHERE me.state = 'done'
      AND me.result NOT IN ('skipped','obsoleted','parallel_failed','parallel_restarted','user_cancelled','user_restarted')
      AND me.DISTRI = :'distri' AND me.VERSION = :'version' AND me.FLAVOR = :'flavor'
      AND me.ARCH = :'arch' AND me.TEST = :'test' AND me.MACHINE = :'machine'
      AND EXISTS (SELECT 1 FROM job_settings s WHERE s.job_id = me.id AND s.key = :'iso_key' AND s.value = :'iso_value')
)
(SELECT *, 'l' AS source FROM allofjobs ORDER BY id DESC LIMIT 1)
UNION (SELECT *, 'n' AS source FROM allofjobs WHERE id > :current_id ORDER BY id ASC LIMIT 100 + 1)
UNION (SELECT *, 'p' AS source FROM allofjobs WHERE id < :current_id ORDER BY id DESC LIMIT 400 + 1)
UNION (SELECT *, 'c' AS source FROM jobs WHERE id = :current_id)
ORDER BY id DESC;
```

Run each of Steps 1-3 three times; discard the first (cold cache) and record the
median of the remaining two.

## Metrics to record

For each option capture from the `EXPLAIN (ANALYZE, BUFFERS)` output:

- `Execution Time` (ms) — the headline number.
- `Planning Time` (ms).
- Whether the isolation subquery uses `idx_value_settings` (look for
  `Index ... idx_value_settings` vs. a `Seq Scan on job_settings`).
- Shared block hits/reads (buffer pressure).
- Row counts at the isolation node (selectivity).

Record in this table:

| scenario history size | option                     | planning ms | execution ms | job_settings access | notes |
| --------------------- | -------------------------- | ----------- | ------------ | ------------------- | ----- |
| (fill)                | A baseline (generalized)   |             |              | n/a                 |       |
| (fill)                | A isolated (view + IN)     |             |              |                     |       |
| (fill)                | B isolated (EXISTS in CTE) |             |              |                     |       |

## Decision rule → implementation impact

- If **A isolated** execution time is within ~1.5x of the **A baseline** and the
  subquery uses `idx_value_settings`: keep the current implementation. No code
  change; add a short note in the code comment citing the measured numbers.
- If **A isolated** regresses badly but **B** is within ~1.5x of baseline:
  switch the strict path to a dynamically-built CTE variant of
  `JobNextPrevious` (option B). This means generating the view SQL with the
  `EXISTS` clause when isolation keys are present; keep the static view for the
  generalized default.
- If **both A and B** regress on large histories: implement option C — a
  denormalized, indexed `history_isolation_hash` column on `jobs` populated at
  job creation from the declared keys, and match on it directly. This is the
  largest change (schema migration + backfill) and only justified if the query
  cost is proven unacceptable.

## Follow-up after measurement

1. Paste the raw `EXPLAIN ANALYZE` outputs into this file under a new "Results"
   section.
2. Apply the decision rule and, if a change is needed, implement it as a
   separate atomic commit amending `next_previous_jobs_query` (and the view for
   option B) with the benchmark numbers referenced in the commit body.
3. Re-run `t/10-jobs.t` and `t/ui/16-tests_job_next_previous.t` to confirm
   correctness is preserved by any query change.

## Results (measured 2026-07-17 on osd, openqa.suse.de)

Worst-case scenario chosen from Step 0: `sle/16.1/Online/x86_64/
sles_gnome@okynos/os-autoinst-distri-opensuse#master/64bit` with **13,683 done
jobs** (largest history in production). `current_id=22864032`.

Isolation-key proxy: production has no `PR_ID`/`PACKAGE_TESTED` yet (feature not
deployed). Used `BUILD_SLE=44.4`, which in this scenario matches **all 13,683
jobs** — i.e. zero selectivity, the pathological worst case for the isolation
filter (maximum settings rows to process, no history reduction).

Limits: previous=400, next=100 (production defaults). 3 runs each, warm figures
are runs 2-3.

| variant | planning ms | execution ms (cold / warm) | job_settings access |
|---|---|---|---|
| Baseline generalized (current prod) | ~2.0 | 76 / 73-84 | n/a |
| Option A: view + `id IN (subquery)` | ~2.7 | **5548** / 176-302 | hashed SubPlan, materializes all 13.7k matches |
| Option B: `EXISTS` inside CTE | ~2.7 | 154 / 140-154 | Index Only Scan `idx_job_id_value_settings`, 13,680 loops |
| Option E: materialized `iso` CTE + `id IN` | ~5 | 245 / 192-244 | worse than B |

### Analysis

- **Option A (as currently implemented) is unacceptable**: a 5.5s cold-cache
  execution and 2-4x warm regression. The outer `id IN (SELECT ... FROM
  job_settings)` builds a hash of every matching setting row regardless of how
  few rows the view returned.
- **Option B is the best isolated variant**: stable ~150ms, no cold cliff, ~2x
  baseline. It uses the `idx_job_id_value_settings` index via an Index Only Scan
  but pays one lookup per job in the history (13,680 loops here).
- The ~2x overhead is a **worst-case upper bound** driven by this scenario's
  zero selectivity (isolation value shared by all 13.7k jobs). The real intended
  use (`PR_ID` selecting a handful of jobs per submission) will make the
  isolated query *cheaper* than baseline, because the CTE shrinks to the few
  matching jobs. The measured 150ms is therefore a safe ceiling, not the
  expected cost.
- Isolation is opt-in and only requested when a job declares
  `_HISTORY_ISOLATION_KEYS`; the generalized default path is byte-for-byte the
  unchanged view (measured identical to current prod).

### Decision

Switch the strict path from **Option A to Option B**: build the
`JobNextPrevious` query with an `EXISTS (SELECT 1 FROM job_settings ...)` clause
per isolation key folded into the `allofjobs` CTE, instead of wrapping the view
with an outer `id IN` filter. Keep the static view for the generalized default.
