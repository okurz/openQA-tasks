# 148 (poo#210483): OSD results space — full distribution of test results

Ticket: https://progress.opensuse.org/issues/210483
Repository: `openQA` (this checkout), baseline `4d6c602db` (2026-08-19), branch per task
`feature/148_<slug>`. External counterpart: `/srv/salt/openqa/openqa-salt.ini` on OSD
(salt-managed, `salt-states-openqa` repo — **not checked out locally**).

Scope: make the result storage on `openqa.suse.de` reclaimable again and fix the
configuration defects that make the nightly cleanup ineffective, in a way that is also
useful for other openQA instances (audit tool, validation, docs). This plan covers the **232
maintenance job groups**; the non-maintenance groups are covered by
`tasks/150_poo210483_osd_nonmaintenance_group_retention.md`.

Non-goals: changing `limit_results_and_logs` scheduling, screenshot garbage collection
mechanics, asset cleanup, DB partitioning.

## Problem

`/results` (= `/var/lib/openqa`, `/dev/vdd`, 16 TB) is 93 % full (15 TB used, 1.2 TB free,
7.5 % free) while `[misc_limits] result_cleanup_max_free_percentage = 16` asks for 16 %
free (~2.56 TB). The nightly `limit_results_and_logs` runs and deletes everything it is
allowed to, but there is nothing left to delete: verified against the cutoff that was in
effect during the last completed pass (`2026-11-18 00:00`), **0** non-archived jobs in the
whole DB are past their retention (see Findings). Total reclaimable under the current
settings is ~10 GB.

The retention that produces the 12 TB is 640/730 days of *non-important* results in the
maintenance parents. So this is a policy/configuration problem, not a cleanup bug — but the
configuration has several defects that hide the problem and waste space:

1. `keep_logs_in_days >= keep_results_in_days` in 56 groups (52 exactly equal). `delete_results`
   removes the whole directory including logs, so those log settings never take effect. The
   log payload is 80–98 % of a result directory (measured), so this delays freeing almost
   the whole directory to the results expiry.
2. `0`/unset means "forever" for `keep_important_results_in_days` (129 groups, inherited from
   15 parents whose explicit `0` plus the salt config default `important_result_storage_duration = 0`)
   and for `keep_jobs_in_days` (184 groups) / `keep_important_jobs_in_days` (145 groups, no config
   default at all).
3. The API validates `logs > results` and `results > jobs` as errors but allows equality and
   skips the check when a value is `0`, which is how the grandfathered groups survive.
4. `keep_jobs_in_days` is unrelated to `keep_results_in_days`, so the DB accumulates 930,584
   result-less, log-less job rows up to 3 years old — which is what made the original
   report ("76 jobs from 2023 not archived") look like a storage leak.

## Findings on OSD (2026-11-19)

All data was gathered read-only: SQL as the `openqa` role (`psql -d
postgresql://openqa:<password>@openqa.suse.de/openqa`), plus `ssh osd 'sudo -n -u geekotest psql
openqa …'` for `comments`, `minion_jobs`, `screenshots`, `screenshot_links` (permission
denied for those tables as `openqa`). **No `du` over `/var/lib/openqa/testresults` or
`/var/lib/openqa/images`** — they hold millions of small files; only single directories
(≤ 5 at a time) and `df` were used.

### Storage layout

| mount | device | fs | size | used | free |
|---|---|---|---|---|---|
| `/var/lib/openqa` (bind of `/results`) | `/dev/vdd` | xfs | 16 T | 15 T (93 %) | 1.2 T |
| `/var/lib/openqa/archive` | `/dev/vde` | btrfs zstd | 11 T | 3.4 T (31 %) | 7.7 T |
| `/var/lib/openqa/share` | `/dev/vdc` | xfs | 20 T | 16 T (79 %) | 4.3 T |

`/dev/vde` additionally carries the automounted fixed `HDD`/`ISO` assets
(`/var/lib/openqa/share/factory/{hdd,iso}/fixed`), so the 3.4 T is not all archived results.

Result dirs: `/var/lib/openqa/testresults/<job_id/1000:%05d>/<%08d job_id>-<name>`
(`OpenQA::Schema::Result::Jobs::num_prefix_dir`). Under `/var/lib/openqa` there are
24,311 prefix dirs, 169,261,182 screenshots in `images/`, plus `webui/` 191 GB and
`backup/` 132 GB (SQL dumps).

### Where the 12 TB is

`sum(result_size)` over non-archived jobs: **12 TB** (5,840,499 jobs, 3,935,236 of them with
`result_size > 0` ⇒ ~3.05 MB per stored result). Archived: 532,116 jobs / 911 GB.
Spot check of 3 dirs: DB 79/141/69 MB vs `du` 78/138/58 MiB ⇒ accounting is trustworthy at
TB scale.

By effective `keep_results_in_days`:

| krd | jobs | results | past retention | bytes past retention |
|---|---|---|---|---|
| 640 | 3,635,958 | 8,321 GB | 294 | 0 |
| 730 | 971,709 | 2,871 GB | 11 | 0 |
| 365 | 45,916 | 53 GB | 3,611 | 0.7 MB |
| 90 | 193,196 | 83 GB | 166,204 | 0.5 MB |
| 21 | 185,209 | 336 GB | 127,100 | 2.5 GB |
| 30 | 419,714 | 123 GB | 354,436 | 1.1 GB |
| ≤ 60 | ~350k | ~90 GB | most | ≤ 7.5 GB |

