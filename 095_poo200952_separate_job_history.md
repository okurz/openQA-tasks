# Plan: Separate openQA job history for independent PRs

Related issues:

- https://progress.opensuse.org/issues/200952 (o3+osd production rollout)
- https://progress.opensuse.org/issues/200985 (spike solution, timeboxed 20h, size:M)

## Context and Motivation

openQA groups jobs into a scenario history by comparing a fixed set of DB
columns, `SCENARIO_WITH_MACHINE_KEYS = (DISTRI VERSION FLAVOR ARCH TEST MACHINE)`
(`lib/OpenQA/Schema/Result/Jobs.pm:47`). Three separate features build on this
grouping via `_previous_scenario_jobs` (`Jobs.pm:1673`):

- **Bugref carry-over:** `carry_over_bugrefs` / `_carry_over_candidate`
  (`Jobs.pm:1773` / `:1724`).
- **Investigation tab:** `Jobs.pm::investigate` (`:1933`) picks `last_good` by
  walking `_previous_scenario_jobs`. (The `openqa-investigate` retrigger bot
  lives in the separate `os-autoinst/scripts` repo and is out of scope here.)
- **Next & Previous:** `ResultSet::Jobs::next_previous_jobs_query`
  (`ResultSet/Jobs.pm:573`) via controller `Test::job_next_previous_ajax`
  (`Controller/Test.pm:724`).

Because all three share `SCENARIO_WITH_MACHINE_KEYS`, independent submissions
(e.g. different PRs) with identical scenario keys are treated as consecutive
builds. This causes wrong bugref carry-over, wrong "last good build" in
investigation, and cluttered "Next & Previous" lists.

