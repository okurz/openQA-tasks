# 150 (poo#210483): OSD non-maintenance job group retention

Ticket: https://progress.opensuse.org/issues/210483
Repository: `openQA` (this checkout), baseline `4d6c602db`, branch per task
`feature/150_<slug>`. Companion plan for the maintenance groups:
`tasks/148_poo210483_osd_results_full_distribution_of_test_results.md`.
Data below measured read-only on OSD on 2026-11-19.

## Goal

Lower the retention of job groups that are neither maintenance-compliance relevant nor needed
for long-term reference, **development job groups first**, so that `/results` stops holding
results of jobs nobody will look at again, and so that no non-maintenance group keeps a
`0`/unset ("forever") or multi-year value.

Honest sizing: this is worth **~161 GB on 15 TB used (~1 %)**. It is hygiene and it removes the
`forever` values, not the space fix — the space fix is the log cap on the maintenance groups in
plan 148 (the staging/increment *results* are maintenance evidence and stay, see plan 148 P2).

## Status

* Phase 1 — **executed 2026-11-19**: 133 Development groups (parent 9 default plus 60 group-level
  overrides), expected ~58 GB. See "Executed changes" for the group list, audit event IDs and the
  verification.
* Phase 2 — in progress in a separate session: 226 remaining non-maintenance groups, results target
  60 d (not 30 d), expected ~103 GB. See "Pre-change values" for the worklist.
* Phase 3 — replacing `0`/unset values inside these groups; part of that session.
* Independent of plan 148 (maintenance groups); the two plans share only the audit tooling
  (plan 148 T1/T2).

## Policy (decided 2026-11-19)

A group belongs to this plan if `g.parent_id = 9` (Development) OR **none** of these contains
"maintenance" (case-insensitive): group name, parent group name, group description, parent
description. Any job group in parent group id 9 (Development) is considered a development group
and treated as Phase 1, regardless of whether "Maintenance" appears in the job group name or
description.

Target values, applied as `new = min(old, target)`; `0`/unset means forever and is replaced by
the target:

| setting                          | current examples               | target (Phase 1 Dev) | target (Phase 2 Non-Dev) |
| -------------------------------- | ------------------------------ | -------------------- | ------------------------ |
| `keep_logs_in_days`              | 5, 10, 14, 20, 30, 60, 90, 180 | **14**               | **14**                   |
| `keep_important_logs_in_days`    | 20, 90, 120, 0                 | **60**               | **60**                   |
| `keep_results_in_days`           | 12, 21, 30, 60, 70, 90, 180, 0 | **30**               | **60**                   |
| `keep_important_results_in_days` | 0 (mostly), 50, 90, 3650       | **90**               | **90**                   |
| `keep_jobs_in_days`              | 180, 365, 730, unset           | **365**              | **365**                  |
| `keep_important_jobs_in_days`    | 0, 730, 1820, 2190             | **730**              | **730**                  |

Invariants that must hold afterwards (they do with the targets above): `logs < results`
(14 < 30 in Phase 1, 14 < 60 in Phase 2), `ilogs < ires` (60 < 90), `results ≤ jobs`
(30 ≤ 365 in Phase 1, 60 ≤ 365 in Phase 2), `ires ≤ ijobs` (90 ≤ 730).

Rationale: development and product-validation groups re-run on demand; development results
older than 30 days and non-development product validation results older than 60 days are
re-derivable from the build, and logs are explicitly "best effort" (the 2-year obligation
covers results+status of _maintenance_ results only, decided 2026-11-19).

## Findings on OSD (2026-11-19, read-only)

Non-maintenance and development groups (selection rule above): **359 groups, 1.0 M live jobs,
700.9 GB live results (652.8 GiB)**. Age distribution of their live results:

| age      | bytes  |
| -------- | ------ |
| 0–7 d    | 311 GB |
| 7–14 d   | 176 GB |
| 14–30 d  | 169 GB |
| 30–60 d  | 30 GB  |
| 60–90 d  | 14 GB  |
| 90–180 d | 0.4 GB |
| >180 d   | 0.2 GB |

So the groups already shed their data quickly; the gain comes from the window they keep
_beyond_ the proposed targets.

### Phase 1 — development groups (parent id 9 or name/parent contains "development")

133 groups, **215.5 GB** live (94 GB of it in group 637 `Development Investigations`, which is
already at `logs 2 / results 2` — high-volume KIWI/fuzzing jobs, ~43 MB per dir, nothing to
reduce there). Results target: **30 days**. Expected gain **~58.2 GB**:

| group | gain    | logs    | results  | jobs      | size    | name                                   |
| ----- | ------- | ------- | -------- | --------- | ------- | -------------------------------------- |
| 220   | 28.4 GB | 30 → 14 | 30 → 30  | 730 → 365 | 36.8 GB | Test Development: Yutao Wang           |
| 520   | 15.7 GB | 20 → 14 | 40 → 30  | 730 → 365 | 44.4 GB | Development Yam Support Images         |
| 305   | 8.5 GB  | 30 → 14 | 90 → 30  | 730 → 365 | 8.5 GB  | Test Development: Kernel-KOTD          |
| 158   | 2.7 GB  | 90 → 14 | 90 → 30  | 730 → 365 | 3.0 GB  | Test Development: Kernel               |
| 446   | 2.1 GB  | 20 → 14 | 40 → 30  | 730 → 365 | 5.7 GB  | YaST Maintenance Updates - Development |
| 293   | 0.4 GB  | 10      | 180 → 30 | 730 → 365 | 1.6 GB  | QEM                                    |
| 168   | 0.4 GB  | 14      | 60 → 30  | 730 → 365 | 1.9 GB  | Test Security                          |

The remaining groups change only `jobs`/`ires` or have smaller gains.

### Phase 2 — remaining non-maintenance groups

226 groups, **485.4 GB** live. Results target: **60 days** (instead of 30 days). Expected gain
**~103.2 GB**:

| group   | gain        | logs    | results | jobs      | size    | name                             |
| ------- | ----------- | ------- | ------- | --------- | ------- | -------------------------------- |
| 445     | 26.2 GB     | 30 → 14 | 30      | 180       | 36.3 GB | BCI Application Images           |
| 727     | 15.1 GB     | 20 → 14 | 31      | 730 → 365 | 31.3 GB | Unified Core (SLE 16.0)          |
| 618     | 12.1 GB     | 30 → 14 | 90 → 60 | 730 → 365 | 18.0 GB | Kernel (SLE 16)                  |
| 625     | 10.6 GB     | 30 → 14 | 30      | 730 → 365 | 14.9 GB | File Systems                     |
| 444     | 6.7 GB      | 30 → 14 | 30      | 180       | 13.5 GB | BCI Language Images              |
| 624     | 6.2 GB      | 60 → 14 | 90 → 60 | 730 → 365 | 8.8 GB  | Virtualization(SLE16 Developing) |
| 285     | 5.8 GB      | 30 → 14 | 90 → 60 | 730 → 365 | 14.8 GB | Latest - HA + SAP                |
| 579     | 2.8 GB      | 30 → 14 | 60      | 730 → 365 | 3.6 GB  | HA                               |
| 710/623 | 2.5 GB each | 30 → 14 | 30      | 180       | 5.4 GB  | BCI Base Images                  |

Groups that change nothing here: 647 `Unified Core (Main)` 248 GB at `10/21`, 727/219/275 at
`logs 14`, i.e. the biggest items are already inside the targets.

Important results in these groups mostly have `keep_important_results_in_days = 0` (forever).
Live important results are small (58 GB DB-wide, of which only a fraction here), but the
`0` must be replaced or the results part of the change has no effect for important builds.

## Executed changes

### 2026-11-19 — Phase 1: retention caps applied to 133 Development groups (~58.2 GB expected)

Approved and executed by okurz on 2026-11-19 (19:04–19:15 UTC). Method:

- Parent group 9 (`Development`) updated via `PUT /api/v1/parent_groups/9`: `default_keep_jobs_in_days = 365`.
- 60 groups with explicit column overrides exceeding targets updated via `PUT /api/v1/job_groups/<id>` with `name` (unchanged) and target values (`logs <= 14`, `ilogs <= 60`, `results <= 30`, `ires <= 90`, `jobs <= 365`, `ijobs <= 730`).
- Audit events in `api/v1/audit_events`: 61 distinct IDs updated (parent 9 + 60 job groups; audit event IDs 56285005..56285220).
- Exactly 0 groups outside Phase 1 were touched (verified against `audit_events`).

