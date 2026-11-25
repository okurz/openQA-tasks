# 169: release gate — review vocabulary, carry-over semantics, default actions

Repositories and baselines:
`openQA` `487b5610c` (2026-02-21, `feature/next`) — primary, upstreamable;
`os-autoinst-scripts` `22575395` (2026-11-19); `qem-bot` `5d20ab83` (2026-10-26);
`qem-dashboard` `4fc255e4` (2026-11-18). Branch per task: `feature/169_<slug>`.
External counterpart: OSD `openqa.ini` (salt-managed, not checked out locally).

Scope: make an unreviewed-by-a-human, release-blocking openQA failure visible,
acted on by automation, and structurally reviewable, and stop rewarding the
"commented + ticket ref" action as the terminus of a review. Focus on general
openQA features; the SUSE-only dashboard/bot units are secondary and only where
openQA cannot express them.

Non-goals: short-term unblocking of SMELT 44779 / t25680366 (out of scope, per
okurz); widening qem-bot's approval fallback; fixing the SAP HANA `Stop_site_*`
flake itself (test-code work in os-autoinst-distri-opensuse, separate plan).

## Problem

A not-ok aggregate job blocks maintenance approvals. qem-bot requires the newest
job per scenario in the aggregate to be `passed`/`softfailed`; a bugref or label
in a comment does not unblock (`qem-bot/openqabot/approver.py:456-472`). A human
review comment that is prose plus a ticket reference satisfies openQA's `reviewed`
predicate, so the job leaves every human queue, and satisfies nothing that the
gate or any automation can act on. The result is a blocking failure that is
invisible to humans and inert to machines.

Two predicates do not align:
- openQA `reviewed` = parsed bugref or label in a comment
  (`lib/OpenQA/Schema/ResultSet/Comments.pm:100-131`).
- qem-bot `ok` = newest job per scenario is `passed`/`softfailed`, or an explicit
  `@review:acceptable_for:submission_<n>:<reason>` comment, or an older ok job that
  contains the submission (`approver.py:65,404-425`).

Carry-over makes this structural: the comment of a 2-day-old source job is copied
onto a run no human has examined, the copy counts as reviewed, and the job-done
hook is suppressed (`lib/OpenQA/Schema/Result/Jobs.pm:1826-1840,2244`).

## Findings (2026-11-21, read-only)

Timeline for scenario `sle-15-SP6-Azure-SAP-PAYG-Updates-x86_64-Build20261120-1-SAPHanaSR-angi-ScaleUp-PerfOpt-msi@az_Standard_E4s_v3`:

| job | build | finished | result | notes |
|---|---|---|---|---|
| t25630444 | 20261118-1 | 11-19 05:30 | failed `Stop_site_a-primary` | lpalovsky comment 11-19 08:16: `jsc#TEAM-11552` + `Restart - sporadic issue` |
| t25643204 | clone | 11-19 11:23 | **passed** | restart after the hint: hint validated |
| t25661179 | 20261119-1 | 11-20 05:49 | passed | does not contain 44779 |
| t25677144 | 20261120-1 | 11-21 04:31 | failed `Stop_site_b-primary` | zero comments — hook produced nothing |
| t25680366 | clone (restarted by jalausuch, QE PM, ~5 h before, on a Saturday) | 11-21 09:59 | failed `Stop_site_a-primary` | comment is the 11-19 comment, auto-carried-over, `(The hook script will not be executed.)` |

Scenario history: 16 passes, 5 not-ok in 21 runs (flake ≈ 24 %); the failing
module ran 48 min in both failures. No human has reviewed t25680366.

Gate state: `dashboard.qam.<internal>/api/incidents/44779?project=SUSE:Maintenance:44779&type=smelt`
→ `priority 1000`, `emu true`, `packages ["ruby2.5"]`, `approved false`,
`rejection_reason "smelt:44779 has at least one not-ok job in aggregate tests"`.
`api/jobs/update/257497` (the SAP/HA aggregate for build 20261120-1): 22 jobs,
21 passed/softfailed, exactly one failed — t25680366. The aggregate settings list
85 SLES_SAP + 5 HA + 9 PCM incidents, so one 2 h Azure flake gates ~99 updates.

