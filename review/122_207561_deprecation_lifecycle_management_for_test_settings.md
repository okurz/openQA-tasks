# Task 122: Deprecation/Lifecycle Management for Test Settings (Ticket #207561)

## Overview & Motivation

Related issue: https://progress.opensuse.org/issues/207561
Referenced issue: https://progress.opensuse.org/issues/200075

In openQA, test settings are often managed externally and submitted via API requests rather than being maintained directly in the openQA database. As demonstrated in #200075 (the `UEFI_PFLASH_CODE=ovmf-.*-unsupported` migration), removing or migrating obsolete test variables across machines, job templates, and test suites requires clear visibility and enforcement mechanisms.

Currently, openQA only allows ad-hoc job de-prioritization via `prio_throttling_patterns`. There is no formal mechanism to declare test settings as deprecated, surface warnings/explanations to users on the test details page, or reject updates in settings definitions.

This feature introduces test setting lifecycle and deprecation management in openQA.

## Acceptance Criteria

- **AC1:** It is possible to declare test settings (a certain key and a regex to match the value) as deprecated with the levels `warning` and `error` and an explanation.
- **AC2:** The test details page shows a warning/error with an explanation if the test contains deprecated settings.
- **AC3:** Routes that modify settings definitions (machine settings, job template settings, products, test suites) reject requests that add/update deprecated settings on `error` level.
- **Discussion/Tie-in:** Tie in with job priority throttling so deprecation rules can optionally adjust job priority without requiring duplicated regex definitions in configuration.

## Architectural Design

### 1. Configuration (`openqa.ini` and `OpenQA::Setup`)

A new section `[job_settings_lifecycle]` in `openqa.ini` allows declaring rules.
Format:

```ini
[job_settings_lifecycle]
## Format: rule_id = KEY:PATTERN:LEVEL[:PRIO_ADJUSTMENT]:EXPLANATION
## PATTERN can be =~<regex> or !~<regex> (defaults to =~ if prefix omitted)
## LEVEL is 'warning' or 'error' (extensible to 'experimental', 'info')
## PRIO_ADJUSTMENT (optional) is a number (e.g. +30, 15) to de-prioritize jobs using deprecated settings
## EXPLANATION is a human-readable message explaining why it is deprecated and what to use instead
rule = UEFI_PFLASH_CODE:=~ovmf-.*-unsupported:warning:30:Use released OVMF packages instead
rule = OBSOLETE_SETTING:=~.*:error:OBSOLETE_SETTING has been removed; see documentation
```

`default_config` in `lib/OpenQA/Setup.pm` registers `job_settings_lifecycle => {}` so any keys in this section are loaded into `$app->config->{job_settings_lifecycle}`.

### 2. Core Rules Engine (`OpenQA::JobSettings::Lifecycle`)

A dedicated module `lib/OpenQA/JobSettings/Lifecycle.pm` implements the logic with low cyclomatic complexity:

- `parse_lifecycle_rules($config)`: Parses rules from `$config->{job_settings_lifecycle}`, compiles regular expressions, and caches the result in `$config->{_job_settings_lifecycle_rules}`.
- `check_setting($key, $value, $rules)`: Checks a single key-value pair against the active rules. Returns a list of matching rule descriptors:
  `{ key => $k, value => $v, level => $level, explanation => $explanation, prio_adjustment => $prio }`.
- `check_settings($settings_hash, $rules)`: Checks all settings of a job or entity. Returns all matching rule descriptors.
- `validate_settings_for_submission($settings_hash, $rules)`: Evaluates settings against `error`-level rules. Returns `undef` if valid, or a descriptive error message string if any setting matches an `error`-level rule.
- `apply_lifecycle_prio($settings, $new_job_args, $throttling_info, $rules)`: If a matched rule defines a `prio_adjustment`, updates `$new_job_args->{priority}` and appends to `@$throttling_info`.

### 3. AC3 Enforcement: Settings Definition Routes

- `OpenQA::WebAPI::Controller::API::V1::Table`:
  In `_prepare_settings ($self, $table, $entry)` (used when creating/updating Machines, TestSuites, and Products), validate `$hp->{settings}` using `validate_settings_for_submission()`. If invalid, return the error message which results in `HTTP_BAD_REQUEST` (`400`).
- `OpenQA::Schema::ResultSet::JobTemplates`:
  In `create_or_update_job_template ($job_templates, $group_id, $args)` (used when updating job templates via YAML schedules), validate `$args->{settings}` using `validate_settings_for_submission()`. If invalid, return `{error => $error_message}` which causes `job_template#update` to reject the transaction with `HTTP_BAD_REQUEST` (`400`).

