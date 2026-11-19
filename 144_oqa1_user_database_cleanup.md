# 144 oqa1: User Database Cleanup and Phased Account Consolidation

Context: User database maintenance, privilege demotion, and safe deprovisioning on https://openqa.suse.de/
Ticket: poo#144 (oqa1)
Branch: `feature/144_oqa1_user_database_cleanup` (branched from `origin/master`)
Numbering: Prefix `144` as specified; builds on discovery and baseline audit tooling.

---

## Problem Statement

Cross-checking active openQA accounts on `openqa.suse.de` against corporate directory services (Geekos / SUSE ID) identified **205 stale accounts** belonging to departed employees. However, a naive bulk deletion or immediate account anonymization (`anonymize()`) poses serious operational risks:

1. **Active Automation Disruption**: Several departed employee accounts hold active API keys that are actively used by production cron jobs and automation (e.g. User ID 8 actively creating job templates daily, and User ID 145 running automated LTP tests). Immediate API key deletion would break production test pipelines.
2. **Ambiguous Bot/Service Ownership**: Accounts such as User ID 403 (`qa-maintenance-automation`), User ID 399 (`openqa_container_bot`), User ID 128 (`sle-qam-openqa`), and User ID 413 (`carwos-tester`) are service/bot accounts registered under former employees' email addresses or plus-addressed emails. Blindly anonymizing them disrupts automated maintenance.
3. **Loss of Attribution vs. PII Scrubbing**: Accounts with historical write operations (comments on tests, audit events, needle attributions, job restarts) must have their PII anonymized in compliance with corporate security and privacy policies while preserving relational integrity so test discussion context is not destroyed.
4. **Read-Only Clutter**: 138 stale accounts have zero write operations in the database (they only logged in once via SSO to view tests). These can be purged or anonymized immediately with zero operational impact.

A phased, tiered consolidation strategy is required to clean up privileges, migrate active automation, preserve audit history, and deprovision stale accounts safely.

---

## Current OSD Inventory & Classification Breakdown

From the database cross-check of the 205 stale accounts on `openqa.suse.de`:

| Classification Tier                     | Description                                                                                                           | Account Count                                                          | Dominant Roles                   | Risk Level                                                              |
| :-------------------------------------- | :-------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------- | :------------------------------- | :---------------------------------------------------------------------- |
| **Tier 1: Active Automation Accounts**  | Accounts with recent API key activity (< 30 days) executing background actions.                                       | 3 accounts (User ID 8, User ID 145, User ID 403)                       | 3 Admins                         | **CRITICAL**: Immediate deletion breaks production cron jobs.           |
| **Tier 2: Service / Bot Accounts**      | Accounts identified as bot/service accounts registered under personal/plus-addressed emails.                          | ~4 accounts (User ID 399, User ID 128, User ID 413, etc.)              | 1 Admin, 3 Operators             | **HIGH**: Need ownership/alias transfer before key rotation.            |
| **Tier 3: Historical Write Accounts**   | Departed employees with historical contributions (comments, job restarts, audits, needles), but no recent automation. | ~60 accounts (e.g. User ID 416, User ID 481, User ID 429, User ID 369) | 39 Admins, 17 Operators, 4 Users | **MEDIUM**: Privileges must be revoked; PII scrubbed via `anonymize()`. |
| **Tier 4: Read-Only Inactive Accounts** | Accounts with zero comments, zero audit events, and zero active API keys.                                             | 138 accounts                                                           | 0 Admins, 6 Operators, 132 Users | **LOW**: Safe for immediate batch anonymization.                        |

---

## Target Architecture & Cleanup Workflow