Why the gate cannot self-heal: 44779 first appears in an aggregate at build
20261120-1 (present in t25677144/t25680366 settings as `Maintenance:/44779/`,
absent in t25661179/t25643204), so qem-bot's `was_ok_before` fallback has no
older ok job to use.

Automation inventory and why each did not fire:

| mechanism | trigger | inert because |
|---|---|---|
| `RETRY=<n>` (`Jobs.pm:2262-2290`) | failed/incomplete/timeout | not set on the scenario |
| `auto_clone_regex` (`lib/OpenQA/Setup.pm:149`) | `incomplete`/`timeout_exceeded` whose `reason` matches | module `failed` with `reason=None` never matches |
| `job_done_hook_failed` → `openqa-label-known-issues` | `auto_review:"…"[:retry[:limit]]` in a **progress** ticket subject (`os-autoinst-scripts/openqa-label-known-issues:269-310,373-388`) | reference is SAP Jira; and carry-over skipped the hook |
| `openqa-investigate`, `openqa-llm-investigate` | same hook | hook skipped; **`openqa-llm-investigate` is not enabled on OSD** (no inference hosts), only o3 |
| LLM verdict `Restart: YES` | none | `verdict.py:92` parses `BISECT` and `openqa-llm-investigate:804-813` gates on it; `Restart` is advisory, no consumer |
| `label:force_result:<result>` (`Comments.pm:150,228`) | operator, `force_result_regex` (`Setup.pm:152`) | not used; cost/risk asymmetry, see Decisions |
| `@review:acceptable_for:submission_<n>:<reason>` (`approver.py:65`) | UI template exists on OSD (`templates/webapi/branding/openqa.suse.de/commenting_tools.html.ep`) | keyed per incident → an aggregate blocking 99 incidents needs 99 markers |
| `openqa-advanced-retrigger-jobs`, `openqa-get-qem-bot-blocking-jobs` | SQL for incompletes / report-only parse of qem-bot CI logs | no rule for "not-ok aggregate blocking a submission" |
| openQA `blocked_by_id` (`Jobs.pm:2364`) | scheduler (parent not done) | unrelated to the release gate |
| restart button / `POST jobs/<id>/restart` (`lib/OpenQA/WebAPI.pm:347,367`) | logged-in user with API key | used twice by humans (t25643204 pass, t25680366 fail); no automation uses it |

## Decisions

1. **Carry-over is a lead, not a verdict.** A carried-over comment must not mark a
   job as reviewed. Carried-over text matches only the failed-module signature,
   never the ticket's failing step, so it claims a verdict for a run no human read.
   Effect: the job stays in `todo` sweeps, the group overview, `openqa_review`,
   notifications. It does **not** unblock — blocking is correct; the point is
   visibility, hook execution, and not rewarding a copy as a review.
2. **The hook runs unless the carried comment is actionable.** Suppressing the hook
   on carry-over is only defensible when the carried comment contains a
   machine-actionable decision (`label:force_result`, `flag:restart`,
   `@review:acceptable_for`). Today it is suppressed unconditionally.
3. **Do not widen qem-bot's fallback to "sibling scenarios passed".** Rejected by
   okurz: a different test scenario is not evidence for this one; a product update
   must not be released because other tests passed. `was_ok_before` stays
   per-scenario.
4. **`flag:restart` is an automation input, not a human shortcut.** The restart
   button and `POST jobs/<id>/restart` already exist for a logged-in reviewer
   (twice used in this incident). A flag's value is that intent is recorded in the
   comment, executed by the hook/cron with a bounded budget, and traced by a system
   comment naming the rule that fired.