### 4. AC2 Presentation: Test Details Page

- `OpenQA::WebAPI::Controller::Test`:
  In `settings ($self)`: stash `deprecated_settings` by running `check_settings` against the job's settings.
  In `_show ($self, $job)`: check if any settings are deprecated to stash `has_deprecated_settings` and `deprecated_level`.
- `templates/webapi/test/settings.html.ep`:
  - When `deprecated_settings` are present, render a Bootstrap alert (`.alert-warning` or `.alert-danger`) listing the deprecated settings, badges, and explanations.
  - In `#settings_box`, render a badge next to deprecated settings with explanation tooltips.
- `templates/webapi/test/result.html.ep`:
  - Show a deprecation badge/icon on the "Settings" tab link (`#nav-item-for-settings`) so users are alerted immediately upon opening the test details page.

### 5. Priority Throttling Integration

In `OpenQA::Schema::ResultSet::Jobs::_apply_prio_throttling`:
Call `OpenQA::JobSettings::Lifecycle::apply_lifecycle_prio` to apply priority adjustments from lifecycle rules, avoiding duplicated regex definitions in `openqa.ini`.

## Implementation Tasks

### Task 1: Core Engine & Config Parsing (AC1)

- [x] Add `job_settings_lifecycle => {}` to `lib/OpenQA/Setup.pm` `default_config`.
- [x] Create `lib/OpenQA/JobSettings/Lifecycle.pm` implementing `parse_lifecycle_rules`, `check_setting`, `check_settings`, `validate_settings_for_submission`, and `apply_lifecycle_prio`.
- [x] Hook `apply_lifecycle_prio` into `OpenQA::Schema::ResultSet::Jobs::_apply_prio_throttling`.
- [x] Add unit test suite `t/job_settings_lifecycle.t` testing all parsing patterns, match operators (`=~`, `!~`), levels (`warning`, `error`, `experimental`), priority adjustments, and edge cases.

### Task 2: Rejection on Error Level in Settings Routes (AC3)

- [x] Hook `validate_settings_for_submission` in `_prepare_settings` in `lib/OpenQA/WebAPI/Controller/API/V1/Table.pm`.
- [x] Hook `validate_settings_for_submission` in `create_or_update_job_template` in `lib/OpenQA/Schema/ResultSet/JobTemplates.pm`.
- [x] Add integration tests in `t/api/05-machines.t` verifying 400 rejection on error-level deprecated settings and acceptance on warning-level settings.
- [x] Add integration tests in `t/api/08-jobtemplates.t` verifying YAML update rejection on error-level deprecated settings.

### Task 3: Test Details Page Deprecation Notice (AC2)

- [x] Update `lib/OpenQA/WebAPI/Controller/Test.pm` (`settings` and `_show`) to check and stash deprecated settings.
- [x] Update `templates/webapi/test/settings.html.ep` to show deprecation alert and table badges.
- [x] Update `templates/webapi/test/result.html.ep` to show deprecation badge on the Settings tab header.
- [x] Add UI / integration tests in `t/ui/18-tests-details.t` or `t/job_settings_lifecycle.t` verifying the rendered deprecation notice.

### Task 4: Documentation & Verification

- [x] Document `[job_settings_lifecycle]` in `etc/openqa/openqa.ini`.
- [x] Run `make tidy` and `make test-checkstyle`.
- [x] Run targeted test execution with `COVERAGE=1` and verify with `make check-line-coverage`.
- [x] Review git status to ensure only intended changes are present and no tasks/ files are staged.

## Subagent Execution Log

- Phase 1 (Planning): Completed in session. Architecture designed and documented in this plan.
- Phase 2 (Implementation & Testing): Completed via `flash-builder` sub-agent. All modules, templates, configuration docs, and test suites (`t/job_settings_lifecycle.t`, `t/api/05-machines.t`, `t/api/08-jobtemplates.t`) implemented and verified.
- Phase 3 (Review & Fix-up): Completed via `precision-fixer` sub-agent. Validated and fixed edge cases (defensive config structure checks, signed priority normalization, priority initialization defaults). Verified 100% statement coverage across all modified lines, passing `make tidy` and `make test-checkstyle`.
- Phase 4 (Coordination & Completion): Final review and status verification completed. Ready for commit/PR.
