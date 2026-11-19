# Task 122: Complete Test Setting Lifecycle Management (poo#207561 follow-up)

Related issue: https://progress.opensuse.org/issues/207561
Predecessor: `tasks/122_207561_deprecation_lifecycle_management_for_test_settings.md`,
implemented in commit `5925eb50b feat(settings): support test settings lifecycle`.

## Current state (after 5925eb50b)

- `[job_settings_lifecycle]` in `openqa.ini`, rule format
  `KEY:PATTERN:LEVEL[:PRIO]:EXPLANATION`, parsed by
  `OpenQA::JobSettings::Lifecycle` and cached in the config hash.
- `warning`/`error` matches rendered on test details (settings tab alert,
  per-key badge, badge on tab header).
- `error` level rejects machine/product/test-suite updates
  (`API::V1::Table::_prepare_settings`) and job template YAML updates
  (`ResultSet::JobTemplates::create_or_update_job_template`).
- Optional prio adjustment hooked into `Jobs::_apply_prio_throttling`.

## Lifecycle model

The complete lifetime of a test setting:

| Phase                 | Meaning                                                                         | Supported today                                     |
| --------------------- | ------------------------------------------------------------------------------- | --------------------------------------------------- |
| 1. Introduced         | New key/value becomes known, documented, maybe experimental                     | no                                                  |
| 2. Active             | In use; admins/test devs need to know where and how often                       | partially (`/api/v1/job_settings/jobs`, jobs only)  |
| 3. Deprecated         | Still works, users warned, optionally de-prioritized                            | yes, but only on definition routes and test details |
| 4. Obsolete           | Must not be used anymore, new usage rejected                                    | only on definition routes, **not on job creation**  |
| 5. Migrated / aliased | Old key/value transparently mapped to replacement                               | no                                                  |
| 6. Removed            | All stored definitions cleaned up, rule kept to block reintroduction or dropped | no tooling                                          |

## Gap analysis

### Correctness gaps in the existing implementation (fix first)

1. **Job creation paths are not covered.** Most settings reach openQA via
   `POST /api/v1/isos` (`ScheduledProducts::_generate_jobs` /
   `_create_jobs_in_database`), `POST /api/v1/jobs` (`API::V1::Job::create`)
   and `openqa-clone-job` (which uses `POST /api/v1/jobs`). None of them
   report warnings or reject `error` level settings. This is the primary use
   case from poo#200075 (settings submitted by external tooling), so AC3 is
   effectively only half-fulfilled.
2. **Silent misconfiguration.** Rules with invalid regex or wrong format are
   skipped via `next` without logging; unknown levels are accepted silently.
   The regex cannot contain `:` because of the separator. Existing
   `_load_throttling_patterns` in `OpenQA::Setup` logs format errors; lifecycle
   rules should behave the same.
3. **Duplication.** `parse_lifecycle_rules` + `check_settings` +
   "worst level" computation is repeated in `Test::settings`, `Test::_show`,
   `Table.pm`, `JobTemplates.pm`, `Jobs.pm`, each with `require`. Should be a
   single entry point (e.g. `lifecycle_matches($config, $settings)` plus a
   Mojolicious helper).
4. **No real UI test.** Predecessor Task 3 claims UI coverage, but only
   controller stash is tested in `t/job_settings_lifecycle.t`; nothing in
   `t/ui/18-tests-details.t` renders the alert/badge in a browser.
5. **No user/admin documentation** in `docs/Installing.md` (only an `ini`
   comment), unlike `prio_throttling_patterns` (`docs/Installing.md:735`).

### Missing lifecycle features

6. **Phase 3→4 transition over time.** Rules have no "since"/"sunset" date.
   Admins must remember to flip `warning` to `error`. A sunset date that
   auto-escalates makes announced deadlines enforceable and visible
   ("will be rejected after 2026-12-01").
7. **Phase 5 migration/aliasing.** No way to declare a replacement
   (`OLD_KEY` → `NEW_KEY`, or value rewrite). With a replacement, openQA can
   (a) show the concrete fix in the explanation and (b) optionally rewrite at
   job creation so external tooling does not break on day one.
8. **Phase 2 usage visibility.** No way to answer "where is `KEY` (matching
   rule X) still used?" across machines, products, test suites, job templates
   and recent jobs. Required to decide whether a setting can be removed.
9. **Phase 6 removal tooling.** No bulk cleanup of stored definitions
   (dry-run + apply, audit-logged), so admins resort to manual DB/YAML edits
   as in poo#200075.
10. **Rule discoverability for clients.** Rules are only in the server
    config. `openqa-cli`, `openqa-clone-job`, `openqa-validate-yaml`,
    `openqa-load-templates` and external schedulers (e.g. qem-bot, openQABot)
    cannot validate before submission. Needs a read-only API route.
11. **Observability.** No aggregated view of how many jobs per rule are
    scheduled; no admin page listing active rules; no audit events for
    rejected submissions.