Top groups: 414 Core Maintenance Updates 709 GB, 429 Security Maintenance Updates 577 GB,
665 SLES 16.0 Kernel Staging 541 GB, 405 SAP/HA 454 GB, 412 Core Wicked 427 GB,
641 SLE15SP7 Kernel Incidents 365 GB, 435/548/488 Kernel Incidents 310–325 GB each.

Sanity check that the cleanup works: for **all** groups, using the cutoff of the last pass,
`must_be_gone = 0`. (Group 710 BCI Base Images 16.1 showed "712 overdue" with `now()` because
those jobs crossed the line during the run that started 2026-11-19 and is still queued;
with the 2026-11-18 cutoff the same query returns 0.)

### What a results cap would free (live jobs older than N days)

| cap | jobs | results older |
|---|---|---|
| 3650 d | 0 | – |
| 730 d | 746 | 0 |
| 640 d | 2,828 | 0 |
| **365 d** | **1,298,652** | **2,192 GB** |
| 180 d | 3,068,814 | 5,049 GB |
| 90 d | 4,320,729 | 6,659 GB |
| 30 d | 5,209,905 | 8,046 GB |

Restricted to groups that currently keep results longer than 365 d: 1,124,806 jobs,
**2.19 TB**. That is the only single setting change that satisfies
`result_cleanup_max_free_percentage = 16` (needs ~1.4 TB).

### Logs vs. results (measured)

`RESULT_CLEANUP_LOG_FILES` (`OpenQA::Jobs::Constants`) = `autoinst-log.txt`,
`ulogs/`, videos, `video_time.vtt`, `serial0.txt`, `serial_terminal*.txt`; those are what
`delete_logs` removes, the rest stays until `delete_results`. Samples (`du -sk` of those
paths vs. the whole dir):

| sample | dir size | log payload |
|---|---|---|
| 4× group 414 `mau-extratests*` | 57–78 MB | 95–98 % |
| 3× BCI/container (groups 445/710/444) | 1.1 MB | 80–85 % |

So the `logs < results` invariant is a large lever, not cosmetics: for the 56 violating
groups the log cleanup never runs and ~85–97 % of every directory is only freed at
results expiry. With a two-thirds rule the freed-early window is
`[2/3·results, results]` — measured 138 GB of `result_size` in steady state
(637: 40 GB, 220: 33 GB, 445: 27 GB, 625: 12 GB, 607: 7 GB, …) ⇒ ~120 GB of peak reduction,
plus a few GB on the important side (only 58 GB of live results are in important builds).

### Result dir composition by age (measured 2026-11-19)

29 randomly sampled result dirs of the biggest maintenance groups (414, 429, 405, 411, 435, 488,
548, 562, 573, 641, 652, 656, 665, 666, 673, 281), `du -sk` of the dir versus the
`RESULT_CLEANUP_LOG_FILES` set, `ulogs/` and video files, plus the two largest files:

| dir age | samples | dir size | log payload share | largest remaining file |
|---|---|---|---|---|
| 0–7 d | 3 | 2.6–8.1 MB | 51–74 % | `video.webm`, `details-installation.json` (3.7 MB) |
| 7–14 d | 3 | 0.3–10.1 MB | 0–88 % (0 where `logs = 10` already expired) | `autoinst-log.txt`, `details-boot_ltp.json` |
| 14–21 d | 3 | 1.6–70 MB | 61–89 % | `autoinst-log.txt` (18 MB), `serial_terminal.txt` |
| 21–30 d | 3 | 0.3–29 MB | 0–97 % | `ulogs/*.tgz`, `autoinst-log.txt` |
| 30–60 d | 4 (`logs = 60/90`) | 2.3–45 MB | 70–71 % | `autoinst-log.txt` |
| 60–90 d | 4 (`logs = 60`) | 0.3–22.5 MB | 0 in 3 of 4, 92 % in 1 | `details-partition.json` |
| 90–180 d | 3 | 0.1–1.8 MB | 0 % | `details-*.json` (0.3–0.5 MB) |
| 180–365 d | 3 | 0.08–1.2 MB | 0 % | `details-boot_ltp.json` |
| 365–640 d | 3 | 0.5–1.3 MB | 0 % | `details-boot_ltp.json` |

Conclusions:

* Log payload dominates a dir only while `keep_logs_in_days` has not expired; afterwards it is
  **exactly 0** and the dir is 0.1–1.5 MB of `details-*.json` + `vars.json` + `ulogs` leftovers.
  Total log payload on `/results` today ≈ **3.2 TB** (matching the cap-2-d estimate in the
  proposals below), 25 % of the 12.9 TB.
* Therefore **no log setting can reclaim the 5.4 TB of dirs older than 180 d**; only the results
  retention can. Conversely, in the groups that already use `logs = 10`, the log lever is spent.
* In the 640/730-day maintenance groups the 2-year "maintenance test results" that are kept
  today consist of JSON details only — **the logs were already deleted after 10–30 days**. The
  obligation covers results+status only and logs are best effort (decided 2026-11-19), so the
  log cap below is unproblematic and the 2-year block is results-only.
* The 56 groups with `logs >= results` are the only place where the log cleanup is dead, and
  they are small (138 GB window); the big log gains are in groups with `logs = 30/60/90`
  (SAP/Kernel Incidents, SL Micro Kernel) — 235 groups keep logs longer than 14 days.

### Screenshots: results vs. archive references

`screenshots` 169,261,182 rows; `screenshot_links` 441,992,137 rows (38 GB); links belonging
to archived jobs 43,548,682, of those older than 730 days 20,156,776. Average screenshot
file 10.3 KB (5 samples) ⇒ `images/` ≈ 1.7 TB, guessing from `df` ≈ 2–2.5 TB.