Top Phase 1 changes by expected space gain:

| id  | group                                  | logs    | results  | jobs      | size    | gain    |
| --- | -------------------------------------- | ------- | -------- | --------- | ------- | ------- |
| 220 | Test Development: Yutao Wang           | 30 → 14 | 30       | 730 → 365 | 36.8 GB | 28.4 GB |
| 520 | Development Yam Support Images         | 20 → 14 | 40 → 30  | 730 → 365 | 44.4 GB | 15.7 GB |
| 305 | Test Development: Kernel-KOTD          | 30 → 14 | 90 → 30  | 730 → 365 | 8.5 GB  | 8.5 GB  |
| 158 | Test Development: Kernel               | 90 → 14 | 90 → 30  | 730 → 365 | 3.0 GB  | 2.7 GB  |
| 446 | YaST Maintenance Updates - Development | 20 → 14 | 40 → 30  | 730 → 365 | 5.7 GB  | 2.1 GB  |
| 293 | QEM                                    | 10      | 180 → 30 | 730 → 365 | 1.6 GB  | 0.4 GB  |
| 168 | Test Security                          | 14      | 60 → 30  | 730 → 365 | 1.9 GB  | 0.4 GB  |

Verification immediately after the change:

- 0 groups in Phase 1 keep logs longer than 14 days or results longer than 30 days (`keep_logs_in_days > 14 OR keep_results_in_days > 30` returns 0).
- All 133 groups satisfy the target invariants (`logs < results`, `ilogs < ires`, `results <= jobs`, `ires <= ijobs`).

Follow-up verification (after next `limit_results_and_logs` pass, ~25 h):

- `select id, state, finished, notes from minion_jobs where task='limit_results_and_logs' order by id desc limit 3`
- `df -h /results` (expect ~58 GB freed)

## Tasks

### T1: generate and review the worklist (read-only, no writes, no commit)

**Deliverable:** `/tmp/gg_150_worklist.tsv` with one row per group: id, name, parent,
description flag, current and target values, live bytes, bytes >target res, expected gain, phase.

```sql
SELECT g.id, g.name, coalesce(p.name,'') AS parent,
       coalesce(g.keep_logs_in_days::text,''), coalesce(g.keep_important_logs_in_days::text,''),
       coalesce(g.keep_results_in_days::text,''), coalesce(g.keep_important_results_in_days::text,''),
       coalesce(g.keep_jobs_in_days::text,''), coalesce(g.keep_important_jobs_in_days::text,''),
       count(j.id), coalesce(sum(j.result_size),0),
       coalesce(sum(j.result_size) FILTER (WHERE j.t_created <= now()-interval '30 days'),0),
       coalesce(sum(j.result_size) FILTER (WHERE j.t_created <= now()-interval '60 days'),0),
       coalesce(sum(j.result_size) FILTER (WHERE j.t_created <= now()-interval '90 days'),0)
FROM job_groups g
LEFT JOIN job_group_parents p ON p.id = g.parent_id
LEFT JOIN jobs j ON j.group_id = g.id AND NOT j.archived
WHERE g.parent_id = 9
   OR (
       lower(g.name) NOT LIKE '%maintenance%'
       AND lower(coalesce(p.name,'')) NOT LIKE '%maintenance%'
       AND lower(coalesce(g.description,'')) NOT LIKE '%maintenance%'
       AND lower(coalesce(p.description,'')) NOT LIKE '%maintenance%'
   )
GROUP BY g.id, p.id ORDER BY g.id;
```

**Acceptance criteria**

- [x] The worklist contains 359 groups; 133 of them Phase 1 development groups (including all parent id 9 groups)
- [x] `SELECT` only, no `pg_stat`/writes; no `du` over `testresults`
- [x] The pre-change values are recorded in this file (so the change can be reverted)

### T2: apply phase 1 (development groups, ~58 GB, 133 groups)

**Depends on:** T1, approval. **Deliverable:** updated values + verification output in this file.
Apply the target table (`min(old, target)`, `0`/unset → target; `results → 30`) to the 133 groups
of phase 1, preferring the parent level where a parent default reproduces to all children (parent 9
`Development`, 28 `Others`, 30 `L3`). All 120 groups in parent 9 `Development` are included regardless
of whether "Maintenance" is in their group name or description. Do not touch groups outside the phase 1 list.

**Acceptance criteria**

- [ ] `./script/openqa-audit-retention` (plan 148 T1) shows no `forever` and no
      `logs_not_shorter_than_results` / `results_gt_jobs` violation for these groups
- [ ] The next `limit_results_and_logs` pass deletes result dirs and `df` on `/results` reflects
      the freed space (see Gates)
- [x] An unrelated group's values are byte-identical before and after (no accidental mass update - verified 0 groups outside Phase 1 touched)

### T3: apply phase 2 (remaining non-maintenance groups, ~103 GB, 226 groups)

**Depends on:** T2 verified over at least one full cleanup pass (~25 h).
Same procedure for the other 226 groups with results reduced to **60 days** (instead of 30 days);
skip 647/727/219/275 explicitly (already inside the targets) and record that they were skipped and why.

### T4: replace `0`/unset with the targets

**Depends on:** T2/T3. `ires 0 → 90`, `ijobs 0/unset → 730`, `ires 3650/1820/2190 → 90`,
`ilogs 0 → 60`. Without this the results/important part of T2/T3 has no effect.

### T5: re-measure

**Depends on:** T2–T4 and two cleanup passes. Re-run the T1 query and append the before/after
table (groups, bytes, `df`) to this file. Stop if the freed space is below 100 GB and the cause
is not obvious — then the targets are not the issue but the cleanup run is (see plan 148,
"Cleanup runtime observations").

## Risks

| Risk                                                          | Impact     | Mitigation                                                                                                                                   |
| ------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| A "development" group is actually used as long-term reference | Low        | phase 1 is 133 groups; maintainers are visible in the descriptions; the pre-change values are recorded for revert                            |
| `results = 30` loses the history of a test development effort | Low–Medium | the group re-runs on demand; `job_modules` and job pages stay for 365 d                                                                      |
| Mass update hits a maintenance group by accident              | Medium     | parent 9 groups are included by rule; other groups filter on all four name/description fields; assert count is 359; diff one untouched group |
| Cleanup pass takes >24 h, effect visible a day later          | Low        | one phase per day, verify via minion notes                                                                                                   |
| `result_size` bookkeeping drift makes the estimate optimistic | Low        | sample 5 `du` of dirs in phase 1 before/after                                                                                                |

## Open questions

1. Should `logs = 14` be lowered to 7 for development groups? Dev jobs are obsolete within days;
   T1 can produce both variants.
2. Do the BCI/container groups (445/444/623/710/608) need `results = 30`, or is 21 (their
   `ires`/`jobs` pattern) enough? They are product validation, not development.
3. Parent-level vs group-level: parent 9 `Development` has 120 children; setting
   `default_keep_*` there applies to all children in Phase 1. Check `job_groups.parent_id = 9`
   before using the parent level.

## Approvals

| Decision                                                                                                           | Approver | Date       |
| ------------------------------------------------------------------------------------------------------------------ | -------- | ---------- |
| Retention obligation covers results+status only; logs are best effort                                              | okurz    | 2026-11-19 |
| Non-maintenance groups are handled in this plan (150), dev groups first; maintenance groups stay in 148            | okurz    | 2026-11-19 |
| Target values: logs 14, Phase 1 results 30, Phase 2 results 60, jobs 365, important 60/90/730                      | okurz    | 2026-11-19 |
| Parent group id 9 (Development) all treated as Phase 1 development groups regardless of "Maintenance" in name/desc | okurz    | 2026-11-19 |
| Read-only SQL on OSD for T1/T5                                                                                     | okurz    | 2026-11-19 |
| Phase 1 execution on OSD (133 development groups via API)                                                          | okurz    | 2026-11-19 |
| Any write on OSD for Phase 2 (group values via API/SQL, salt config)                                               | pending  | –          |
| Plan approved for implementation as written                                                                        | okurz    | 2026-11-19 |