12. **Phase 1 introduction / unknown settings** (discuss, see "Out of scope /
    critique").

## Atomic tasks

Each task is independently implementable and committable in the given order;
later tasks depend only on T1 where noted.

### T1: refactor: single lifecycle entry point

- Add `OpenQA::JobSettings::Lifecycle::lifecycle_matches($config, $settings)`
  returning matches plus `worst_level($matches)`; add helper
  `lifecycle_matches` in `OpenQA::WebAPI::Plugin::Helpers`.
- Replace the duplicated blocks in `Test.pm` (`settings`, `_show`),
  `Table.pm`, `JobTemplates.pm`, `Jobs.pm`; load the module with `use` once.
- Tests: adapt `t/job_settings_lifecycle.t` (data-driven table for
  `worst_level`), existing API tests must stay green unchanged.
- Commit: `refactor(settings): deduplicate lifecycle rule evaluation`.

### T2: fix: validate and log lifecycle rule configuration

- In `OpenQA::Setup` (like `_load_prio_throttling`) parse rules at startup and
  `log->warn` on invalid format, invalid regex and unknown level (allowed:
  `info`, `warning`, `error`).
- Support escaping `\:` in the pattern (or document limitation explicitly);
  keep explanation free-form.
- Tests: `t/job_settings_lifecycle.t` data-driven cases for each invalid
  input asserting the logged warning (`combined_like`) and that valid rules
  still load; `t/config.t` for defaults.
- Commit: `fix(settings): warn about invalid lifecycle rules`.

### T3: feat: lifecycle checks on job creation (`POST /api/v1/jobs`, clone)

- In `API::V1::Job::create`/`_create_job`: collect matches of final settings;
  `error` → reject job with 400 and explanation; `warning` → add to response
  `warnings` array (existing pattern in `Job.pm:896` for restart).
- Record matches in a job comment or `throttling_info`-like note? Decide:
  prefer response warnings only, no DB change.
- `openqa-clone-job` / `openqa-cli schedule`: print server `warnings` to
  stderr (check `OpenQA::Script::CloneJob` output handling).
- Tests: `t/api/04-jobs.t` (reject/warn), `t/35-script_clone_job.t` for
  warning output.
- Commit: `feat(settings): enforce lifecycle rules on job creation`.

### T4: feat: lifecycle checks on product scheduling (`POST /api/v1/isos`)

- In `ScheduledProducts::_generate_jobs` evaluate merged per-job settings;
  `error` → add to `failed_job_info` with explanation (job not created);
  `warning` → add to scheduled product `results` (new key `warnings`) and to
  the `isos post` response; show on `/admin/productlog`.
- Tests: `t/api/02-iso.t` (failed_job_info + warnings), productlog UI test
  if template changed (`t/ui/…productlog…`).
- Commit: `feat(settings): enforce lifecycle rules on product scheduling`.

### T5: test: UI coverage for test details deprecation notice

- Add Selenium test in `t/ui/18-tests-details.t` configuring a warning and an
  error rule, asserting the tab badge, the alert class and per-key badge.
- Commit: `test(ui): cover deprecated settings notice on test details`.

### T6: docs: document test setting lifecycle management

- New section in `docs/Installing.md` next to `prio_throttling_patterns`:
  rule format, levels, which routes enforce, interplay with prio throttling,
  recommended phase-out workflow (warning → error → cleanup → remove rule).
- Short hint in `docs/UsersGuide.md` about the settings tab badge.
- Verification: `make test-docs` (or docs build target) if available.
- Commit: `docs: document test setting lifecycle rules`.

### T7: feat: read-only API route exposing lifecycle rules and validation

- `GET /api/v1/job_settings/lifecycle`: list parsed rules (id, key, op,
  regex string, level, prio, explanation, later: since/sunset/replacement).
- `POST /api/v1/job_settings/validate`: accepts settings hash, returns
  matches without side effects (enables client-side/CI validation).
- Tests: new subtests in `t/api/` (check for existing job_settings API test
  file first, e.g. `t/api/17-job_settings.t` or similar; extend rather than
  create).
- Commit: `feat(api): expose test setting lifecycle rules`.

### T8: feat: client-side validation in `openqa-validate-yaml` / `openqa-load-templates`

- Depends on T7. Optional `--host` mode: query `/job_settings/validate` for
  all settings in the YAML/templates and report matches; non-zero exit on
  `error`.
- Tests: `t/40-script_openqa-validate-yaml.t` (or matching existing test),
  `t/40-openqa-load-templates.t` with mocked API.
- Commit: `feat(client): validate settings against lifecycle rules`.

### T9: feat: sunset dates with automatic escalation

- Extend rule format with optional attributes. To avoid an ever-growing
  positional `:` format, switch to a sub-section per rule while keeping the
  old one-line format backwards compatible:

  ```ini
  [job_settings_lifecycle UEFI_UNSUPPORTED]
  key = UEFI_PFLASH_CODE
  pattern = =~ovmf-.*-unsupported
  level = warning
  since = 2026-09-01
  sunset = 2026-12-01
  prio = 30
  explanation = Use released OVMF packages instead
  ```

  (`OpenQA::Setup` already supports named sub-sections like
  `[test_preset …]`.)

- Effective level = `error` once `sunset` has passed; explanation gets
  "rejected after <sunset>" appended while in warning phase.
- Tests: data-driven cases with mocked time (`Test::MockModule` on
  `time`/`DateTime->now`) for before/after sunset; both config formats.
- Commit: `feat(settings): support sunset dates for lifecycle rules`.

### T10: feat: replacement hints and optional aliasing

- Depends on T9 format. Attributes `replacement_key`, `replacement_value`
  (template with `$1` captures) and `action = warn|rewrite`.
- `rewrite`: at job creation (T3/T4 code path, before
  `_apply_prio_throttling`) rename key / rewrite value; record the rewrite
  in the response warnings and in the job's settings as
  `_LIFECYCLE_REWRITTEN=<OLD_KEY>` to keep results traceable.
- Never rewrite stored definitions implicitly (that is T12).
- Tests: `t/job_settings_lifecycle.t` rewrite unit cases,
  `t/api/04-jobs.t` + `t/api/02-iso.t` asserting stored job settings.
- Commit: `feat(settings): support replacement and aliasing of settings`.

### T11: feat: usage report for lifecycle rules

- `GET /api/v1/job_settings/lifecycle/usage[?rule=<id>]`: per rule, list
  machines, products, test suites, job templates (with group) whose settings
  match, and count of jobs in the last N days
  (`misc_limits.job_settings_max_recent_jobs` reuse).
- Admin page `/admin/job_settings_lifecycle` (read-only table: rule, level,
  sunset, #definitions, #recent jobs, links). JS in
  `assets/javascripts/`, no inline scripts.
- Tests: `t/api/…` for JSON, `t/ui/…` for the page (menu entry for
  operators/admins).
- Commit: `feat(settings): add usage report for lifecycle rules`.

### T12: feat: bulk cleanup of deprecated settings in stored definitions

- Depends on T10/T11. Minion task `cleanup_deprecated_settings` triggered via
  `POST /api/v1/job_settings/lifecycle/cleanup` (admin only) with
  `dry_run=1` default; applies `replacement_*` or deletes the key in
  machine/product/test-suite/job-template settings.
- Emit audit events (`table_update` / `jobtemplate_update`) per modified
  entity; YAML-managed job groups: update the stored template YAML too or
  refuse with a clear message (decide during implementation; refusing is
  safer).
- Tests: `t/api/…` dry-run vs apply, audit log entries, Minion task unit test
  in `t/`.
- Commit: `feat(settings): add cleanup of deprecated settings`.

### T13: feat: metrics and audit events for lifecycle matches

- Count matches per rule/level on job creation, expose via
  `/admin/influxdb/jobs` (existing route) or a new influxdb measurement.
- Emit audit event `job_settings_rejected` for `error`-level rejections
  (who/what route), so admins can contact the submitter.
- Tests: `t/api/…influxdb…`, audit log assertion in T3/T4 test files.
- Commit: `feat(settings): report lifecycle rule matches as metrics`.

## Out of scope / critique

- **Settings registry / unknown-setting detection (phase 1).** Tempting to
  add a catalog of "known" settings with types and descriptions, flagging
  typos (`QEMURAM` vs `QEMU_RAM`). However the authoritative list of backend
  variables lives in os-autoinst (`doc/backend_vars.asciidoc`) and test
  variables are defined per test distribution. Duplicating them in openQA
  would rot. If pursued, openQA should consume a machine-readable list
  exported by os-autoinst/test distributions, not maintain its own. Treat as
  a separate ticket; the `info` level from T2 already allows announcing
  experimental settings.
- **DB-backed rules with admin UI editing.** Config-file rules require host
  access and a restart but are simple and reviewable (salt/git). Only move to
  DB storage if operators ask for it; the API from T7/T11 keeps that option
  open without changing clients.
- **Rewriting existing job results.** Old jobs keep their original settings;
  history must not change.
- T3/T4 rejecting jobs is a behavior change for external schedulers. Roll out
  with `warning` rules first; document in release notes.

## Verification (per task)

- `make tidy` and `make test-checkstyle`.
- `COVERAGE=1 make test-unit-and-integration TESTS="<touched tests>"`, then
  `make check-line-coverage` and
  `cover -report text -select_re '<modified file>'` for full statement
  coverage of new/changed lines.
- `make test-gitlint` after each commit; commit body with Motivation /
  Design Choices / Benefits and `Related issue:
https://progress.opensuse.org/issues/207561`.