First attempt "count screenshots with no link" is **wrong** for this question: it counts
orphans (which `limit_screenshots` already deletes). It must require `EXISTS (link)`.
Sample of 20 random archived jobs (`result_size > 0`, `t_created < now()-730 d`):
7,925 links, of which 1,017 screenshots (12.8 %) are exclusively used ⇒ extrapolated
~2.6 M screenshots ≈ 26 GB released when those archived results are deleted. Most
screenshots are shared with live jobs and survive. **This is the least certain number in the
report and the main job of task I1** (sample-kill estimation, later verified by `df` deltas).

### Archived (important) results

Archiving only happens for *preserved important* jobs, so 878 GB of the 911 GB archived
results are in `tag:…:important` builds (341,807 jobs). Tag parsing was validated: the
`important_results = 730` bucket contains exactly 0 bytes older than 730 days, as the code
requires. Buckets by effective `keep_important_results_in_days`:

| ires | archived important jobs | archived results | of which > 730 d |
|---|---|---|---|
| 730 | 71,912 | 267 GB | 0 |
| forever | 38,417 | 250 GB | 180 GB (oldest 2020-03) |
| 3650 | 10,178 | 143 GB | 33 GB |
| 2920 | 30,807 | 97 GB | 76 GB |
| 2190 | 35,059 | 85 GB | 32 GB |
| ≤ 450 | ~3,800 | 36 GB | 0 |

`find_jobs_with_expired_results` has **no `archived` filter**, so archived result dirs are
deleted at their results retention while the job row (and its `job_modules`) stays. Archived
results older than: 365 d → 649 GB, **730 d → 335 GB**, 1095 d → 220 GB, 1460 d → 131 GB,
1825 d → 97 GB, 2920 d → 0. A 730 d cap therefore frees ~335 GB (~62,400 dirs) on the
archive volume plus ~26 GB of screenshots on `/results`.

### Job-group settings audit (578 groups, 29 parents)

Deployed defaults (`/etc/openqa/openqa.ini.d/openqa-salt.ini`, from
`/srv/salt/openqa/openqa-salt.ini`): `log_storage_duration = 10`,
`important_log_storage_duration = 90`, `result_storage_duration = 21`,
`important_result_storage_duration = 0` (forever), and **no** `job_storage_duration` /
`important_job_storage_duration` (hence forever).

* `logs >= results`: 56 groups / 504,845 jobs / 232 GB — 31× `30→30`, 1× `2→2` (637,
  92 GB), 3× `60→60`, 2× `90→90`, 6× `180→180`, 2× `14→14`, rest smaller; 4 groups actually
  have `logs > results` (30→12, 30→20, 0→640, plus one 0→0).
* `important logs >= important results`: 46 groups / 555,147 jobs / 242 GB — 44 equal,
  2 larger (446: 60→50, 627: 0→3650). Group 322 (`logs 30/30`, `ilogs 365/365`) violates both.
* `results = 0` (forever): 2 groups (627, 462), 18 jobs.
* `important results = 0`: 129 groups (102 own, 15 parents explicitly supply `0`).
* `logs = 0`: 2 groups; `important logs = 0`: 5 groups.
* `keep_jobs_in_days` unset: 184 groups / 10,652 live jobs / 11 GB (oldest 2024-12-11);
  `keep_important_jobs_in_days` 0 or unset: 145 groups / 1,179,256 live jobs.
* `results > jobs`: 2 groups; `important results > important jobs`: 5 groups (647 Unified
  Core: ires forever but ijobs 2190).
* API validation today (`lib/OpenQA/WebAPI/Controller/API/V1/JobGroup.pm`
  `_check_keep_logs_and_results`): error on `logs > results` and `results > jobs`, skipped
  when either side is `0`, equality allowed ⇒ `logs == results` is silently accepted.

### Job metadata vs. results economics

| component | size | per job (6,373,459 jobs) |
|---|---|---|
| `jobs` | 13 GB | 2.2 KB |
| `job_settings` (327 M rows) | 80 GB | 12 KB |
| `job_modules` (312 M rows) | 101 GB | 16 KB |
| `screenshot_links` | 38 GB | 6 KB |
| DB total | 278 GB | ~44 KB |
| one stored result dir | 12 TB / 3.94 M | **~3.05 MB** |

One result dir ≈ 70 job records. 4,526,560 jobs in 2026 so far ⇒ ~5.4 M jobs/year ⇒
**~185 GB of DB per year of `keep_jobs`**. Consequence: keeping metadata long is cheap and
`job_modules` keep the per-module evidence after the result dir is gone, so `keep_jobs` must
**not** be tied to `keep_results`; only "forever" needs clamping.

Non-archived jobs with no results: 1,905,213 (1,435,974 of them also `logs_present = false`);
930,584 of them are already past their group's results retention. Those are what made the
"76 jobs from 2023" look like a leak: group 322 is a deprecated group
(`keep_jobs_in_days = 1095`, `keep_results_in_days = 30`, no comments ⇒ no important builds);
its 76 oldest rows hold `result_size = 0`, `logs_present = false` and no directory exists,
their expiry is 2026-11-30 … 2026-12-19.

### Cleanup runtime observations

`limit_results_and_logs` 25528992 started 2026-11-18 00:00:10, finished 2026-11-19 01:28:22
(~25.4 h); 25565101 (2026-11-19) is still `inactive` because the guard is held for a day;
25487569 (2026-11-16) failed with "Worker went away". `limit_screenshots` children ran
01:28–03:13. `/var/lib/openqa/webui/cache/cleanup-status.json` = `{"last_processed_job_group_id": 419}`,
so groups with id > 419 are processed first, i.e. with a cutoff ~24 h behind real time.
`minion_jobs` is pruned (only 44,033 `archive_job_results` rows, all 2026-11-12..19), so
archiving history older than a week is unavailable.