5. **`label:force_result` stays the sanctioned waiver.** Reviewers own flaky
   scenarios and must use it; requiring a release manager's written agreement is
   not scalable. Keep it, structure it, and make the second party the automation:
   a recorded failed restart attempt is the witness, quoted in the waiver comment.
   `@review:acceptable_for` is the *scoped, auditable* alternative (per submission
   or per aggregate; result stays truthful in openQA, group stats, badges,
   history, and the dashboard remark); `force_result` rewrites the result for every
   consumer, all submissions, permanently, and cannot be deleted. It is not
   equivalent, and the scoped marker is the direction for the gate side.
6. **Act, then notify.** Personal nudges and "kind words" have not worked; telling
   people how to do their job generates resentment. The default action executes
   immediately and a group owner gets an asynchronous message; the human role
   becomes veto, not action.
7. **Make the machine independent of ticket content.** The SAP QE group can read
   `jsc#`; the gate and other users cannot, and that is not going to change. So the
   vocabulary and the default actions must be executable without reading the
   ticket. Tracker accessibility stays a lint warning, not a gate.
8. **Fix the incentive, not the person.** The reward that produced this behaviour
   is "reviewed". Publishing flake rates and ticket age per scenario, per
   maintainer, is the counter-measure; QA engineers are not going to fix flakes
   while reviewing them counts as success.
9. **Impact ranking (okurz).** openQA features first (all instances, more
   workflows): carry-over semantics, review vocabulary, `flag:restart`, structured
   force_result, external gate plugin, flake reporting. qem-dashboard second
   (SUSE, maintenance only): blocking queue, oldest-per-group, group owner, the
   read-only `api/jobs/<id>/blocking` endpoint that the openQA plugin consumes.
   qem-bot third: the aggregate-scoped marker. Prefer openQA units that subsume a
   dashboard need.

## Rejected options

| option | why rejected |
|---|---|
| qem-bot accepts a passing sibling scenario with the same REPOHASH (t25677156) as proof for 44779 | different scenario; not evidence; okurz veto |
| Stricter carry-over (`state_changes_limit` 3 → 1) alone | the job stays blocked and the comment disappears; no benefit without tasks 1–2 |
| `flag:restart` as a UI button replacement | the restart button already exists |
| Waiver requires release manager's written agreement | not scalable, not feasible |
| Mirror `jsc#` into `poo#` as the fix | obvious to us, not to the group; not applicable as a process change; keep as lint warning only |

## Tasks

Ordered by readiness; one commit per task, conventional commits, hard-wrapped at 80.

**T0 — ticket (openQA, progress).** File `poo#<n>` "Release gate: unreviewed
blocking aggregate failures stay invisible" referencing this plan; AC as in
`## Decisions`. A write; gated on okurz.

**T1 — openQA: carried-over comments do not count as reviewed.**
Files: `lib/OpenQA/Schema/Result/Comments.pm` (`is_carried_over`, text marker
`(Automatic carryover from t#`), `lib/OpenQA/Schema/ResultSet/Comments.pm:100-131`
(`comment_data_for_jobs`: carried-over comment sets `comments`, not `reviewed`),
`lib/OpenQA/Schema/Result/Jobs.pm:2425` (`should_skip_review` inherits the change),
`lib/OpenQA/BuildResults.pm:69,82,168`.
AC1: a job whose only comment is an automatic carry-over appears in `todo=1`
overview and is not counted as `labeled` in the build result.
AC2: a human comment, a carried-over comment plus a human comment, and
`flag:carryover` behaviour stay as today.
AT: extend `t/17-labels_carry_over.t`, `t/10-tests_overview.t`, `t/api/09-comments.t`.

