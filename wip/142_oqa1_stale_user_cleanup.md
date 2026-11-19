# 142 oqa1: Stale User Account Identification and Automated Cleanup Workflow

Context: Employee departures and user database maintenance on https://openqa.suse.de/
Ticket: poo#142 (oqa1)
Branch: `feature/142_oqa1_stale_user_cleanup` (branched from `origin/master`)
Numbering: Prefix `142` as specified; relates to openQA user lifecycle and stale account governance.

---

## Problem Statement

As employees leave the company, the user database of openQA instances—notably `https://openqa.suse.de/` (OSD)—accumulates stale accounts. These accounts represent multiple operational and security concerns:

1. **Dormant Privileges**: Stale accounts may retain `is_operator = 1` or `is_admin = 1` permissions.
2. **Orphaned API Keys**: Departing employees' active API keys and personal access tokens remain valid indefinitely unless deleted or expired.
3. **Audit and Compliance**: GDPR and SUSE internal security policies mandate regular deprovisioning and anonymization of personal data for offboarded staff.
4. **Lack of Automated Lifecycle Management**: While openQA supports user anonymization (`$user->anonymize` via `DELETE /api/v1/user/:id`), openQA has historically lacked an automated discovery mechanism to cross-check active accounts against corporate directories and perform periodic garbage collection.

---

## Technical Analysis & Discovery Findings

### 1. Identity Verification Sources

| Source                                      | Access & Protocol                                         | Active Indicator                                    | Inactive / Departed Indicator                             | Assessment                                                                                                                                       |
| :------------------------------------------ | :-------------------------------------------------------- | :-------------------------------------------------- | :-------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------- |
| **Geekos API** (`https://geekos.suse.net/`) | Internal HTTPS, unauthenticated (`GET /api/users/<nick>`) | HTTP 200 with JSON payload (`{"type":"user",...}`)  | HTTP 404 (`{"errors":["user not found"]}`)                | **Fastest & most direct query surface** for automated HTTP probes inside SUSE network.                                                           |
| **SUSE LDAP** (`ldaps://ldap.<internal>`)      | Anonymous bind (`-x`), port 636                           | `suseudbenabled: 1` in `ou=accounts` or `ou=people` | `suseudbenabled: 0`, or entry purged entirely (0 results) | **Authoritative directory**, accessible via CLI/Perl without token; covers posixAccounts.                                                        |
| **Workday** (`wd3.myworkday.com`)           | SAML/Okta SSO or ISU credentials                          | Active employee status in WWS/RaaS report           | Terminated status                                         | Upstream HR system of record, but requires HR-managed API tokens. Downstream syncs to LDAP and Geekos make direct Workday integration redundant. |

### 2. openQA User Database Model & Deletion Contract

- **Storage**: Table `users` (`id`, `username`, `nickname`, `email`, `fullname`, `is_operator`, `is_admin`, `deleted_at`).
- **Soft Deletion / Anonymization Contract**: `$user->anonymize` in `OpenQA::Schema::Result::Users`:
  - Deletes all active user API keys (`$self->api_keys->delete`).
  - Anonymizes references in `audit_events` (`event_data =~ s/\Q$username\E/deleted-user/gr`).
  - Sets `username => "deleted-user-$user_id"`, `email => undef`, `fullname => undef`, `nickname => undef`.
  - Sets `deleted_at => DateTime->now`.
  - Preserves relational integrity of historical comments, job records, and needle attributions.
- **Identified Defect in `anonymize()`**: `anonymize()` currently does NOT reset `is_operator` or `is_admin`. Soft-deleted accounts retain their role flags in the database and web UI.
- **API Gap Addressed**: `GET /api/v1/users` (recently implemented) provides admin-authenticated listing with pagination (`limit`, `offset`) and active/deleted filtering (`deleted=0/1`).

---

## Target Architecture

The solution consists of three decoupled components:

```
+-----------------------------------------------------------------------------------+
| 1. Core Model Fix: OpenQA::Schema::Result::Users                                  |
|    - Explicitly revoke `is_admin => 0, is_operator => 0` upon `anonymize()`       |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 2. Periodic Maintenance Task: OpenQA::Task::User::CleanupStale                    |
|    - Queries active users (`deleted_at IS NULL`)                                  |
|    - Cross-checks with Geekos API / LDAP                                          |
|    - Enqueued weekly via `script/openqa-enqueue-user-cleanup` and Minion          |
|    - Configurable grace period and dry-run reporting                              |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 3. Standalone Audit & Cleanup CLI: script/openqa-audit-stale-users               |
|    - Interactive / manual tool for admins                                         |
|    - Generates markdown/JSON reports of stale accounts and orphan API keys       |
|    - Supports dry-run, CSV export, and optional immediate deactivation            |
+-----------------------------------------------------------------------------------+
```

---

## Detailed Task Breakdown

### Task 1: Fix Core User Model Role Revocation upon Anonymization

- **Files**:
  - `lib/OpenQA/Schema/Result/Users.pm`
  - `t/06-users.t`
  - `t/api/15-users.t`
- **Objective**:
  - In `OpenQA::Schema::Result::Users::anonymize`, ensure `is_admin` and `is_operator` are explicitly updated to `0` inside the transaction.
  - Update `t/06-users.t` and `t/api/15-users.t` to assert that soft-deleted users have `is_admin == 0` and `is_operator == 0`.