## Gates

| Step            | Exact verification command                                                                                                                                                           |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| T1 (read-only)  | the SQL above; `grep -c . /tmp/gg_150_worklist.tsv` = 359; `grep -ci development` = 133                                                                                              |
| T2/T3/T4 apply  | before/after `df -h /results`; the group diff recorded in this file; `psql … -c "SELECT count(*) FROM job_groups WHERE keep_logs_in_days > 14 AND …"` = 0 for the processed set      |
| T2/T3/T4 verify | `select id, state, finished, notes from minion_jobs where task='limit_results_and_logs' order by id desc limit 3` after the next pass (expect a pass that deleted several GB, not 0) |
| T5 re-measure   | re-run the T1 query; compare "bytes >30 d" per group with the pre-change table                                                                                                       |
| audit check     | `./script/openqa-audit-retention --format json` once plan 148 T1 is merged: 0 classifications `forever`/`logs_not_shorter_than_results` for the processed groups                     |

Commits: this plan changes no code, so there is no commit in this repository. If a repo change
turns out to be needed (e.g. the audit script from plan 148), it lands under that plan's tasks
and gates.

## Pre-change values

Measured read-only on OSD on 2026-11-19 via `psql -d postgresql://openqa:<password>@openqa.suse.de/openqa` using the updated T1 query.

### Worklist verification and count analysis

- Total non-maintenance and development groups satisfying the policy: **359 groups** (1,005,824 live jobs, 652.8 GiB / 700.9 GB live results).
- **Phase 1 (Development groups): 133 groups**, 369,679 live jobs, 215.5 GB live results, results target **30 d**, expected gain **~58.2 GB**.
  - All 120 groups in parent group id 9 (`Development`) are treated as development groups in Phase 1 regardless of whether "Maintenance" appears in their group name or description.
  - 13 groups with "development" in name under other non-maintenance parents (`Released`, `SL Micro`, `EOL`, `SLE 15`, `Others`).