```
+-----------------------------------------------------------------------------------------+
| 1. Classification & Audit (script/openqa-audit-stale-users)                             |
|    - Queries Geekos API / LDAP to detect non-active employees                           |
|    - Inspects audit_events, comments, and api_keys to assign Tier 1, 2, 3, or 4         |
|    - Flags accounts with recent activity (< 30 days) as protected from deletion        |
+-----------------------------------------------------------------------------------------+
                                           |
                                           v
+-----------------------------------------------------------------------------------------+
| Phase 1: Immediate Privilege Revocation (--revoke-roles)                                |
|    - Strip is_admin = 0, is_operator = 0 for all Tier 3 & Tier 4 accounts               |
|    - Immediate security hardening without breaking active API keys                      |
+-----------------------------------------------------------------------------------------+
                                           |
                                           v
+-----------------------------------------------------------------------------------------+
| Phase 2: Automation & Bot Migration (Runbook & Transfer Tools)                          |
|    - Reassign cron jobs from User ID 8 / User ID 145 to dedicated bot accounts          |
|    - Reassign ownership of bot accounts to functional team aliases                      |
|    - Revoke superseded personal API keys                                                |
+-----------------------------------------------------------------------------------------+
                                           |
                                           v
+-----------------------------------------------------------------------------------------+
| Phase 3: Anonymization & Deprovisioning (--tier=readonly, --tier=historical)            |
|    - Batch anonymize Tier 4 (read-only users)                                           |
|    - Batch anonymize Tier 3 (historical write users, preserving comment relationships)  |
|    - Finally anonymize migrated Tier 1 accounts once automation callers are verified    |
+-----------------------------------------------------------------------------------------+
```

---

## Detailed Task Breakdown

### Task 1: Extend Audit Tool with Activity Tiering & Safety Guards

- **Files**:
  - `script/openqa-audit-stale-users`
  - `t/44-scripts-openqa-audit-stale-users.t`
- **Objective**:
  - Enhance `script/openqa-audit-stale-users` to inspect related database activity:
    - Count audit events (`audit_events`), comments (`comments`), and active API keys (`api_keys`).
    - Compute `real_last_activity` timestamp across all activity tables.
    - Assign each stale account to a classification tier:
      - `active_automation`: has API key activity within `--active-threshold-days` (default 30).
      - `bot`: username or email matches bot patterns (`*bot*`, `*automation*`, `*tester*`).
      - `historical_writes`: has historical comments, needle updates, or audit records.
      - `readonly`: zero comments, zero audits, zero API keys.
  - Add CLI flags:
    - `--tier <all|active_automation|bot|historical_writes|readonly>`: Filter audit or action by tier.
    - `--active-threshold-days <days>`: Threshold to consider an account actively used (default: 30).
    - `--revoke-roles-only`: Revoke `is_admin` and `is_operator` without anonymizing or deleting API keys.
    - `--protect-active`: Refuse to anonymize any account in the `active_automation` tier unless explicitly forced with `--force-active`.
  - Include activity metrics and tier in JSON, CSV, and table outputs.
- **Verification**: `COVERAGE=1 make test-unit-and-integration TESTS=t/44-scripts-openqa-audit-stale-users.t && make check-line-coverage`

### Task 2: Implement Admin CLI for Reassigning Bot/Automation Ownership

- **Files**:
  - `script/openqa-reassign-account`
  - `t/44-scripts-openqa-reassign-account.t`
- **Objective**:
  - Provide an administrative tool to safely transition bot and automation ownership:
    - `openqa-reassign-account --user <username|id> --new-email <team-alias@<internal>> [--new-nickname <nick>]`
    - Update user email and nickname to decouple departing personal email addresses from long-lived bot accounts.
    - Add `--rotate-api-keys` option to generate a new key pair for the target service and display credentials for updating caller scripts.
- **Verification**: `COVERAGE=1 make test-unit-and-integration TESTS=t/44-scripts-openqa-reassign-account.t && make check-line-coverage`

### Task 3: Production Runbook & Staged Execution on openqa.suse.de

- **Files**:
  - `docs/UsersGuide.md` (Admin section: Stale Account Lifecycle & Service Migration)
- **Objective**:
  - Document the exact staged operational procedure for `openqa.suse.de`:
    - **Step 1 (Dry Run & Tier Inventory)**:
      ```bash
      openqa-audit-stale-users --format table
      ```
    - **Step 2 (Immediate Privilege Demotion)**:
      ```bash
      # Strip admin and operator flags from departed accounts without touching keys or accounts
      openqa-audit-stale-users --revoke-roles-only --exclude "system,geekotest,admin,8,145,403"
      ```
    - **Step 3 (Clean Up Read-Only Accounts)**:
      ```bash
      # Anonymize 138 zero-write accounts safely in batch
      openqa-audit-stale-users --apply --tier readonly
      ```
    - **Step 4 (Migrate Automation Callers)**:
      - Coordinate with openQA infrastructure team for User ID 8 (job template syncing cron) and User ID 145 (LTP runner) to replace API keys with dedicated bot credentials (`geekotest` or `qac_bot`).
      - Reassign User ID 403 (`qa-maintenance-automation`) email to functional team alias `qa-maintenance@<internal>`.
    - **Step 5 (Deprovision Historical Accounts & Migrated Automation)**:
      ```bash
      # Anonymize historical write accounts (preserves relational audit & comments)
      openqa-audit-stale-users --apply --tier historical_writes
      ```