**T2 — openQA: run the job-done hook on carry-over when the carried comment is not
actionable.** Files: `lib/OpenQA/Schema/Result/Jobs.pm:1765` (`hook_script`),
`1826-1840` (`carry_over_bugrefs`), `2244-2256` (finalize opts),
`lib/OpenQA/Schema/Result/Comments.pm` (`is_actionable`: `force_result`,
`flag:restart`, `@review:acceptable_for`, group vocabulary match from T3).
AC1: carry-over with a prose/bugref-only comment runs the hook and the "will not be
executed" marker is not emitted.
AC2: carry-over with an actionable comment keeps today's behaviour.
AT: extend `t/17-labels_carry_over.t` (hook invocation asserted on the queue).

**T3 — openQA: per-group review vocabulary.** Files:
`lib/OpenQA/Schema/Result/JobGroups.pm` (new `review_keyword_regex`,
`is_nullable => 1`), `dbicdh/PostgreSQL/{deploy,upgrade}` + `dbicdh/_source`,
`lib/OpenQA/WebAPI/Controller/API/V1/JobGroup.pm` (validation),
`lib/OpenQA/WebAPI/Controller/API/V1/Comment.pm` (comment creation: when the group
has a vocabulary and the comment has a bugref/label that does not match it, the
comment is created and the response states it does not count as reviewed; a
non-matching comment never sets `reviewed` in `comment_data_for_jobs`),
`templates/webapi/comments/add_comment_form_groups.html.ep` (list the group's
keywords as insert templates), OSD branding template for the accepted tracker
prefixes.
AC1: on a group with `review_keyword_regex = 'label:(flaky|known_issue)|flag:restart|@review:acceptable_for'`,
`jsc#TEAM-11552\nRestart - sporadic issue` leaves the job unreviewed and the UI
names the required vocabulary.
AC2: groups without the setting behave exactly as today.
AT: `t/api/10-jobgroups.t`, `t/api/09-comments.t`, `t/17-labels_carry_over.t`.

**T4 — openQA: `flag:restart` as machine-readable restart intent.** Files:
`lib/OpenQA/Utils.pm` (flag parsing is generic; add a documented keyword),
`lib/OpenQA/Schema/Result/Comments.pm` (`restart_request`), the comment form
template (template button), `docs/`, `OpenQA::Markdown` flag highlighting.
AC1: `flag:restart` is parsed, rendered, and exposed via the comments API
(`lib/OpenQA/WebAPI/Controller/API/V1/Comment.pm` response gains the flags).
AT: `t/api/09-comments.t`, `t/16-markdown.t`.