## Decisions

Decided during the analysis session (2026-11-19):

1. **Results retention of "maintenance" groups is out of scope for now**: the 2-year obligation
   applies to maintenance test results (640/730-day incident and maintenance-update groups,
   4.5 TB older than 180 d), so it must not be lowered until that obligation is renegotiated
   ("maybe down to less" is a later, separate conversation).
2. **The obligation covers results+status only; logs are "best effort"** — so log retention can
   be lowered everywhere, including the maintenance groups.
3. **No feature work in this plan**: treating more jobs as important or archiving
   non-important ones is deferred to separate sessions (tiering, storage, compression).
4. **Non-maintenance groups are handled in `tasks/150_poo210483_osd_nonmaintenance_group_retention.md`**
   (development groups first, ~163 GB). This plan covers the 232 maintenance groups only.

Still open:

5. Log cap target: 14 d (`logs`) / 60 d (`ilogs`) recommended (P1); 7 d frees 0.56 TB more,
   21 d frees 0.7 TB less.
6. Clamp every `0`/unset retention to 3650 days, in the DB **and** in `[default_group_limits]`.
7. `keep_jobs*`: clamp "forever" only (1095 / 3650), keep finite values, keep metadata
   independent of results.
8. Whether to re-flag the 930,584 result-less expired job rows as `archived = true` (T7).
6. Clamp every `0`/unset retention to 3650 days, in the DB **and** in `[default_group_limits]`.
7. `keep_jobs*`: clamp "forever" only (1095 / 3650), keep finite values, keep metadata
   independent of results.
8. Whether to re-flag the 930,584 result-less expired job rows as `archived = true` (T7).

## Proposed job group settings changes (2026-11-19)

All values are *freed bytes on `/results`*, estimated from `result_size` per age bucket
(578 groups, 12.9 TB live) and the measured log share (80 % inside a group's log window, 0
outside), **restricted to the 232 maintenance groups (12.3 TB)**. The non-maintenance groups
(671 GB, ~163 GB gain) are planned separately in `tasks/150_…`.

Group categories by name/parent name (only maintenance rows apply here):

| category | groups | live results | >180 d | >365 d | log-14 d gain |
|---|---|---|---|---|---|
| incident | 72 | 5,175 GB | 2,278 GB | 1,044 GB | 829 GB |
| maintenance updates | 18 | 3,643 GB | 2,239 GB | 1,094 GB | 29 GB |
| staging | 38 | 2,497 GB | 678 GB | 160 GB | 563 GB |
| increment | 40 | 846 GB | 195 GB | 54 GB | 283 GB |
| QR | 35 | 66 GB | 12 GB | 5 GB | 12 GB |
| other "maintenance" | 43 | 41 GB | 19 GB | 7 GB | 0 |
| non-maintenance (plan 150) | 332 | 671 GB | 0 | 0 | 126 GB |

**P1 — absolute log cap, all maintenance groups: `keep_logs_in_days = min(current, 14)`,
`keep_important_logs_in_days = min(current, 60)`, plus the invariant `logs < 2/3·results`.**
235 groups change DB-wide (209 of them maintenance), 77 of them by more than 100 MB. Gain by cap
(maintenance groups only; non-maintenance adds ~126 GB at 14 d, see plan 150):

| cap | 7 d | 10 d | **14 d** | 21 d | 30 d | 45 d |
|---|---|---|---|---|---|---|
| freed | 2.23 TB | 1.95 TB | **1.72 TB** | 1.03 TB | 0.47 TB | 0.29 TB |

Top gains: 665 SLES 16.0 Kernel Staging 60→14 d (195 GB), 573 SL Micro Kernel Increments
90→14 (139 GB), 666 SLES 16.0 Kernel Increment 60→14 (126 GB), 562 SL Micro Kernel Staging
90→14 (109 GB), 652 SP7 SAP Incidents 30→14 (95 GB), 689 SL Micro 6.2 Kernel Staging 90→14
(89 GB), 558 SP6 SAP Incidents 30→14 (89 GB), 641 SP7 Kernel Incidents 30→14 (76 GB), then
441/494/488/435/548 (Kernel/SAP Incidents, 50–59 GB each), 672/744 staging groups (44 GB).
Cost: logs of failures older than 14 days become unreadable — that is the only real price, and
logs are explicitly best effort (decision 2). This is **66 % of the maintenance-only
total** (1.72 of 2.59 TB) and needs no compliance decision.

**P2 — staging and increment results: WITHDRAWN (2026-11-19).** The earlier rationale
("pre-release validation, not shipped maintenance results, so no 2-year obligation") is wrong for
the affected products. Group structure on OSD:

* SLE 15 has proper post-release evidence in `Maintenance: Aggregated updates` (414 Core, 411
  Kernel, 405 SAP/HA, 419 MinimalVM, 412 Wicked, 429 Security) plus the `Single Incidents` groups.
* **SLES 16 (parents 50/52) has no `Maintenance Updates` groups at all** — 665/666/673/672/674 and
  the 16.1 groups *are* the maintenance test evidence.
* **SLE Micro has `Maintenance Updates` groups for Core/Container/Security/Virtualization/Public
  Cloud (534/420/547/542/532) but none for Kernel** — so 562 and 573 are the only kernel
  maintenance evidence.

Capping these 54 groups to 180 d (873 GB) would therefore drop maintenance test results inside the
2-year obligation. Not executed. Only 150 d worth of data for a subset (SLE Micro non-kernel) is
possibly redundant, ~50 GB — not worth the compliance risk.