- **Verification**: `make test-markdown && SKIP_UPDATE_DEPS=1 make test-checkstyle`

### Task 4: Add Automated Safeguards to User Deletion API and Minion Task

- **Files**:
  - `lib/OpenQA/Schema/Result/Users.pm`
  - `lib/OpenQA/WebAPI/Controller/API/V1/User.pm`
  - `t/api/15-users.t`
  - `t/06-users.t`
- **Objective**:
  - In `OpenQA::WebAPI::Controller::API::V1::User::delete`:
    - Check if target user has had API key activity or audit activity within the last 30 days.
    - Require `?force=1` parameter if active automation is detected; otherwise reject with HTTP 409 Conflict: `Account has active API key activity within the last 30 days. Migrate automation before deleting.`
  - In `OpenQA::Schema::Result::Users::anonymize`:
    - Ensure `is_admin => 0` and `is_operator => 0` are reset upon anonymization so soft-deleted accounts never retain roles.
- **Verification**: `COVERAGE=1 make test-unit-and-integration TESTS="t/06-users.t t/api/15-users.t" && make check-line-coverage`

---

## Approvals

| Decision                                                                                            | Approver | Date       |
| :-------------------------------------------------------------------------------------------------- | :------- | :--------- |
| Categorize stale accounts into 4 tiers (Active Automation, Bots, Historical Writes, Read-Only)      | okurz    | 2026-11-09 |
| Never delete active automation accounts (User ID 8, User ID 145) until callers are migrated         | okurz    | 2026-11-09 |
| Reassign bot accounts to functional team aliases rather than deleting them                          | okurz    | 2026-11-09 |
| Execute immediate role revocation (`is_admin=0, is_operator=0`) ahead of full account anonymization | okurz    | 2026-11-09 |
| Require `--force` to delete accounts with API key activity in the last 30 days                      | okurz    | 2026-11-09 |

---

## Gates

| Commit   | Scope                                                                                           | Verification Command                                                                                                                                    |
| :------- | :---------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Commit 1 | CLI: Activity tiering, `--tier`, and `--revoke-roles-only` in `script/openqa-audit-stale-users` | `make tidy && COVERAGE=1 make test-unit-and-integration TESTS=t/44-scripts-openqa-audit-stale-users.t && make check-line-coverage && make test-gitlint` |
| Commit 2 | CLI: Account reassignment script `script/openqa-reassign-account` and tests                     | `make tidy && COVERAGE=1 make test-unit-and-integration TESTS=t/44-scripts-openqa-reassign-account.t && make check-line-coverage && make test-gitlint`  |
| Commit 3 | Core API: Active automation protection guard and role revocation upon deletion                  | `make tidy && COVERAGE=1 make test-unit-and-integration TESTS="t/06-users.t t/api/15-users.t" && make check-line-coverage && make test-gitlint`         |
| Commit 4 | Documentation: Staged cleanup runbook and service migration instructions                        | `make test-markdown && SKIP_UPDATE_DEPS=1 make test-checkstyle && make test-gitlint`                                                                    |

---

## Session starter

```markdown
Continue with execution plan `tasks/144_oqa1_user_database_cleanup.md`.
Load skills: `perl-dev`, `git-workflow`, `testing`.
Branch: `feature/144_oqa1_user_database_cleanup` based on `origin/master`.
Commit unit: Start with Task 1 (Add activity tiering, `--tier` filter, and `--revoke-roles-only` flag to `script/openqa-audit-stale-users` with tests in `t/44-scripts-openqa-audit-stale-users.t`).
Confirm with user before executing any `--apply` or live modification on production instances.
```