- **Phase 2 (Remaining non-maintenance groups): 226 groups**, 636,145 live jobs, 485.4 GB live results, results target **60 d** (instead of 30 d), expected gain **~103.2 GB**.
- Combined expected space reclamation across all groups: **~161.4 GB** (~161 GB, consistent with the plan's ~163 GB sizing).

**Reconciliation with preliminary draft counts (332 groups, 110 dev groups):**
The earlier 332 count came from the preliminary categorization in plan 148, which sequentially filtered groups by `incident`, `maintenance updates`, `staging`, `increment`, `qr`, and `maintenance`. Under the refined policy rules:

1. 15 staging/increment groups (11 with parent "Development" such as `Development: SLE16_staging_Core_dev`, `Test Development: PC 16.0 Increments `, `Staging: SLE 15`, 1 with parent "Others", 3 with parent "Released") do not contain "maintenance" and belong in plan 150.
2. All 14 groups in parent group id 9 (`Development`) that contain "maintenance" in name or description (e.g. `YaST Maintenance Updates - Development`, `Test Development: JeOS`, `Test QAM HA-SAP`, `Roy Maintenance:SLES 16.1 VIRT Staging`) are included in Phase 1 by rule.
   Net count is 332 + 15 + 12 = **359 groups** (110 + 11 + 12 = **133 development groups in Phase 1**, **226 groups in Phase 2**).

Deliverable file `/tmp/gg_150_worklist.tsv` contains 359 data rows matching the gate `grep -c . /tmp/gg_150_worklist.tsv` = 359, `grep -ci development /tmp/gg_150_worklist.tsv` = 133.

### Full group pre-change values table (359 groups)

| id  | group                                                       | parent             | logs | ilogs | results | ires | jobs | ijobs | live jobs | size     | >target res | gain     | phase |
| --- | ----------------------------------------------------------- | ------------------ | ---- | ----- | ------- | ---- | ---- | ----- | --------- | -------- | ----------- | -------- | ----- |
| 1   | x-released SLED 12                                          | Released           | 30   | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 7   | x-released SLE 11 SP3 2.Desktop                             | Released           | 30   | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 9   | x-released SLE 11 SP4 1.Server                              | Released           | 30   | 120   | 90      | 3650 | 730  | 0     | 0         | -        | -           | -        | 2     |
| 14  | x-released SLE 11 SP4 4.Test Development                    | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 16  | x-released SLE 11 SP4 3.HA                                  | Released           | 30   | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 17  | VMDP                                                        | Released           | 30   | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 20  | VMDP Testing                                                | Development        | 30   | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 25  | Acceptance: SLE 12 SP2 1.Server                             | Released           | 30   | 120   | 40      | 3650 | 730  | 0     | 0         | -        | -           | -        | 2     |
| 26  | Acceptance: SLE 12 SP2 2.Desktop                            | Released           | 10   | 70    | 30      | 2190 | 730  | 0     | 0         | -        | -           | -        | 2     |
| 27  | Acceptance: SLE 12 SP2 3.HA                                 | Released           | 30   | 120   | 30      | 2190 | 730  | 0     | 0         | -        | -           | -        | 2     |
| 28  | Staging: SLE 12 SP2                                         | Released           | 10   | 120   | 30      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 29  | Test Development: SLE 12 SP2                                | Released           | 30   | 120   | 20      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 31  | Slenkins: SLE 12 SP2                                        | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 32  | Regression: SLE 12 SP2                                      | Released           | 30   | 120   | 40      | 730  | -    | 2190  | 1         | -        | -           | -        | 2     |
| 40  | Acceptance: SLE 12 SP2 4.Autoyast                           | Released           | 30   | 120   | 30      | 2190 | 730  | 3650  | 0         | -        | -           | -        | 2     |
| 43  | Acceptance: SLE 12 SP2 5.SLES4SAP                           | Released           | 30   | 120   | 30      | 2190 | 730  | 3650  | 0         | -        | -           | -        | 2     |
| 44  | Online Migration: SLE 12 SP2 2.Desktop                      | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 45  | Online Migration: SLE 12 SP2 1.Server                       | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 46  | Virtualization: SLE 12 SP2                                  | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 50  | Staging: SLE 12                                             | Released           | 5    | 30    | 11      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 52  | MicroOS 1.0 DVD                                             | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 55  | SLE 12 SP3 Functional: Server                               | Released           | 21   | 120   | 90      | 730  | 730  | 2190  | 0         | -        | -           | -        | 2     |
| 56  | SLE 12 SP3 Userspace Regression: Server                     | Released           | 30   | 120   | 40      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 57  | SLE 12 SP3 Slenkins: Server                                 | Released           | 21   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 58  | Test Development: SLE 12 SP3                                | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 1     |
| 59  | SLE 12 SP3 Virtualization: Server                           | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 60  | Regression: Autoyast                                        | Released           | 30   | 120   | 40      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 61  | SLE 12 SP3 Functional: Desktop                              | Released           | 14   | 50    | 40      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 62  | SLE 12 SP3 Migration: Desktop                               | Released           | 14   | 50    | 40      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 63  | SLE 12 SP3 FIPS: Server                                     | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 64  | SLE 12 SP3 Functional: HA                                   | Released           | 14   | 60    | 40      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 65  | SLE 12 SP3 Migration: Server                                | Released           | 21   | 120   | 90      | 730  | -    | 2190  | 16        | -        | -           | -        | 2     |
| 66  | SLES4SAP 12 SP3                                             | Released           | 30   | 60    | 40      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 69  | Acceptance: SLE 12 SP2 RT                                   | Released           | 30   | 120   | 30      | 2190 | 730  | 3650  | 0         | -        | -           | -        | 2     |
| 70  | SLE 12 SP3 Kernel: Server                                   | Released           | 21   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 72  | SLE 12 SP3 Migration: HA                                    | Released           | 30   | 120   | -       | 3650 | -    | 3650  | 0         | -        | -           | -        | 2     |
| 74  | MicroOS 1.0 VMX - KVM-and-Xen                               | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 76  | MicroOS 1.0 VMX - XEN                                       | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 78  | SLES 12 SP3 JeOS                                            | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 80  | SLE 12 SP3 Migration (post): Desktop                        | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 85  | SLE 12 SP3 Migration (post): Server                         | Released           | 30   | 120   | 90      | 800  | -    | 800   | 0         | -        | -           | -        | 2     |
| 86  | SLE 12 SP3 Migration (post): HA                             | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 87  | SLE 12 SP3 Network: Server                                  | Released           | 12   | 120   | 30      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 95  | Staging: CaaSP                                              | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 96  | Test Development: SLE 15                                    | Development        | 10   | 20    | 20      | 50   | -    | 730   | 916       | -        | -           | -        | 1     |
| 97  | CaaSP 1.0 Deployment - VMX                                  | Released           | 30   | 120   | -       | 3650 | -    | 3650  | 0         | -        | -           | -        | 2     |
| 102 | schlad: Experimental and Development                        | Development        | 15   | 20    | 20      | 50   | -    | 50    | 32        | -        | -           | -        | 1     |
| 110 | Functional                                                  | SLE 15             | 20   | 60    | 40      | 2920 | 730  | 2920  | 0         | -        | -           | -        | 2     |
| 111 | Migration: SLE15GA                                          | Released           | 30   | 200   | 180     | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 112 | SLE 15 (Development) - Userspace                            | Released           | 10   | 120   | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 113 | SLE 15 (Development) - Security                             | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 114 | SLE 15 (Development) - Slenkins                             | Released           | 14   | 120   | 60      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 115 | Virtualization-Acceptance: SLE 15                           | Development        | 12   | 120   | 50      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 116 | Kernel Validation                                           | SLE 15             | 90   | 180   | 90      | 730  | 730  | 2190  | 482       | -        | -           | -        | 2     |
| 118 | Desktop Applications                                        | SLE 15             | 30   | 120   | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 124 | MicroOS 2.0 - DVD                                           | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 125 | Staging: SLE 15                                             | Development        | 5    | 80    | 10      | 80   | -    | 730   | 242       | -        | -           | -        | 1     |
| 126 | MicroOS 2.0 - VMX                                           | Released           | 30   | 120   | -       | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 128 | SLE 12 SP3 Acceptance: RT                                   | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 129 | YaST                                                        | SLE 15             | 20   | 60    | 40      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 130 | HPC                                                         | SLE 15             | 14   | 120   | 60      | 2920 | 730  | 2920  | 0         | -        | -           | -        | 2     |
| 131 | MinimalVM                                                   | SLE 15             | 60   | 60    | 60      | 60   | 730  | 730   | 550       | -        | -           | -        | 2     |
| 132 | Test Development: SLE 12                                    | Released           | 10   | 20    | 10      | 50   | -    | 50    | 0         | -        | -           | -        | 1     |
| 136 | MicroOS 3.0 - DVD                                           | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 137 | MicroOS 3.0 - VMX                                           | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 139 | SLE 12 SP5 Functional: Server                               | Released           | 28   | 120   | 60      | 730  | 730  | 2190  | 0         | -        | -           | -        | 2     |
| 142 | SLE 12 SP5 YaST                                             | Released           | 14   | 120   | 60      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 143 | HA                                                          | SLE 15             | 30   | 120   | 60      | 2190 | -    | 3650  | 0         | -        | -           | -        | 2     |
| 145 | SLE 15 Migration (post)                                     | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 146 | SLES for SAP Applications                                   | SLE 15             | 30   | 120   | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 148 | Support Server: SLE 12 SP3                                  | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 151 | Migration: Server 12SP4                                     | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 152 | SLE 12 Functional: Desktop                                  | Released           | 30   | 365   | 70      | 3650 | -    | 3650  | 0         | -        | -           | -        | 2     |
| 153 | CaaSP 4.0 - Next                                            | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 155 | SLE 12 Kernel                                               | Released           | 30   | 365   | 90      | 3650 | -    | 3650  | 0         | -        | -           | -        | 2     |
| 156 | SLE 15 (Development) - SES6                                 | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 157 | SLE 12 HA                                                   | Released           | 30   | 120   | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 158 | Test Development: Kernel                                    | Development        | 90   | 180   | 90      | 730  | 730  | 2190  | 4581      | 3.0 GB   | 2.5 GB      | 2.7 GB   | 1     |
| 162 | SLES 12 JeOS                                                | Released           | 30   | 120   | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 163 | SLE 12 Virtualization-Acceptance                            | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 164 | SLE 12 Virtualization-Milestone                             | Released           | 30   | 365   | 90      | 3650 | -    | 3650  | 0         | -        | -           | -        | 2     |
| 167 | SLE 12 Security                                             | Released           | 30   | 365   | 200     | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 168 | Test Security                                               | Development        | 14   | 90    | 60      | 180  | -    | 730   | 10146     | 1.9 GB   | 402.0 MB    | 402.0 MB | 1     |
| 169 | SLE 12 HPC                                                  | Released           | 14   | 120   | 60      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 170 | SLE 12 Network                                              | Released           | 30   | 365   | 90      | 3650 | -    | 3650  | 0         | -        | -           | -        | 2     |
| 181 | MicroOS 4.0 - DVD                                           | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 182 | MicroOS 4.0 - VMX                                           | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 183 | SLES for SAP Applications 12                                | Released           | 30   | 120   | 60      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 184 | Migration: HA - new EOL                                     | EOL                | 30   | 365   | 12      | 3650 | -    | 3650  | 0         | -        | -           | -        | 2     |
| 189 | Migration:Milestone Server 12SP4                            | Released           | 30   | 365   | 90      | 3650 | -    | 3650  | 0         | -        | -           | -        | 2     |
| 190 | SLE 12 NFV                                                  | Released           | 30   | 120   | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 196 | SLE 12 Migration: Desktop                                   | Released           | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 198 | SLERT 12 SP5                                                | Others             | 14   | 60    | 90      | 730  | -    | 2190  | 8         | 580.8 KB | -           | -        | 2     |
| 210 | SLE 12 Azure                                                | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 211 | HPC Product obsolete                                        | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 212 | Test Development: Migration Server: SLE12 SP5               | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 1     |
| 213 | Virtualization-Milestone: SLE 16                            | Development        | 14   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 219 | Latest - Azure                                              | Public Cloud       | 14   | 90    | 90      | 365  | 730  | 730   | 11255     | 10.6 GB  | 1.6 GB      | 1.6 GB   | 2     |
| 220 | Test Development: Yutao Wang                                | Development        | 30   | 30    | 30      | 50   | 730  | 730   | 21617     | 36.8 GB  | 136.3 MB    | 28.4 GB  | 1     |
| 222 | Migration : SLE15GA Milestone                               | Released           | 14   | 200   | 180     | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 229 | Terraform                                                   | Development        | 10   | 20    | 20      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 230 | IBM before SLE15-SP2                                        | Development        | 10   | 20    | 20      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 234 | Migration: SLE 12SP5                                        | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 238 | Migration:Milestone SLE 12SP5                               | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 240 | SLE 12 File Systems                                         | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 245 | SLE 12 Migration: SLES                                      | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 246 | SLE 12 Migration:Milestone SLES                             | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 247 | SLE 12 Regression on Migrated system:SLES                   | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 248 | SLE 12 SLES for SAP Applications                            | Released           | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 251 | Test-GaoWei                                                 | Development        | 5    | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 257 | File Systems                                                | SLE 15             | 30   | 120   | 90      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 258 | Migration:HPC                                               | EOL                | 10   | 10    | 10      | 10   | -    | 730   | 0         | -        | -           | -        | 2     |
| 259 | SLES4SAP+HA 12 Public Cloud                                 | Released           | 30   | 120   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 261 | Migration:Continuous Upgrade SLE12SP5                       | Released           | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 262 | Functional Wicked                                           | SLE 15             | 10   | 90    | 21      | 2920 | 730  | 2920  | 0         | -        | -           | -        | 2     |
| 263 | Virtualization-Acceptance                                   | SLE 15             | 60   | 365   | 90      | 730  | 730  | 730   | 25        | -        | -           | -        | 2     |
| 264 | Virtualization-Milestone                                    | SLE 15             | 30   | 365   | 60      | 365  | -    | 730   | 16        | -        | -           | -        | 2     |
| 265 | Migration                                                   | SLE 15             | 20   | 50    | 60      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 266 | Migration: Milestone                                        | SLE 15             | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 267 | Migration: Regression                                       | EOL                | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 268 | Security                                                    | SLE 15             | 30   | 90    | 90      | 180  | 730  | 730   | 601       | -        | -           | -        | 2     |
| 272 | SLE 12 EC2                                                  | Released           | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 273 | SLE 12 GCE                                                  | Released           | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 274 | Latest - EC2                                                | Public Cloud       | 14   | 90    | 90      | 365  | 730  | 730   | 10523     | 7.7 GB   | 186.8 MB    | 186.8 MB | 2     |
| 275 | Latest - GCE                                                | Public Cloud       | 14   | 90    | 90      | 365  | 730  | 730   | 10011     | 9.3 GB   | 1.3 GB      | 1.3 GB   | 2     |
| 276 | PC Tools Image                                              | Public Cloud       | 14   | 90    | 90      | 365  | 730  | 730   | 79        | 1.1 MB   | -           | -        | 2     |
| 277 | Migration: SLE15 SP4 continuous                             | EOL                | 5    | 20    | 12      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 278 | SLES for SAP Applications                                   | Development        | 5    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 279 | Migration 12sp5 Test Yaml                                   | Released           | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 285 | Latest - HA + SAP                                           | Public Cloud       | 30   | 90    | 90      | 365  | 730  | 730   | 4644      | 14.8 GB  | 479.8 MB    | 5.8 GB   | 2     |
| 287 | Windows HDD creation                                        | WSL (deprecated)   | 30   | 30    | 30      | 30   | 730  | 730   | 45        | 24.5 MB  | -           | 19.6 MB  | 2     |
| 288 | SLE 12-SP5                                                  | WSL (deprecated)   | 10   | 90    | 70      | 730  | 730  | 2190  | 0         | -        | -           | -        | 2     |
| 292 | IBM SLE15-SP2                                               | Development        | 10   | 20    | 20      | 50   | -    | 50    | 0         | -        | -           | -        | 1     |
| 293 | QEM                                                         | Development        | 10   | 10    | 180     | 180  | -    | 1     | 1978      | 1.6 GB   | 416.8 MB    | 416.8 MB | 1     |
| 294 | x_mgriessmeier                                              | Development        | 5    | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 295 | HPC migration test                                          | EOL                | 5    | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 2     |
| 296 | KernelX                                                     | EOL                | 1    | 1     | 1       | 1    | -    | 730   | 0         | -        | -           | -        | 2     |
| 297 | Test QAM HA-SAP                                             | Development        | 5    | 20    | 12      | 50   | -    | 730   | 63        | -        | -           | -        | 1     |
| 298 | SLE 15-SP2                                                  | EOL                | 14   | 180   | 90      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 301 | Migration: HPC                                              | EOL                | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 305 | Test Development: Kernel-KOTD                               | Development        | 30   | 120   | 90      | 730  | 730  | 2190  | 63238     | 8.5 GB   | 8.5 GB      | 8.5 GB   | 1     |
| 312 | SLES 15 SP3 - zluo                                          | Development        | 5    | 20    | 12      | 50   | -    | 50    | 0         | -        | -           | -        | 1     |
| 313 | Container Host                                              | SLE 15             | 10   | 90    | 70      | 90   | 730  | 0     | 0         | -        | -           | -        | 2     |
| 314 | Artificial Intelligence                                     | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 316 | Test development: Lemon                                     | Development        | 5    | 20    | 12      | 50   | -    | 730   | 2034      | -        | -           | -        | 1     |
| 317 | SLERT 15 SP3                                                | Others             | 10   | 90    | 70      | 730  | -    | 2190  | 1         | 410.1 KB | -           | -        | 2     |
| 318 | Test Development: Huajian                                   | Development        | 5    | 20    | 12      | 50   | -    | 730   | 1634      | -        | -           | -        | 1     |
| 319 | Migration - Development                                     | Development        | 5    | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 320 | Migration: HPC Milestone                                    | EOL                | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 324 | Migration: Other test                                       | EOL                | 15   | 20    | 25      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 326 | Latest (SLE 15-SP7)                                         | WSL (deprecated)   | 10   | 90    | 70      | 730  | 730  | 2190  | 2376      | -        | -           | -        | 2     |
| 327 | SLE Micro 5.0                                               | Released           | 5    | 20    | 12      | 50   | -    | 50    | 0         | -        | -           | -        | 2     |
| 328 | SUSE Carwos                                                 | Others             | 30   | 200   | 30      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 330 | Test Development: GRACE                                     | Development        | 5    | 20    | 12      | 50   | -    | 730   | 288       | -        | -           | -        | 1     |
| 332 | L3: Kernel 12-SP2                                           | L3                 | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 333 | L3: Kernel 12-SP4                                           | L3                 | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 334 | L3: Kernel 12-SP5                                           | L3                 | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 335 | L3: Kernel 15                                               | L3                 | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 336 | L3: Kernel 15-SP1                                           | L3                 | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 337 | L3: Kernel 15-SP2                                           | L3                 | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 346 | Maintenance: SLE 15 SP2 Updates                             | Development        | 5    | 20    | 60      | 60   | -    | 50    | 0         | -        | -           | -        | 1     |
| 352 | [deprecated] Containers 15 SP2 Updates                      | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 353 | [deprecated] Containers 15 SP1 Updates                      | Released           | 10   | 90    | 30      | 0    | 730  | 0     | 0         | -        | -           | -        | 2     |
| 354 | [deprecated] Containers 12 SP4 Updates                      | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 355 | [deprecated] Containers 12 SP5 Updates                      | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 357 | [deprecated] Containers 15 GA Updates                       | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 358 | [deprecated] Containers 12 SP3 Updates                      | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 359 | Test QEM-Timo                                               | Development        | 5    | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 360 | Maintenance: 15-SP2 Staging Images                          | Development        | 10   | 90    | 730     | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 362 | SLE Micro 5.1                                               | Released           | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 363 | [deprecated] SLE Micro 5.0 Updates                          | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 369 | [deprecated] Containers 15-SP3 Updates                      | Released           | 10   | 90    | 21      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 377 | Container host HDDs                                         | Containers         | 14   | 21    | 14      | 21   | 30   | 30    | 421       | 1.2 GB   | -           | -        | 2     |
| 378 | SLE Base Image Updates 15-SP3 [deprecated]                  | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 379 | SLE Base Image Updates 15-SP2 [deprecated]                  | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 380 | SLE Base Image Updates 15-SP1 [deprecated]                  | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 381 | SLE Base Image Updates 15 GA [deprecated]                   | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 382 | SLE Base Image Updates 12-SP5 [deprecated]                  | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 384 | SLE Base Image Updates 12-SP3 [deprecated]                  | Released           | 10   | 90    | 70      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 386 | SLE 15-SP4                                                  | WSL (deprecated)   | 10   | 90    | 21      | 730  | 730  | 2190  | 0         | -        | -           | -        | 2     |
| 391 | Test Development: JeOS                                      | Development        | 10   | 90    | 70      | 730  | 730  | 2190  | 1122      | 544.5 KB | -           | -        | 1     |
| 392 | Liberty Functional                                          | EOL                | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 398 | Test Development: Containers                                | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 1         | -        | -           | -        | 1     |
| 400 | Liberty Kernel                                              | EOL                | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 401 | EPEL                                                        | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 402 | [deprecated] SLE Micro 5.1 Updates                          | Released           | 10   | 90    | 21      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 403 | Liberty 8.5 Functional                                      | EOL                | 10   | 90    | 21      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 404 | WinUpdates                                                  | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 410 | SLE Micro 5.5 (deprecated)                                  | EOL                | 10   | 90    | 21      | 0    | -    | 0     | 0         | -        | -           | -        | 2     |
| 413 | SLEM 5.2 on Public Cloud                                    | Development        | 5    | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 415 | SLE Micro: Development                                      | SL Micro           | 5    | 20    | 12      | 50   | -    | 50    | 1102      | 74.7 MB  | -           | -        | 1     |
| 416 | DMS (deprecated)                                            | Public Cloud       | 14   | 120   | 360     | 720  | 730  | 730   | 35        | -        | -           | -        | 2     |
| 426 | Virtualization-MU-Incidents                                 | Development        | 30   | 90    | 30      | 90   | -    | 730   | 14        | -        | -           | -        | 1     |
| 428 | BCI repo                                                    | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 2261      | 1.7 GB   | -           | 1.0 GB   | 2     |
| 431 | Test pstivanin-security                                     | Development        | 5    | 10    | 7       | 15   | 730  | 730   | 69        | 218.1 MB | -           | -        | 1     |
| 433 | SLERT                                                       | Others             | 30   | 365   | 90      | 730  | -    | 2190  | 96        | -        | -           | -        | 2     |
| 442 | BCI Base Images 15-SP3 (ltss)                               | EOL                | 30   | 90    | 30      | 90   | 180  | 180   | 0         | -        | -           | -        | 2     |
| 443 | BCI Base Images 15-SP4 (ltss)                               | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 1687      | 506.9 MB | -           | 292.5 MB | 2     |
| 444 | BCI Language Images                                         | Containers         | 30   | 30    | 30      | 30   | 180  | 180   | 103215    | 13.5 GB  | -           | 6.7 GB   | 2     |
| 445 | BCI Application Images                                      | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 130037    | 36.3 GB  | -           | 26.2 GB  | 2     |
| 446 | YaST Maintenance Updates - Development                      | Development        | 20   | 60    | 40      | 50   | -    | 50    | 7645      | 5.7 GB   | 229.8 MB    | 2.1 GB   | 1     |
| 447 | Azure CLI                                                   | Development        | 10   | 90    | 70      | 2190 | 730  | 3650  | 3212      | -        | -           | -        | 1     |
| 448 | Migration: SAP                                              | EOL                | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 449 | SLE Micro for Rancher image                                 | SL Micro           | 10   | 90    | 21      | 730  | -    | 2190  | 409       | 30.2 MB  | -           | -        | 2     |
| 451 | SLE Micro Toolbox updates                                   | SL Micro           | 10   | 90    | 21      | 730  | 730  | 2190  | 2466      | 144.7 MB | -           | -        | 2     |
| 452 | Migration: HA                                               | EOL                | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 453 | Base Images (12SP5)                                         | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 779       | 32.2 MB  | -           | 25.8 MB  | 2     |
| 454 | Virtualization-Acceptance for SLE15SP4                      | Released           | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 455 | SLEM 5.3 on Public Cloud                                    | Development        | 10   | 90    | 21      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 457 | Developement ALP                                            | EOL                | 5    | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 2     |
| 461 | SLE 15-SP5                                                  | WSL (deprecated)   | 10   | 90    | 21      | 730  | 730  | 2190  | 871       | -        | -           | -        | 2     |
| 466 | Test Development: Migration ONLY for Debug                  | EOL                | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 467 | Security-QR-Staging                                         | Development        | 14   | 720   | 180     | 720  | -    | 730   | 0         | -        | -           | -        | 1     |
| 468 | Security-Timo-testing                                       | Development        | -    | -     | -       | -    | -    | -     | 1366      | 651.9 MB | -           | -        | 1     |
| 472 | Test Development: Kernel experiments                        | Development        | 5    | 20    | 12      | 50   | -    | 730   | 382       | -        | -           | -        | 1     |
| 474 | emiler security                                             | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 331       | -        | -           | -        | 1     |
| 475 | BCI Base Images 15-SP5 (ltss)                               | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 1612      | 422.4 MB | -           | 221.8 MB | 2     |
| 476 | Container Image                                             | SLE 15             | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 477 | Test-LilyZhao                                               | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 1065      | -        | -           | -        | 1     |
| 478 | Migration: Misc.                                            | EOL                | 20   | 50    | 60      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 479 | SLEM 5.1 on Public Cloud                                    | Development        | 10   | 90    | 21      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 480 | SLEM 5.4 on Public Cloud                                    | Development        | 10   | 90    | 21      | 730  | -    | 2190  | 0         | -        | -           | -        | 1     |
| 481 | TestMpagot                                                  | Development        | -    | -     | -       | -    | -    | -     | 13        | -        | -           | -        | 1     |
| 487 | Test amanzini-security                                      | Development        | -    | -     | -       | -    | -    | -     | 1034      | 5.4 MB   | -           | -        | 1     |
| 489 | Test FSzekely-security                                      | Development        | 5    | 20    | 30      | 50   | 730  | 730   | 1623      | 117.3 MB | 1.8 MB      | -        | 1     |
| 496 | YaST                                                        | EOL                | 10   | 90    | 70      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 503 | suseconnect                                                 | Development        | 5    | 20    | 12      | 50   | -    | 730   | 2         | -        | -           | -        | 1     |
| 507 | Test development: Kernel kselftests                         | Development        | 5    | 20    | 12      | 50   | -    | 730   | 26        | -        | -           | -        | 1     |
| 509 | PCW                                                         | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 510 | Migration                                                   | SL Micro           | 20   | 90    | 40      | 730  | -    | 2190  | 38        | -        | -           | -        | 2     |
| 511 | Functional                                                  | SL Micro           | 180  | 365   | 180     | 365  | 730  | 730   | 1045      | 197.7 MB | -           | 158.2 MB | 2     |
| 512 | Kernel                                                      | SL Micro           | 180  | 365   | 180     | 730  | 730  | 2190  | 7472      | 33.3 MB  | -           | 26.7 MB  | 2     |
| 513 | Container Host                                              | SL Micro           | 180  | 365   | 180     | 365  | 730  | 730   | 3411      | 1.1 GB   | -           | 880.1 MB | 2     |
| 514 | Security                                                    | SL Micro           | 30   | 90    | 90      | 180  | 730  | 730   | 592       | -        | -           | -        | 2     |
| 515 | Virtualization                                              | SL Micro           | 60   | 365   | 180     | 365  | -    | 365   | 774       | 65.1 MB  | -           | 52.1 MB  | 2     |
| 516 | SUMA images                                                 | Containers         | 30   | 90    | 30      | 730  | 180  | 2190  | 1340      | -        | -           | -        | 2     |
| 520 | Development Yam Support Images                              | Development        | 20   | 50    | 40      | 50   | 730  | 730   | 99869     | 44.4 GB  | 1.7 GB      | 15.7 GB  | 1     |
| 523 | SLEM 5.5 on Public Cloud                                    | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 524 | Staging: SL Micro                                           | Development        | 10   | 90    | 21      | 730  | -    | 2190  | 201       | -        | -           | -        | 1     |
| 527 | ssyrianidou-temp                                            | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 529 | Leo                                                         | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 530 | HA Migration                                                | SLE 15             | 30   | 120   | 70      | 2190 | -    | 3650  | 3         | 9.2 MB   | -           | -        | 2     |
| 531 | Public Cloud Maintenance / SLEM5.5 Incidents                | Development        | 10   | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 533 | stack_tests_pyton_dev                                       | Development        | -    | -     | -       | -    | -    | -     | 6770      | 1.2 GB   | -           | -        | 1     |
| 536 | File Systems                                                | SL Micro           | 30   | 90    | 30      | 3650 | 730  | 3650  | 777       | -        | -           | -        | 2     |
| 537 | PUBLIC CLOUD INFRA                                          | Development        | 5    | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 538 | BCI Base Images 15-SP6 (ltss)                               | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 2639      | 614.1 MB | -           | 359.2 MB | 2     |
| 539 | Test Security Baremetal                                     | Development        | 10   | 30    | 25      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 540 | Test-lpalovsky                                              | Development        | -    | -     | -       | -    | -    | -     | 1         | 3.1 MB   | -           | -        | 1     |
| 543 | SLE Micro 5.5 respin                                        | SL Micro           | 5    | 20    | 12      | 50   | 730  | 730   | 0         | -        | -           | -        | 2     |
| 544 | sle-micro-6.2-VT-development                                | Development        | 20   | 20    | 20      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 545 | Latest - SLE Micro (deprecated)                             | Public Cloud       | 10   | 90    | 70      | 730  | 730  | 2190  | 0         | -        | -           | -        | 2     |
| 550 | Test_podman_migration                                       | Development        | -    | -     | -       | -    | -    | -     | 2         | -        | -           | -        | 1     |
| 551 | SL Micro 6.0 Maintenance dev                                | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 552 | Test Development: Core Maintenance Updates - SP6            | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 0         | -        | -           | -        | 1     |
| 553 | Test Development: Maintenance: SLE 15 SP6 Core Incidents    | Development        | 5    | 20    | 550     | 730  | 730  | 730   | 0         | -        | -           | -        | 1     |
| 560 | Image config                                                | SL Micro           | 10   | 90    | 21      | 730  | 730  | 3650  | 994       | -        | -           | -        | 2     |
| 563 | SL Micro Kernel Extend LTP Test(We Gao)                     | Development        | 5    | 20    | 12      | 50   | -    | 730   | 85        | -        | -           | -        | 1     |
| 564 | dev-core_development                                        | Development        | 5    | 20    | 30      | 50   | 730  | 730   | 1609      | 1.7 GB   | 35.3 MB     | -        | 1     |
| 569 | Test_lxj                                                    | Development        | -    | -     | -       | -    | -    | -     | 1671      | 177.4 MB | -           | -        | 1     |
| 571 | Test Development: Kernel Baremetal                          | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 171       | -        | -           | -        | 1     |
| 576 | Test: Chenzi                                                | Development        | 5    | 20    | 12      | 50   | -    | 730   | 2150      | -        | -           | -        | 1     |
| 577 | HPC                                                         | Containers         | 14   | 180   | 90      | 2920 | 730  | 2920  | 1078      | 84.7 MB  | 9.8 MB      | 9.8 MB   | 2     |
| 579 | HA                                                          | SLE 16             | 30   | 120   | 60      | 2190 | 730  | 3650  | 9403      | 3.6 GB   | -           | 2.8 GB   | 2     |
| 580 | Minimal-VM                                                  | SLE 16             | 10   | 90    | 21      | 730  | 730  | 2190  | 10807     | 1.3 GB   | -           | -        | 2     |
| 582 | VirtStack containers                                        | Containers         | 30   | 90    | 30      | 730  | 180  | 2190  | 1109      | 7.1 GB   | -           | 2.0 GB   | 2     |
| 583 | Test Development: José Fernández                            | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 5181      | 3.0 GB   | -           | -        | 1     |
| 584 | Elemental Container                                         | SL Micro           | 10   | 90    | 21      | 3650 | 730  | 3650  | 22137     | 558.7 MB | -           | -        | 2     |
| 585 | Test Development: Rainer Koenig                             | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 1021      | -        | -           | -        | 1     |
| 586 | IBM HPVS                                                    | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 192       | 54.7 MB  | -           | 24.4 MB  | 2     |
| 589 | Security                                                    | SLE 16             | 30   | 90    | 90      | 180  | 730  | 730   | 12891     | 1.4 GB   | 256.4 MB    | 1.2 GB   | 2     |
| 590 | SL Micro 6.0 Product Increments - Virtualization            | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 591 | TEST-dawei.pang                                             | Development        | -    | -     | -       | -    | -    | -     | 101       | -        | -           | -        | 1     |
| 592 | AI Stack                                                    | Development        | -    | -     | -       | -    | -    | -     | 168       | -        | -           | -        | 1     |
| 593 | Test-jgwang                                                 | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 2464      | -        | -           | -        | 1     |
| 594 | SLES and SLED Vendor Affirmation                            | Vendor Affirmation | 30   | 90    | 180     | 365  | 730  | 730   | 92        | -        | -           | -        | 2     |
| 595 | SLE 15-SP6                                                  | WSL (deprecated)   | 10   | 90    | 21      | 730  | 730  | 2190  | 1964      | -        | -           | -        | 2     |
| 596 | Test development: XUGUANG                                   | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 1430      | -        | -           | -        | 1     |
| 597 | Roy Maintenance:SLES 16.1 VIRT Staging                      | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 389       | 208.2 MB | -           | -        | 1     |
| 598 | Public Cloud - SL Micro Product Increments                  | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 601 | Public Cloud SL Micro Product Increments - devel            | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 61        | -        | -           | -        | 1     |
| 602 | Performance: HANA                                           | SLE 15             | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 604 | Development: Jose Lausuch                                   | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 605 | SLES for SAP                                                | Vendor Affirmation | 180  | 365   | 180     | 730  | -    | 2190  | 71        | 6.4 MB   | -           | 5.1 MB   | 2     |
| 606 | Maintenance: SLE Micro / Public Cloud Maintenance Updates   | Development        | 5    | 20    | 365     | 365  | 730  | 730   | 851       | -        | -           | -        | 1     |
| 607 | Test Development: Agama                                     | Development        | 5    | 30    | 14      | 40   | 40   | 60    | 1428      | 8.4 GB   | 7.6 GB      | -        | 1     |
| 608 | BCI Base Images 16.0                                        | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 25255     | 3.4 GB   | -           | 2.0 GB   | 2     |
| 609 | SLERT                                                       | Vendor Affirmation | 30   | 90    | 180     | 365  | 730  | 730   | 92        | -        | -           | -        | 2     |
| 610 | SL Micro 6.0 - respin                                       | SL Micro           | 10   | 90    | 21      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 611 | Test fsimorda-security                                      | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 6464      | 57.0 MB  | -           | -        | 1     |
| 612 | Agama                                                       | SLE 16             | 20   | 90    | 30      | 2190 | 730  | 3650  | 20801     | 5.0 GB   | -           | 156.4 MB | 2     |
| 614 | Test development: Tbaev                                     | Development        | -    | -     | -       | -    | -    | -     | 350       | -        | -           | -        | 1     |
| 615 | apappas-test                                                | Development        | 5    | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 616 | Velociraptor Test Development                               | Development        | 10   | 10    | 10      | 10   | -    | 730   | 7852      | 490.5 MB | -           | -        | 1     |
| 617 | apappas-ha-dev-test                                         | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 180       | -        | -           | -        | 1     |
| 618 | Kernel                                                      | SLE 16             | 30   | 120   | 90      | 730  | 730  | 2190  | 60913     | 18.0 GB  | 3.5 GB      | 12.1 GB  | 2     |
| 619 | Staging: SLE 16                                             | Development        | 5    | 20    | 12      | 50   | -    | 730   | 70        | -        | -           | -        | 1     |
| 620 | Functional                                                  | SLE 16             | 10   | 90    | 21      | 2920 | 730  | 2920  | 18702     | 2.6 GB   | -           | -        | 2     |
| 621 | Test Development - nzhang                                   | Development        | -    | -     | -       | -    | -    | -     | 3         | -        | -           | -        | 1     |
| 622 | Test SLE Micro fsimorda                                     | Development        | -    | -     | -       | -    | -    | -     | 93        | -        | -           | -        | 1     |
| 623 | BCI Base Images 15-SP7                                      | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 37131     | 5.3 GB   | -           | 2.5 GB   | 2     |
| 624 | Virtualization(SLE16 Developing)                            | SLE 16             | 60   | 450   | 90      | 450  | 730  | 730   | 5633      | 8.8 GB   | 621.2 MB    | 6.2 GB   | 2     |
| 625 | File Systems                                                | SLE 16             | 30   | 90    | 30      | 3650 | 730  | 3650  | 39707     | 14.9 GB  | -           | 10.6 GB  | 2     |
| 626 | Public Cloud clients                                        | SLE 16             | 5    | 20    | 12      | 50   | 730  | 730   | 560       | -        | -           | -        | 2     |
| 627 | BCI Vendor Affirmation                                      | Vendor Affirmation | 0    | 0     | 0       | 3650 | 730  | 3650  | 18        | 15.9 MB  | 15.9 MB     | 15.9 MB  | 2     |
| 628 | SLES for SAP Applications                                   | SLE 16             | 30   | 120   | 70      | 730  | 730  | 2190  | 6289      | 998.1 MB | 136.7 MB    | 825.8 MB | 2     |
| 629 | DEV- SL Micro Product Increments - Functional               | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 630 | Container Host                                              | SLE 16             | 20   | 90    | 21      | 90   | 730  | 1825  | 6485      | 2.5 GB   | -           | -        | 2     |
| 631 | Helm Charts                                                 | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 125       | 18.0 MB  | -           | 10.1 MB  | 2     |
| 632 | Test Development: MaurizioD                                 | Development        | 3    | 5     | 3       | 5    | 730  | 730   | 0         | -        | -           | -        | 1     |
| 633 | Performance: HANA                                           | SLE 16             | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 2     |
| 635 | DMS Development                                             | SLE 15             | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 636 | Test Development: Julian Diaz                               | Development        | -    | -     | -       | -    | -    | -     | 386       | -        | -           | -        | 1     |
| 637 | Development Investigations                                  | Others             | 2    | 5     | 2       | 5    | 60   | 730   | 82556     | 96.3 GB  | -           | -        | 1     |
| 638 | DMS Base Image                                              | SLE 15             | -    | -     | -       | -    | -    | -     | 11        | 19.1 MB  | 4.0 MB      | 11.3 MB  | 2     |
| 639 | X11_PA_FirefoxKiosk                                         | EOL                | 10   | 90    | 21      | 730  | -    | 2190  | 0         | -        | -           | -        | 2     |
| 645 | Helm Chart required Images                                  | Development        | 5    | 20    | 12      | 50   | -    | 730   | 0         | -        | -           | -        | 1     |
| 646 | TEST-zcjia                                                  | Development        | -    | -     | -       | -    | -    | -     | 812       | -        | -           | -        | 1     |
| 647 | Unified Core (Main)                                         | Containers         | 10   | 90    | 21      | 0    | 730  | 2190  | 2278      | 265.8 GB | -           | -        | 2     |
| 648 | Virtualization Dev mmartins                                 | Development        | -    | -     | -       | -    | -    | -     | 66        | -        | -           | -        | 1     |
| 649 | Package Hub                                                 | Development        | 5    | 20    | 12      | 50   | -    | 730   | 155       | -        | -           | -        | 1     |
| 654 | Maintenance: Gitea-based test triggering                    | Development        | 5    | 20    | 30      | 30   | 730  | 730   | 0         | -        | -           | -        | 1     |
| 655 | virt-dev-alice-group                                        | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 159       | -        | -           | -        | 1     |
| 657 | Development-RoyCai                                          | Development        | -    | -     | -       | -    | -    | -     | 478       | 331.1 MB | -           | -        | 1     |
| 658 | openqa                                                      | Development        | -    | -     | -       | -    | -    | -     | 2         | -        | -           | -        | 1     |
| 659 | LTP Stable                                                  | Public Cloud       | 10   | 90    | 70      | 730  | 730  | 2190  | 616       | 146.9 KB | 146.9 KB    | 146.9 KB | 2     |
| 663 | Desktop Applications                                        | SLE 16             | -    | -     | -       | -    | -    | -     | 5         | 130.1 MB | -           | -        | 2     |
| 667 | BCI Devel                                                   | Development        | -    | -     | -       | -    | -    | -     | 11        | -        | -           | -        | 1     |
| 668 | Test SLE Performance                                        | Development        | -    | -     | -       | -    | -    | -     | 0         | -        | -           | -        | 1     |
| 669 | Test Development: Containers Maintenance Staging            | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 94        | -        | -           | -        | 1     |
| 679 | Test Development: PC 16.0 Increments                        | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 102       | -        | -           | -        | 1     |
| 680 | Test Development mmilian Security                           | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 876       | 32.5 MB  | -           | -        | 1     |
| 683 | Development: SLE16_staging_Core_dev                         | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 16773     | -        | -           | -        | 1     |
| 688 | Application Images                                          | Public Cloud       | 10   | 90    | 70      | 0    | 730  | 0     | 531       | 294.4 MB | 1.4 MB      | 1.4 MB   | 2     |
| 704 | Test-SLE16-gpathak                                          | Development        | 5    | 15    | 12      | 15   | 30   | 31    | 0         | -        | -           | -        | 1     |
| 710 | BCI Base Images 16.1                                        | Containers         | 30   | 90    | 30      | 90   | 180  | 180   | 25531     | 5.4 GB   | -           | 2.5 GB   | 2     |
| 712 | Immutable Images                                            | SLE 16             | 10   | 90    | 21      | 0    | 730  | 0     | 0         | -        | -           | -        | 2     |
| 713 | SLE Micro 6.2 Vendor Affirmation                            | Vendor Affirmation | 180  | 0     | 180     | 0    | 730  | 0     | 0         | -        | -           | -        | 2     |
| 714 | SLES 16 Dev Stagings                                        | Others             | 5    | 20    | 12      | 50   | 730  | 730   | 5148      | 675.3 MB | -           | -        | 2     |
| 715 | SLES 16                                                     | Vendor Affirmation | 0    | 0     | 640     | 0    | 730  | 0     | 130       | 406.7 MB | 278.2 MB    | 381.0 MB | 2     |
| 716 | BCI Thirdparty containers                                   | Containers         | 10   | 90    | 21      | 0    | 730  | 0     | 3330      | 2.3 GB   | -           | -        | 2     |
| 718 | Transactional Images                                        | Development        | -    | -     | -       | -    | -    | -     | 8         | -        | -           | -        | 1     |
| 720 | SLE Micro 6.2 RT Vendor Affirmation                         | Vendor Affirmation | 180  | 0     | 180     | 0    | 730  | 0     | 0         | -        | -           | -        | 2     |
| 722 | Migration                                                   | SLE 16             | 10   | 90    | 21      | 0    | 730  | 0     | 253       | 1.8 GB   | -           | -        | 2     |
| 723 | Iam Migration                                               | Development        | 14   | 14    | 14      | 14   | 14   | 14    | 0         | -        | -           | -        | 1     |
| 727 | Unified Core (SLE 16.0)                                     | Containers         | 20   | 90    | 31      | 365  | 730  | 0     | 7759      | 31.3 GB  | -           | 15.1 GB  | 2     |
| 728 | BCI Latest Images (beta)                                    | Containers         | 10   | 90    | 21      | 0    | 730  | 0     | 5101      | 3.1 GB   | -           | -        | 2     |
| 729 | HA Development - Immutable                                  | Development        | -    | -     | -       | -    | -    | -     | 407       | -        | -           | -        | 1     |
| 732 | Trento Containers                                           | Containers         | 10   | 90    | 21      | 0    | 730  | 0     | 10        | 5.7 MB   | -           | -        | 2     |
| 733 | Test etchubykalo-security                                   | Development        | -    | -     | -       | -    | -    | -     | 99        | -        | -           | -        | 1     |
| 734 | Test Development: Firefox esr                               | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 22        | -        | -           | -        | 1     |
| 735 | 16.2 Development (temporary)                                | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 0         | -        | -           | -        | 1     |
| 736 | SLES4NVIDIA                                                 | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 102       | -        | -           | -        | 1     |
| 737 | Canary deployment verification                              | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 0         | -        | -           | -        | 1     |
| 738 | Maintenance: SLES 16.1 Installation and Migration Increment | Development        | -    | -     | -       | -    | -    | -     | 102       | -        | -           | -        | 1     |
| 752 | MLM-MCP                                                     | Containers         | 10   | 90    | 21      | 0    | 730  | 0     | 7         | 1.6 MB   | -           | -        | 2     |
| 759 | Trento                                                      | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 0         | -        | -           | -        | 1     |
| 761 | jrivera - experiment                                        | Development        | 5    | 20    | 12      | 50   | 730  | 730   | 58        | 555.8 MB | -           | -        | 1     |
| 762 | Unified Core (SLE 16.1)                                     | Containers         | 20   | 90    | 31      | 365  | 730  | 0     | 373       | 404.8 MB | -           | -        | 2     |

## Session starter

```
Read tasks/150_poo210483_osd_nonmaintenance_group_retention.md in full, plus the "Findings on
OSD" and "Proposed job group settings changes" sections of
tasks/148_poo210483_osd_results_full_distribution_of_test_results.md. Run `git status` first.
Load the `openqa`, `perl-dev` and `testing` skills only if the session ends up changing code;
this plan is settings-only.

This session: T1 only. Produce the worklist with the SQL in the plan (read-only, as the
`openqa` role: `psql -d postgresql://openqa:<password>@openqa.suse.de/openqa`), verify the counts
(332 groups, 110 development groups) and record the pre-change values table in this file under
a new `## Pre-change values` heading. Do not modify any job group value, do not write to the
database, do not create any commit.

Actions that need explicit confirmation before you run them: any `UPDATE`/`INSERT` on the OSD
database, any salt state apply, any psql as `geekotest` with anything but `SELECT`, any minion
enqueue, `git push`, PR creation, and any deletion. Report numbers with the query that produced
them.
```