**T5 — os-autoinst-scripts: `openqa-act-on-failure` default action hook.** Files:
new `openqa-act-on-failure`, `config/openqa-act-on-failure.yaml` (per group regex:
`restart_budget`, `flake_pass_rate_min`, `streak_max`, `notify: chat|mail`),
`tests/test_openqa_act_on_failure.py`, `systemd/` unit, README section.
Behaviour on a not-ok job in a release-gating group: classify with the scenario
history (`/tests/<id>/ajax`, as qem-bot's `get_older_jobs`);
infra `reason` match → restart; flaky (pass rate ≥ min, streak ≤ `streak_max`,
`ancestors < budget`) → restart; deterministic (same failed module in ≥ `streak_max`
consecutive runs of the same build) → do not restart, file a ticket assigned to the
module maintainer, keep blocked. Every action posts a system comment naming the
rule and the budget; the group owner is notified asynchronously via `chat_notify.sh`.
AC1: for t25680366's shape (flake rate 24 %, streak 2, budget 2) the hook restarts
and comments; on the third consecutive failure it stops and files the ticket.
AC2: no action for groups not matching the config.
AT: pytest cases per class, restart bounded, comment text asserted, dry-run.

**T6 — os-autoinst-scripts: consume `Restart: YES`.** Files:
`openqa_llm_investigate/verdict.py` (reuse the parser), `openqa-llm-investigate`
(gate the restart after the verdict), `openqa-act-on-failure` (same budget
function), tests in `tests/test_llm_investigate_verdict.py`,
`tests/test_openqa_act_on_failure.py`.
AC: `Restart: YES` triggers the bounded restart path, `Restart: NO` never restarts,
and the system comment quotes the verdict. Note: not active on OSD until the LLM
hook has inference hosts; the code path is exercised by the hook config for o3 and
by unit tests.

**T7 — openQA: structured force_result.** Files: `lib/OpenQA/Schema/Result/Comments.pm`
(`force_result` description validation: require a non-empty reason and a tracker
reference), `lib/OpenQA/Setup.pm:152` (document `force_result_regex`), docs.
OSD ops (separate, gated): set `force_result_regex` to require
`flaky_<poo#NNNN>`-style reasons, and grant the operator role to the QE reviewers
who own flaky scenarios.
AC1: `label:force_result:softfailed` without a reason is rejected (HTTP 400),
`label:force_result:softfailed:flaky_poo#210999` is accepted.
AT: `t/api/09-comments.t`.

**T8 — openQA: flake report and flake ownership.** Files: `script/openqa-flaky-report`,
`t/44-scripts-openqa-flaky-report.t`, group overview column (flaky rate = passes /
runs over N runs, restart count from `ancestors`) in
`lib/OpenQA/WebAPI/Controller/Test.pm` / `BuildResults.pm`, docs.
AC1: the report lists scenarios in release-gating groups with pass rate < X % over
N runs, newest failure, restart count, and the module's declared maintainer
(os-autoinst-distri-opensuse `Maintainer:` header).
AC2: a ticket per scenario, auto-filed, assigned, with job links; ticket age is the
published KPI.
AT: unit test with fixture jobs; coverage for the new lines.

**T9 — qem-dashboard: blocking queue and gate read API.** Files:
`lib/Dashboard/Model/Incidents.pm` (`blocking_for_job`),
`lib/Dashboard/Controller/API/Jobs.pm` (`GET /api/jobs/<id>/blocking` returning
submission key, priority, severity, age, `rejection_reason`), group owner column +
`PageBlocked.vue`/`PageSubmission.vue` oldest-per-group display,
`t/lib/Dashboard/Test/APICommon.pm` and `t/` tests, `docs/API.md`.
AC1: `GET /api/jobs/25680366/blocking` returns `SUSE:Maintenance:44779` with
priority 1000, emu, age.
AC2: the blocked page shows oldest blocking per group and the tracker prefix of the
job's reference.

**T10 — openQA: external gate plugin.** Files: config section `[external_gate]`
(`url`, `api_key`, `jobs_blocking_path`) in `lib/OpenQA/Setup.pm` and
`etc/openqa/openqa.ini` (commented default), a helper in
`lib/OpenQA/WebAPI/Plugin/Helpers.pm`, branding template
`templates/webapi/branding/openqa.suse.de/gate_info.html.ep`, comment form
integration, `t/` test with a mocked gate endpoint.
AC1: a not-ok job in a gated group shows "blocks N submissions (highest priority
1000, EMU, oldest 2 d)" on the job page and in the comment form.
AC2: the comment form prefills `@review:acceptable_for:submission_<n>:` from the
job's `*_TEST_ISSUES` settings.
AC3: instances without the config show nothing extra.

**T11 — qem-bot: aggregate-scoped waiver.** Files:
`openqabot/approver.py` (`ACCEPTABLE_FOR_TEMPLATE`,
`mark_jobs_as_acceptable_for_submission`, `is_job_acceptable`),
`tests/test_approve_unblock.py`, `tests/test_approve_helpers.py`.
Marker: `@review:acceptable_for:aggregate_<update_settings_id>:<reason>` waives the
not-ok job for every submission in that aggregate; the dashboard remark is recorded
as today.
AC1: one comment on t25680366 clears 44779 and the rest of the aggregate's
submissions; per-submission markers keep working.
AC2: the marker never applies to a submission outside the aggregate.