- **Verification**: `make test-unit-and-integration TESTS="t/06-users.t t/api/15-users.t"`

### Task 2: Implement Standalone Audit & Discovery CLI Script

- **Files**:
  - `script/openqa-audit-stale-users`
  - `t/44-scripts-openqa-audit-stale-users.t`
- **Objective**:
  - Create `script/openqa-audit-stale-users` with `Getopt::Long::Descriptive`:
    - `--dry-run`: Audit and print findings without modifying database (default).
    - `--apply`: Deactivate and anonymize confirmed stale accounts.
    - `--backend <geekos|ldap|both>`: Identity provider to cross-check against (default: `geekos`).
    - `--geekos-url <url>`: Default `https://geekos.suse.net`.
    - `--ldap-host <uri>`: Default `ldaps://ldap.<internal>`.
    - `--exclude <names>`: Comma-separated usernames to ignore (defaults: `system,geekotest,admin`).
    - `--format <table|json|csv>`: Output formatting for automation.
  - Extract username/nickname from openQA `users` table:
    - Strip OpenID URL prefixes (e.g. `https://www.opensuse.org/openid/user/`).
    - Query Geekos `/api/users/<nick>` or LDAP `(uid=<nick>)`.
  - Output summary: total active users, confirmed stale accounts, active API keys held by stale accounts, and privileged roles held by stale accounts.
- **Verification**: `make test-unit-and-integration TESTS=t/44-scripts-openqa-audit-stale-users.t`

### Task 3: Implement Periodic Maintenance Minion Task

- **Files**:
  - `lib/OpenQA/Task/User/CleanupStale.pm`
  - `script/openqa-enqueue-user-cleanup`
  - `t/task-user-cleanup-stale.t`
  - `docs/Installing.md`
- **Objective**:
  - Implement Minion background task `user_cleanup_stale` inheriting from `OpenQA::Task::Table::Limit` or standard Minion task.
  - Read configuration from `[user_cleanup]` section in `openqa.ini`:
    - `enabled = 0` (default disabled for generic openQA instances; enabled on OSD).
    - `backend = geekos` (or `ldap`).
    - `dry_run = 1` (default safe mode).
    - `grace_period_days = 30` (only clean up users inactive/departed for > 30 days).
  - Add enqueue wrapper script `script/openqa-enqueue-user-cleanup`.
  - Log audit events (`openqa_user_stale_detected`, `openqa_user_anonymized`) so actions appear in `/admin/auditlog`.
- **Verification**: `COVERAGE=1 make test-unit-and-integration TESTS=t/task-user-cleanup-stale.t`

### Task 4: Documentation & Production Deployment Guide

- **Files**:
  - `docs/UsersGuide.md`
  - `docs/Installing.md`
- **Objective**:
  - Document the stale account cleanup workflow in administrator documentation.
  - Detail systemd timer setup (`openqa-user-cleanup.timer` and `openqa-user-cleanup.service`).
  - Provide instructions for one-time manual cleanup on `openqa.suse.de`.
- **Verification**: `make test-markdown && SKIP_UPDATE_DEPS=1 make test-checkstyle`

---

## Approvals

| Decision                                                                                                | Approver | Date       |
| :------------------------------------------------------------------------------------------------------ | :------- | :--------- |
| Use Geekos API as primary HTTP check and SUSE LDAP as secondary directory check                         | okurz    | 2026-11-09 |
| Discard direct Workday integration due to auth overhead; rely on LDAP/Geekos syncs                      | okurz    | 2026-11-09 |
| Implement two-tier solution: standalone CLI for immediate cleanup + Minion task for ongoing maintenance | okurz    | 2026-11-09 |
| Ensure `$user->anonymize` revokes `is_admin` and `is_operator` flags                                    | okurz    | 2026-11-09 |

---

## Gates

| Commit   | Scope                                                        | Verification Command                                                                                                                                    |
| :------- | :----------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Commit 1 | Core model: revoke `is_admin`/`is_operator` in `anonymize()` | `make tidy && COVERAGE=1 make test-unit-and-integration TESTS="t/06-users.t t/api/15-users.t" && make check-line-coverage && make test-gitlint`         |
| Commit 2 | CLI script: `script/openqa-audit-stale-users` and unit test  | `make tidy && COVERAGE=1 make test-unit-and-integration TESTS=t/44-scripts-openqa-audit-stale-users.t && make check-line-coverage && make test-gitlint` |
| Commit 3 | Background Minion task: `OpenQA::Task::User::CleanupStale`   | `make tidy && COVERAGE=1 make test-unit-and-integration TESTS=t/task-user-cleanup-stale.t && make check-line-coverage && make test-gitlint`             |
| Commit 4 | Documentation: user lifecycle & systemd timer configuration  | `make test-markdown && SKIP_UPDATE_DEPS=1 make test-checkstyle && make test-gitlint`                                                                    |

---

## Session starter

```markdown
Continue with execution plan `tasks/142_oqa1_stale_user_cleanup.md`.
Load skills: `perl-dev`, `git-workflow`, `testing`.
Branch: `feature/142_oqa1_stale_user_cleanup` based on `origin/master`.
Commit unit: Start with Task 1 (Core model: revoke `is_admin` and `is_operator` upon `anonymize()` in `lib/OpenQA/Schema/Result/Users.pm`).
Confirm with user before executing any `--apply` or live modification on production instances.
```