**P3 — non-maintenance groups: moved to plan 150.** Their logs/results/jobs reduction is worth
~163 GB (development groups first), planned in
`tasks/150_poo210483_osd_nonmaintenance_group_retention.md`.

**P4 — clamp "forever": WITHDRAWN for jobs (2026-11-19).** Old job rows are kept on purpose as a
showcase, they are cheap, and archived result dirs live on `/archive`, not `/results`:

* `keep_jobs_in_days` forever covers 184 groups but only 11,152 live jobs (~0.5 GB of DB); the DB
  holds 6,373,459 rows, 396 of them older than 10 years (oldest 2016-05-12). A clamp to 1095 days
  would delete exactly those showcase rows and buy nothing.
* `keep_important_jobs_in_days` forever covers 145 groups / 1,181,830 rows; that is the only part
  that grows, and it grows on `/dev/vdb` (308 GB of 600 GB, 52 %), not on `/results`.
* Result dirs are already bounded by `keep_results_in_days`, so job rows never hold space on
  `/results` beyond that; they only leave job pages without logs/results (the 930k rows phenomenon).

Remaining optional fragment: `keep_important_results_in_days` 0/unset → 3650 (129 groups, 15 parents,
salt default) — affects the archive volume only, frees nothing today (no archived result is older than
10 years), so it is a safety net rather than a measure. Skip it as well if the archive is fine.

**P5 — deferred:** results retention of incident (2.28 TB >180 d) and maintenance updates
(2.24 TB >180 d) = 4.5 TB. This is the only remaining large block and it is exactly the 2-year
obligation; revisit after decision 5/1, and only via tiering/compression/storage (separate
sessions).

P1 only = **1.72 TB** (plus ~163 GB from plan 150) → `/results` free grows from 1.1 TB (7.5 %) to
~2.8 TB (17.6 %) and ~3.0 TB (18.6 %) together — above `result_cleanup_max_free_percentage = 16`
but without much margin, which is why the 14 d log cap matters: at 21 d it is only 1.03 TB and the
result (14 %) misses the threshold. The freed bytes are *already on disk*, so the next
`limit_results_and_logs` pass (~25 h) deletes them; the new steady state is reached as the 14-day
log window rolls over, so verify `df` after one pass and again a week later.

## Executed changes

### 2026-11-19 — L1′ log cap 30 d on the 18 maintenance groups with `keep_logs_in_days > 30`

Approved and executed by okurz on 2026-11-19 (15:51–15:52 CET). Method: one
`PUT /api/v1/job_groups/<id>` per group with `name` (unchanged) and `keep_logs_in_days=30`, i.e.
the API validation ran and `api/v1/audit_events` holds one `jobgroup_update` entry per group
(ids 56273590–56273615, user 87). No other column changed in any of the 18 groups (verified by
before/after API snapshot), and no other group was touched.

| id | group | logs |
|---|---|---|
| 665 | Maintenance: SLES 16.0 Kernel Staging | 60 → 30 |
| 573 | SL Micro Product Increments - Kernel | 90 → 30 |
| 666 | Maintenance: SLES 16.0 Kernel Increment | 60 → 30 |
| 562 | SL Micro Staging Updates - Kernel | 90 → 30 |
| 689 | SL Micro 6.2 Staging Updates - Kernel | 90 → 30 |
| 106 | Maintenance: SLE 12 SP3 TERADATA Core Incidents | 60 → 30 |
| 193 | Maintenance: 12-SP3-TERADATA Kernel Incidents | 90 → 30 |
| 532 | Public Cloud Maintenance Updates | 60 → 30 |
| 709 | Maintenance - QR - SLE16.0 - Kernel | 60 → 30 |
| 570 | SL Micro Staging Updates - Virtualization | 90 → 30 |
| 542 | Virtualization Maintenance Updates | 60 → 30 |
| 559 | Virtualization SLES Incidents for SLE15/12 | 60 → 30 |
| 160 | Maintenance: SLE 11 SP4 LTEC Kernel Incidents | 90 → 30 |
| 739 | Maintenance: SLES 16.1 Kernel Staging | 60 → 30 |
| 485 | Maintenance: SLE 11 SP4 Core Incidents | 60 → 30 |
| 161 | Maintenance: SLE 11 SP3 Kernel Incidents | 90 → 30 |
| 325 | Maintenance - QR - JeOS15SP2 | 60 → 30 |
| 740 | Maintenance: SLES 16.1 Kernel Increment | 60 → 30 |

Verification immediately after the change:

* 0 maintenance groups keep logs longer than 30 days
  (`coalesce(g.keep_logs_in_days, p.default_keep_logs_in_days, 10) > 30`).
* 93,410 `done` jobs in these groups have `logs_present` and are older than 30 days; their
  directories hold 551 GB of `result_size`, of which ~463 GB (84 %) is log payload — matching the
  80 % log share measured per directory, and the L1′ estimate of 462.9 GB.
* Results retention, important logs and every other setting are unchanged (the 2-year obligation
  on maintenance results is untouched).

Follow-up verification (after the next `limit_results_and_logs` pass, ~25 h):
`select id, state, finished, notes from minion_jobs where task='limit_results_and_logs' order by id
desc limit 3`, `df -h /results`, and the query above (`logs_present` older than 30 d) returning
0 jobs for these groups. Expect ~460 GB less on `/results`.

## Tasks

Every task is one session and one commit in this repository, except T6 (ops on OSD, gated by
approval) and I1–I3 (read-only investigations that produce the numbers T6 needs; their output
goes into this file, which is not version controlled). Tasks T1–T3 build the tool that I1–I3
and T6 use for verification.