**T12 — docs.** openQA `docs/` (review vocabulary, carry-over semantics,
force_result, external gate), `os-autoinst-scripts/README.md` (default action
policy, budgets), `qem-dashboard/docs/API.md`. Keep the SAP/QE convention (gate
vocabulary, restart budget, `force_result` witness) in the site policy overlay,
not in code.

## Risks

- T1 enlarges every human review queue on OSD (the 232 maintenance groups).
  `openqa_review` and `oqa-sweep --todo` will list jobs that today look reviewed.
  Roll out on one parent group first and measure the delta.
- T3 makes a review silently non-counting. The UI must state, on the comment and in
  the overview, that the comment did not count, otherwise the reviewer is blocked
  without knowing it.
- T5 spends worker time (the SAP aggregate job is ~2 h on 2 Azure VMs). Budgets must
  be per group, `Development*` groups must be excluded (as
  `openqa-investigate`'s `DEFAULT_EXCLUDE_GROUP_REGEX`), and the hook must be
  idempotent against restart storms.
- T11 increases the blast radius of one comment (one marker waives ~99 submissions):
  the reason string is mandatory and recorded in the dashboard remark.
- T7 must not break `openqa-label-known-issues`'s `:force_result:<result>` path,
  which posts labels without a `flag:carryover` witness.
- T8's auto-filed tickets need a target project and a stable subject prefix;
  duplicated tickets per scenario are the failure mode.

## Open questions

- Who owns the keyword vocabulary per group: the group owner, or the site policy?
- Does `flag:restart` restart dependencies (parents/children) with the default
  dependency semantics, or the flagged job alone (`skip_parents=1`)?
- Budget unit: restarts per group per day, or worker-hours?
- Flake window: last 21 runs (openQA's carry-over depth) or last 30 days?
- Target project and assignee rules for auto-filed flake tickets.

## Approvals

| Decision | Approver | Date |
|---|---|---|
| Facts: `openqa-llm-investigate` is not enabled on OSD (no inference hosts); other os-autoinst-scripts hooks are; t25680366 was restarted manually by jalausuch (QE PM) on a Saturday | okurz | 2026-11-21 |
| Short-term unblock of SMELT 44779 / t25680366 is out of scope | okurz | 2026-11-21 |
| Rejected: qem-bot accepting a passing sibling scenario with the same REPOHASH as proof | okurz | 2026-11-21 |
| Rejected: stricter carry-over (`state_changes_limit`) as a standalone measure | okurz | 2026-11-21 |
| `label:force_result` stays the sanctioned waiver; no written release-manager agreement; reviewers with flaky scenarios need the operator role | okurz | 2026-11-21 |
| `flag:restart` is an automation input, not a replacement of the restart button | okurz | 2026-11-21 |
| Direction: act automatically, notify group owners asynchronously; personal nudges do not work | okurz | 2026-11-21 |
| SAP Jira access asymmetry accepted as a fact; vocabulary and default actions must not depend on ticket content; keep the tracker lint as a warning | okurz | 2026-11-21 |
| Impact ranking: openQA > qem-dashboard > qem-bot/downstream; prefer openQA units that subsume dashboard needs | okurz | 2026-11-21 |
| KPI change (flake rate and ticket age per scenario/maintainer) as the counter-measure to "reviewed" as success | okurz | 2026-11-21 |
| Carry-over semantics change (T1/T2) accepted as upstream work | pending | – |
| Plan approved for implementation as written | pending | – |
| T0 ticket filed on progress | pending | – |
| T7 OSD writes (`force_result_regex`, operator grants) | pending | – |
| T5 deployment as `job_done_hook_failed` on OSD | pending | – |

## Gates

openQA (repo rule): `make tidy && make test-checkstyle` before each commit;
`COVERAGE=1 make test-unit-and-integration TESTS=<file>` then
`make check-line-coverage` for every new/changed line; `make test-gitlint` after
the commit exists.

| Task | Commit | Verification |
|---|---|---|
| T1 | `fix: carried-over comments do not count as reviewed` | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/17-labels_carry_over.t && COVERAGE=1 make test-unit-and-integration TESTS=t/10-tests_overview.t && make check-line-coverage && make test-gitlint` |
| T2 | `feat: run the job done hook on carry-over without an actionable comment` | as T1, plus `t/api/09-comments.t` |
| T3 | `feat: add per-group review keyword vocabulary` | as T1, plus `t/api/10-jobgroups.t`; migration checked with `make test-unit-and-integration TESTS=t/06-users.t` (schema deploy) |
| T4 | `feat: add flag:restart as machine-readable restart intent` | as T1, plus `t/16-markdown.t` |
| T7 | `feat: require a reason for force_result labels` | as T1 with `t/api/09-comments.t` |
| T8 | `feat: report flaky scenarios with their module maintainer` | as T1 with `t/44-scripts-openqa-flaky-report.t` |
| T10 | `feat: show release gate blocking submissions on the job page` | as T1 with the new mocked-gate test |
| T12 | `docs: document review vocabulary, carry-over and the external gate` | `make test-markdown && make test-checkstyle && make test-gitlint` |
| T5/T6 | `feat: add openqa-act-on-failure default action hook` / `feat: act on the Restart verdict` (os-autoinst-scripts) | `make checkstyle && make test-with-coverage && make test-gitlint` |
| T11 | `feat(approver): support aggregate-scoped acceptable_for marker` (qem-bot) | `make checkstyle && make test-unit && make test-gitlint` |
| T9 | `feat(api): report blocking submissions per job` (qem-dashboard) | `make tidy && make test-unit && make test-js-unit` |
| Ops (no commit) | OSD salt-managed `openqa.ini`, operator grants, hook deployment | read-only verification with the actor that runs at boot: `systemctl show openqa-wa ...`; `ssh osd 'sudo -n -u geekotest psql openqa -c "select id,task,state,finished from minion_jobs order by id desc limit 5"'`; hook run visible as the system comment on the job |

## Blocked

- T0: needs okurz's approval of the ticket body (write on progress). Verify: read the
  ticket back with `scripts/` in the `redmine` skill, date recorded when done.
- T5, T7 ops, T9, T11: need a production window and okurz's approval for OSD
  writes (`openqa.ini` is salt-managed, `salt-states-openqa` is not checked out
  locally). Verify with the boot actor per `## Gates`.
- T6: gated on OSD inference hosts for `openqa-llm-investigate`. Read-only check:
  `ssh osd 'ls /etc/openqa-scripts/ | grep llm'` plus the hook config; record the
  date.
- T3 vocabulary values: gated on the group owners' decision (open question above).

## Session starter

```
Read tasks/169_release_gate_review_vocabulary_and_default_actions.md in full, run
`git status` first, and confirm the openQA baseline is 487b5610c. Load the `perl-dev`,
`testing`, `openqa`, `git-workflow` skills, and `colgrep` for locating the review
predicate. Work on exactly one task per session in this order: T1 → T2 → T3 → T4 →
T10 → T8 → T5 → T11 → T9 → T7 → T12.

Commit unit for this session: T1 — one commit
`fix: carried-over comments do not count as reviewed` on branch
`feature/169_carryover_not_reviewed`, changing only
`lib/OpenQA/Schema/Result/Comments.pm`,
`lib/OpenQA/Schema/ResultSet/Comments.pm`,
`lib/OpenQA/Schema/Result/Jobs.pm`, `lib/OpenQA/BuildResults.pm` and
`t/17-labels_carry_over.t` (+ `t/10-tests_overview.t`), with T1's AC1/AC2, the T1
gate from `## Gates`, `COVERAGE=1` and `make check-line-coverage` clean.

Do not touch the plan file's other sections. Actions needing explicit confirmation
every time: any write on OSD (salt, DB, openqa.ini, operator grants), any job
comment/restart, any ticket on progress.