**The `VERSION` hack problem.** To force separation, squads overload `VERSION`
(e.g. `VERSION=16.1:PR-5466`), as in
[os-autoinst-distri-opensuse#26053](https://github.com/os-autoinst/os-autoinst-distri-opensuse/pull/26053).
Because `VERSION` is a first-class scenario key, this separates the history but
pollutes the version string that test code expects to be "proper" (e.g. `16.1`),
forcing modules to strip everything after the colon. We want the separation
without polluting core scenario keys.

**Open questions from the tickets (must be resolved before/with the code).**
Per poo#200952 AC1/AC2 and poo#202533#note-20, separation is NOT universally
wanted: the dashboard and possibly "Next & Previous" should keep the single,
generalized history. So the mechanism must be opt-in per feature, not a global
change to the scenario definition.

## Design Direction

Introduce an opt-in set of extra history-separation keys, sourced from job
settings (the `job_settings` key/value table,
`lib/OpenQA/Schema/Result/JobSettings.pm`) rather than from a new hard scenario
column. A job setting `_HISTORY_ISOLATION_KEYS=PR_ID` names additional
job settings whose values must also match for two jobs to share an isolated
history. Core `SCENARIO_WITH_MACHINE_KEYS` and `scenario_name` stay unchanged, so
`VERSION` remains pristine and the dashboard/glossary "scenario" definition is
preserved (poo#200985 G2/G3).

Each consuming feature decides independently whether to apply the isolation
keys, satisfying AC1/AC2 (carry-over and investigation opt in; dashboard does
not; "Next & Previous" exposes both views via a UI toggle).

Storage decision to make in Task 1: whether matching on `job_settings` rows is
fast enough or whether a denormalized helper (e.g. an indexed column or a
computed isolation hash) is needed. Decide with a query-cost check before
committing to schema changes.

### Naming: the leading underscore

The setting is named `_HISTORY_ISOLATION_KEYS` with a leading underscore. The
underscore prefix is openQA's reserved namespace for settings meaningful to
openQA itself and not consumed by the os-autoinst test run
(`docs/UsersGuide.md:1277`). It already covers two kinds: schedule/clone-time
controls that are stripped before the run (`_OBSOLETE`, `_GROUP`, `_PRIORITY`)
AND persisted meta-settings openQA reads at runtime (`_TRIGGER_JOB_DONE_HOOK`
at `Jobs.pm:1714`, `_HIDE_SECRETS_REGEX` at `Log.pm:219`,
`_PRIORITY_EXPLANATION` at `Test.pm:402`). There is no blanket rule that strips
all underscore keys; `_build_job_settings` (`ResultSet/Jobs.pm:124`) does no
filtering, so persisted underscore settings land in `job_settings` normally.

`_HISTORY_ISOLATION_KEYS` belongs to the persisted-meta group: it must survive
into `job_settings` because carry-over, investigation, and "Next & Previous"
read it long after scheduling, and it is never relevant to a test module. This
matches `_TRIGGER_JOB_DONE_HOOK` / `_HIDE_SECRETS_REGEX` exactly. Note the
underscore is NOT reserved for scheduling-only parameters — that narrower
reading contradicts the existing persisted-meta settings, so we do not adopt it.

The keys it _names_ (e.g. `PR_ID`) are ordinary, test-visible settings without
an underscore. Only the meta-setting pointing at them carries the prefix.

---

## Atomic Task Breakdown

Each task is an independent, separately committable unit with its own tests.

### Task 1: Backend primitive for history-isolation keys

**Goal:** A reusable way to compute whether two jobs belong to the same
_isolated_ history, driven by the `_HISTORY_ISOLATION_KEYS` job setting.

**Model as a key-set, not a boolean.** The primitive takes an explicit _subset_
of isolation keys to apply, where the empty set means fully generalized (today's
behavior) and the full declared set means fully strict. A boolean toggle is just
these two ends. Designing the API around a key-set from the start avoids a
rewrite when per-key selection (see "Anticipated follow-up requirements") lands.

- Add a helper on `lib/OpenQA/Schema/Result/Jobs.pm` (near `scenario_hash`,
  `:303`) that reads `settings_hash`, resolves the declared
  `_HISTORY_ISOLATION_KEYS`, and returns the key/value pairs for a requested
  subset of those keys.
- Extend `_previous_scenario_jobs` (`:1673`) to accept an isolation key-set and
  add the corresponding key/value constraints (via `job_settings` join). An
  empty/omitted set must keep behavior byte-for-byte identical.
- Decide storage: benchmark a `job_settings` self-join vs. a denormalized hash.
  Document the choice in the commit body.
- **Tests:** unit tests in `t/` covering: equal-scenario jobs split when a
  differing isolation key is applied; merged when the key matches; a subset of
  keys applied independently (e.g. isolate on `PR_ID` only while ignoring
  `PACKAGE_TESTED`); and the empty-set path unchanged.

### Task 2: Apply isolation to bugref carry-over

**Goal:** poo#200985 G1 — jobs of independent PRs are not carry-over candidates.

- Make `_carry_over_candidate` (`Jobs.pm:1724`) pass the job's full declared
  isolation key-set into `_previous_scenario_jobs`. Gate on the job actually
  setting `_HISTORY_ISOLATION_KEYS` so existing groups are unaffected.
- **Tests:** integration test proving a bugref on `PR_ID=100` is not carried
  over to `PR_ID=101` while all `SCENARIO_WITH_MACHINE_KEYS` match; and that
  carry-over still works when no isolation keys are set.

### Task 3: Apply isolation to the Investigation tab

**Goal:** `last_good` reflects the isolated history, not an unrelated PR.

- Update `Jobs.pm::investigate` (`:1933`) and `should_show_investigation`
  (`:2331`) to use the isolated `_previous_scenario_jobs` when the job sets
  isolation keys.
- **Tests:** test coverage that `investigate` picks the isolated `last_good`
  and `first_bad`; unchanged behavior without isolation keys.

### Task 4: "Next & Previous" strict vs. generalized UI toggle

**Goal:** Let users switch between the strict isolated history (e.g. same PR) and
the generalized history (all PRs sharing the base scenario), without changing the
default dashboard behavior (poo#200952 suggestions, poo#202533#note-20).

The initial UI surface is a boolean toggle, but it is rendered over the Task 1
key-set model (empty set vs. full declared set), so the per-key UI in the
follow-up section can replace the toggle without backend changes.

- **Backend:** add an optional query arg to
  `ResultSet::Jobs::next_previous_jobs_query` (`ResultSet/Jobs.pm:573`) and
  `Controller::Test::job_next_previous_ajax` (`Controller/Test.pm:724`).
  Accept a key-set-shaped arg (e.g. `isolation_keys=PR_ID,PACKAGE_TESTED`, with
  the boolean toggle mapping to empty vs. full set) rather than a bare
  `strict=1`, forwarding to the Task 1 isolation path. Choose the default view
  deliberately per AC1 (likely generalized to match today). Reflect the choice
  in the URL query so views are bookmarkable/shareable.
- **Frontend (jQuery + DataTables, not Vue):** add a toggle in
  `templates/webapi/test/job_next_previous.html.ep` and wire it in
  `assets/javascripts/job_next_previous.js` to re-request the AJAX endpoint
  with the chosen mode and reload the DataTable.
- **Tests:** controller test for both modes returning the expected job sets; a
  UI/JS test (existing `t/ui/` Selenium harness) validating the toggle switches
  datasets.

### Task 5: Documentation and migration off the `VERSION` hack

**Goal:** Resolve the "proper version string" regressions
(os-autoinst-distri-opensuse#26053) by giving squads the isolation mechanism.

- Document `_HISTORY_ISOLATION_KEYS` in the openQA docs alongside the other
  underscore meta-settings in `docs/UsersGuide.md` (near line 1277), including
  the relation to the glossary "scenario" definition (poo#200985 suggestion to
  review it).
- Provide a migration recipe for `os-autoinst-distri-opensuse` /
  `opensuse-jobgroups` / `qam-openqa-yml`: keep `VERSION=16.1` pristine, pass
  `PR_ID=<n>` plus `_HISTORY_ISOLATION_KEYS=PR_ID`, and drop the colon-stripping
  workarounds. (Changes to those external repos are out of this repo's scope;
  reference them so the rollout task poo#200952 can track them.)
- **Tests:** none in this repo beyond doc build; the validation is that the
  external repos can remove their version-string workarounds.

---

## Anticipated follow-up requirements

A binary strict/generalized toggle will not survive real usage. These are the
predictable escalations; the key-set model in Tasks 1 and 4 is chosen so they
land without reworking the schema/API:

1. **Per-key selection.** Isolate on a subset, e.g. "all PRs but only this
   package" (`PR_ID` off, `PACKAGE_TESTED` on). Requires the UI to expose the
   active isolation keys as a multi-select — already supported by the Task 1
   key-set API; only the Task 4 UI needs extending.
2. **Per-feature key-sets.** Carry-over strict while "Next & Previous"
   generalized at the same time — different key-sets per feature, not one global
   mode. The per-feature opt-in already allows this.
3. **Persisted default / group-level policy.** Set the default isolation per job
   group (analogous to the `carry_over_bugrefs` column on `JobGroups.pm:91`) so
   users need not re-select each visit.
4. **Shareable state.** URL query args (`isolation_keys=...`) so deep-linked
   "Next & Previous" views reproduce exactly — addressed in Task 4.
5. **Key discoverability.** The UI must show which isolation keys a given
   scenario actually has values for, rather than a hardcoded list.

## Sequencing and Scope Notes

- Task 1 is a prerequisite for Tasks 2–4. Tasks 2, 3, 4 are mutually
  independent once Task 1 lands.
- poo#200985 is the timeboxed (20h, size:M) **spike**: Tasks 1–3 (+ a minimal
  slice of 4) form its scope, aiming to prove G1–G4 on the carry-over first.
- poo#200952 is the broader **rollout**: it depends on AC1/AC2 answers from test
  squads before Task 4's default and Task 5's migration are finalized. Do not
  change squad-facing defaults until those answers exist.
- Before implementing Task 4's default view or any dashboard behavior, confirm
  with squads (AC1) — current evidence (poo#202533#note-20) suggests the
  generalized/single history is wanted there.