### T1: `openqa-audit-retention` — effective settings and their source
**Files:** `script/openqa-audit-retention` (new, Perl), `t/44-scripts-openqa-audit-retention.t` (new).
**Depends on:** nothing. **Commit:** `feat: add openqa-audit-retention to report ineffective cleanup settings`

Report per job group and parent group: effective value and source (`own` / `parent` /
`default`) for all six retention columns, plus classification: `logs_not_shorter_than_results`,
`important_logs_not_shorter_than_important_results`, `forever`, `results_gt_jobs`,
`important_results_gt_important_jobs`. Output `--format text|json`, read-only, no writes, no
`du`. Reuse `OpenQA::Schema` + `OpenQA::App->singleton->config` for the defaults; reuse
`OpenQA::Utils::check_df` only in later tasks.

**Acceptance criteria**
- [ ] `./script/openqa-audit-retention` prints one line per group with all six effective values and their source
- [ ] For fixture data with `logs == results` the group is classified as violating, with and without parent inheritance
- [ ] A group inheriting `important_result_storage_duration = 0` from config is reported as `forever` with source `default`
- [ ] `--format json` output is stable and covered by the test
- [ ] No SQL writes; the script only issues `SELECT`s (assert via the test's schema mock or by review)

### T2: distribution and retention what-if
**Files:** `script/openqa-audit-retention`, `t/44-scripts-openqa-audit-retention.t`.
**Depends on:** T1. **Commit:** `feat: report job/result distribution and retention what-if in openqa-audit-retention`

Add per-group aggregates (live and archived job counts, `sum(result_size)`, oldest
`t_created`, count of jobs with `result_size = 0`) and `--cap DAYS[,DAYS…]`, which prints for
each cap: jobs and bytes whose results are older than the cap, overall and per parent group.
Filters: `--parent ID`, `--group ID`. Must not load all jobs into Perl: aggregate in SQL.

**Acceptance criteria**
- [ ] `--cap 365` on the fixture prints the expected job count and byte sum
- [ ] Aggregates include archived jobs separately and label `result_size = 0` jobs
- [ ] A group with `keep_results_in_days = 0` is treated as forever in the what-if, not as 0 days

### T3: screenshot references of archived jobs
**Files:** `script/openqa-audit-retention`, `t/44-scripts-openqa-audit-retention.t`.
**Depends on:** T2. **Commit:** `feat: report screenshot references of archived jobs in openqa-audit-retention`

Add `--screenshots --sample N`: for a bounded random sample of archived jobs older than
`--older-than DAYS` report links, screenshots exclusively used by those jobs, and screenshots
shared with live jobs. Must require `EXISTS (screenshot_links)` to avoid counting orphans
(the orphan population is a different problem, already handled by `limit_screenshots`), and
must `LIMIT`/sample, never scan `screenshot_links` fully.

**Acceptance criteria**
- [ ] Sample query is bounded (explicit `LIMIT`/`ORDER BY random() LIMIT N`) and configurable
- [ ] Orphans are excluded; a fixture screenshot with no links is not reported as exclusive
- [ ] Output states the sample size and the extrapolation factor so the number is auditable

### I1: investigate the results-vs-archive share of screenshots (read-only, no commit)
**Depends on:** T3. **Deliverable:** numbers appended to this plan.
Run T3 on OSD with several sample sizes and id ranges (job-level sample as done during the
analysis: 20 jobs → 7,925 links / 1,017 exclusive). Answer:
* how many screenshots are referenced by archived jobs only, split by archive age
  (`> 730 d`, `> 1095 d`) and by parent group;
* expected GB in `/var/lib/openqa/images` (169 M screenshots × measured average 10.3 KB) if
  those archived results are deleted;
* what share stays because it is shared with live jobs;
* whether the number is confirmed by a `df` delta on `/var/lib/openqa` after the first
  T6 stage (compare the same weekday before/after, screenshots are deleted in batches by
  `limit_screenshots`).
No `du` of `images/`; sample `ls -l` of ≤ 20 files for the size estimate.

### I2: investigate the logs-vs-results ratio — DONE (2026-11-19)
**No dependency on code, no commit.** Performed with 29 age-stratified directory samples; results
in "Result dir composition by age" and in the P1 table above. Open follow-up if P1 is applied:
re-sample 20 dirs after the first cleanup pass to confirm the 80 % log share and the 1.72 TB.

### I3: investigate where a results cap helps most (read-only, no commit)
**Depends on:** T2. **Deliverable:** staged rollout table appended to this plan.
Use `openqa-audit-retention --cap 180,365 --parent …` against OSD to produce, per parent
group, jobs/bytes freed per cap step, sorted by gain, plus the expected `df` after each step
and which parents keep important results longer than the proposed cap (parent 8
"Maintenance: Single Incidents", 7, 21, 23, 24, 43, 45, 50 dominate). Recommend the first
three steps (largest gain, lowest reviewer risk) for T6.

### T4: warn on ineffective (`logs >= results`) retention
**Files:** `lib/OpenQA/WebAPI/Controller/API/V1/JobGroup.pm`, `t/api/10-jobgroups.t`.
**Depends on:** nothing. **Commit:** `fix(api): warn when log retention cannot take effect`

`_check_keep_logs_and_results` currently errors only on `logs > results` and skips the check
entirely when a value is `0`. Add to `warnings_by_field`:
* `keep_logs_in_days >= keep_results_in_days` (both non-zero) → warning that the log retention
  has no effect because results deletion removes logs, suggest `<= 2/3`;
* same for the `important` pair;
* `results = 0` while `jobs` is finite → warning that the results retention can never be
  reached because the job row (and its directory) is deleted first.
Keep errors unchanged (OSD has 52/44 grandfathered groups with equality, so this must not
become an error) and apply the same to `default_keep_*` on parent groups.

**Acceptance criteria**
- [ ] Equality produces a warning, not an error; `>` still produces an error (existing tests unchanged)
- [ ] Warnings appear for both group and parent-group endpoints, with `warnings_by_field` keys matching the field names
- [ ] `results = 0` with finite `jobs` produces a warning
- [ ] No behaviour change for fully valid input (no warnings)

### T5: document retention ordering and "forever"
**Files:** `docs/UsersGuide.md`, `etc/openqa/openqa.ini` (comments only).
**Depends on:** T4 (wording). **Commit:** `docs: document retention ordering and forever semantics of job group limits`

A short table: six settings, inheritance (`own → parent default → [default_group_limits]`),
`0 = infinity`, and the invariants `logs < results` (recommend `2/3`), `results <= jobs`,
`important_*` longer than the non-important counterpart. State explicitly that
`logs == results` makes the log retention dead, and that `[default_group_limits]
important_result_storage_duration = 0` and the absent `job_storage_duration` /
`important_job_storage_duration` mean forever. Align the commented example values in
`etc/openqa/openqa.ini` with the documented recommendation (do not change shipped defaults).

**Acceptance criteria**
- [ ] Documented invariants match the behaviour tested in T4
- [ ] Example config comments name all six settings and the `0` semantics
- [ ] `make test-markdown` passes

### T6: apply the OSD changes (external, approval-gated, no commit here)
**Depends on:** I1–I3 and approval. **Deliverable:** changed settings on OSD + verification
output recorded in this file.

Split into independently verifiable stages, each followed by one completed cleanup pass
(~25 h) before the next:

* **T6a — P1 log cap (1.72 TB)**: `keep_logs_in_days = min(current, 14)` and
  `keep_important_logs_in_days = min(current, 60)` for the 209 maintenance groups with a larger
  value, `logs = min(current, 2/3·results)` for the 56 violating groups. Parent-level defaults
  first so children that inherit need no own value; report the resulting per-group diff before
  writing.
* **T6b — P2 staging/increment: withdrawn**, do not execute. The 54 groups are the primary (SLES
  16) or only (SLE Micro kernel) maintenance evidence, see P2 above.
* **T6c — P3 non-maintenance: not here**, handled in
  `tasks/150_poo210483_osd_nonmaintenance_group_retention.md` (~163 GB, dev groups first).
* **T6d — P4: cancelled for jobs.** `keep_jobs_in_days` / `keep_important_jobs_in_days` stay as
  they are ("forever" where nobody overrode them), matching the showcase intent; see P4. Only if
  wanted: `important_result_storage_duration = 3650` in the salt config as an archive-side safety
  net (no effect before 2036).

Each stage is independent and can be reverted by restoring the previous values recorded in the
pre-change diff.

Verification per stage: `df -h /results /var/lib/openqa/archive`, the `openqa-audit-retention`
report before/after, the notes of the next `limit_results_and_logs` minion job
(`select id, state, finished, notes from minion_jobs where task='limit_results_and_logs' order
by id desc limit 3`), and for T6b the "oldest non-archived job" query. Writes need explicit
confirmation in the plan's Approvals table first; the config part must be verified with the
actor that runs at boot (salt, not an interactive edit of `/etc`).

### T7: optional — archive jobs that have no results left
**Files:** `script/openqa-archive-jobs` (new) + test; or extend `openqa-enqueue-result-cleanup`.
**Depends on:** decision 6. **Commit:** `feat: add openqa-archive-jobs to archive jobs without results`

There is no API/UI path to set `archived = 1`; only `archive_job_results` does, and
`Jobs::archive` returns early with `update({archived => 1})` when the result dir is gone, so
no file is touched. Add a script that enqueues `archive_job_results` in batches for jobs past
their group's results retention with `result_size = 0` (930,584 rows today) — never for jobs
whose directory may still exist. Guard with `--dry-run` default false vs.
`--limit N`, and refuse to run when the resulting dir exists for a sampled job.

**Acceptance criteria**
- [ ] `--dry-run` prints the batch size and sample job IDs without enqueuing
- [ ] Only jobs with `archived = 0`, `result_size = 0`, `state` final and past results retention are selected
- [ ] The script never deletes files itself and fails loudly if a selected job's dir exists

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Result retention cut removes evidence still needed by reviewers | Medium | 365-day cap only after I3; staged parents; `job_modules` and job pages stay |
| `important results` 730 d loses GM/QU logs of old builds | Medium | staged 1825 → 730; documented in T5; announce in the ticket before T6c |
| `keep_jobs` clamp deletes job pages users link to bug reports | Medium | clamp "forever" only, 1095 d floor for normal builds; no change to finite values |
| Two-thirds rule leaves too little log retention for short-lived groups | Low | rule only lowers groups where `logs >= results`; `2/3` keeps ≥ 20 d for the common `30/30` |
| Cleanup pass takes >24 h, so a stage's effect shows up a day late | Low | one stage per day, verify with the minion notes and the cache file |
| `result_size` bookkeeping drift (dirs deleted outside openQA) makes the what-if optimistic | Low | spot-check `du` of ≤ 5 sampled dirs per report, as done in the analysis |
| Edits of `/etc/openqa` by hand diverge from salt | Medium | config change goes through `salt-states-openqa`, verified with `salt-call state.apply` |

## Open questions

1. Should `default_group_limits.important_result_storage_duration` ship as `3650` upstream,
   or keep `0` and only fix OSD's `openqa-salt.ini`? (Upstream default change would bound every
   instance's archive growth but silently deletes archived dirs after 10 years.)
2. Is a shared parent level enough for T6b, or do the 94 `640`-day overrides need to be
   lowered individually because they are set on the group, not inherited?
3. Do we want `keep_results_in_days` for the `Maintenance: QR` parents (23) at 365 as well, or
   do QR groups need the full two years of results for reuse/regression comparison?
4. Follow-up: `minion_jobs` is pruned so aggressively that the archiving history cannot be
   audited — is a longer retention for `archive_job_results` worth its own ticket?
5. `label:linked` is matched as a literal in `_find_expired_jobs`, while tagging uses the
   `tag:` syntax — verify whether linked-job protection is dead code (own ticket).

## Approvals

| Decision | Approver | Date |
|---|---|---|
| Read-only SQL/`ssh` investigation on OSD (no writes) | okurz | 2026-11-19 |
| Findings: old unarchived rows are metadata-only, the 12 TB is 640/730-day non-important results | okurz | 2026-11-19 |
| Log retention default rule `logs < results`, two-thirds, with allowed exceptions | okurz | 2026-11-19 (proposed by user) |
| Clamp all `0`/forever retention to 10 years (3650 days) on OSD — narrowed to results only, see below | okurz | 2026-11-19 (proposed by user) |
| Scope of this plan: job group retention settings only; no feature work (tiering, archive non-important) here | okurz | 2026-11-19 |
| Levers: reduce `keep_logs*` in all groups; reduce all periods only in groups without "maintenance" in name/parent name/description | okurz | 2026-11-19 |
| Results retention of maintenance groups stays (2-year obligation), revisit only after clarification | okurz | 2026-11-19 |
| `keep_jobs`/`keep_important_jobs` stay "forever" (showcase of old jobs); no clamp | okurz | 2026-11-19 |
| P1 log cap 14 d / important 60 d (1.72 TB, remaining 191 maintenance groups) | pending | – |
| L1′ executed: log cap 30 d on the 18 maintenance groups with `logs > 30` (~463 GB) | okurz | 2026-11-19 |
| P2 staging+increment results 180 d (873 GB) | withdrawn — conflicts with the 2-year obligation | 2026-11-19 |
| 2-year obligation covers results+status only, logs best effort (unblocks P1) | okurz | 2026-11-19 |
| Non-maintenance groups (incl. development first) handled in plan 150 | okurz | 2026-11-19 |
| Cap `keep_important_results_in_days` at 730 on the archive (335 GB, separate session) | pending | – |
| Re-flag 930,584 result-less expired job rows as `archived` | pending | – |
| Any write on OSD (salt config, DB updates, minion enqueues) | pending | – |
| Plan approved for implementation as written | pending | – |

## Gates

Gate before every commit (repo rule): `make tidy && make test-checkstyle`.
Then the task-specific gate, then `make test-gitlint` after the commit exists.

| Commit / task | Exact verification command |
|---|---|
| T1 `feat: add openqa-audit-retention …` | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/44-scripts-openqa-audit-retention.t && make check-line-coverage && make test-gitlint` |
| T2 `feat: report job/result distribution …` | same as T1 (same test file, full file re-run with `COVERAGE=1` and `make check-line-coverage`) |
| T3 `feat: report screenshot references …` | same as T1 |
| T4 `fix(api): warn when log retention cannot take effect` | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/api/10-jobgroups.t && COVERAGE=1 make test-unit-and-integration TESTS=t/36-job_group_settings.t && make check-line-coverage && make test-gitlint` |
| T5 `docs: document retention ordering …` | `make test-markdown && make test-checkstyle && make test-gitlint` |
| T7 `feat: add openqa-archive-jobs …` | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/44-scripts-openqa-archive-jobs.t && make check-line-coverage && make test-gitlint` |
| T6a/b/c/d (ops, no commit) | `df -h /results /var/lib/openqa/archive`; `./script/openqa-audit-retention` diff before/after; `select id, state, finished, notes from minion_jobs where task='limit_results_and_logs' order by id desc limit 3` after the next pass; for T6b `select min(t_created), max(t_created) from jobs where not archived` |
| I1/I2/I3 (investigations) | no gate; output is reviewed in this plan and I3 gates T6b |

## Session starter

```
Read tasks/148_poo210483_osd_results_full_distribution_of_test_results.md in full and run
`git status` first. Load the `perl-dev`, `testing`, `openqa` and `git-workflow` skills before
writing code. Work on exactly one task of the plan per session, in this order of readiness:
T1 → T2 → T3 → I1/I2/I3 (in parallel, read-only) → T4 → T5 → T7; T6 only after its rows in
`## Approvals` are filled.

Commit unit for this session: T1 — one commit
`feat: add openqa-audit-retention to report ineffective cleanup settings` on a branch
`feature/148_audit_retention`, adding only `script/openqa-audit-retention` and
`t/44-scripts-openqa-audit-retention.t`, with the T1 acceptance criteria and the T1 gate from
`## Gates`. Do not touch any other file, do not modify the plan file's other sections.

Actions that need explicit confirmation before you run them, every time: any write on OSD
(salt state apply, `UPDATE`/`INSERT` on the production DB, psql as `geekotest` with anything
but `SELECT`, minion enqueues), any `git push`, PR creation or merge, and any deletion
including `git clean`, `rm` of result directories or `archive dirs`. Read-only SQL on OSD was
approved only for the investigations in this plan. Report the findings as numbers with the
query or sample that produced them, and stop after the commit.
```
