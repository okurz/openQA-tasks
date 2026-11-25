# 217 — Better API key handling: permission scoping and API creation (poo/207879)

Related issue: https://progress.opensuse.org/issues/207879
Follow-up of PR #7907 (fix: Return secret on API key creation) and PR #7908 (feat: Add comment field to API keys).

## Context & Requirements

Redmine ticket [poo#207879](https://progress.opensuse.org/issues/207879) note-6 identified the remaining scope:
1. **User default key holds highest permissions; additional keys can have equal or lower permissions**:
   - In openQA, user permissions are role flags on `users` (`is_admin`, `is_operator`).
   - A user's effective permissions when authenticated via an API key must be bounded by both:
     1. The user's own current roles (`$user->is_admin`, `$user->is_operator`), and
     2. The permission scope assigned to that specific API key.
   - A user cannot grant an API key higher roles than the user currently possesses (e.g. non-admin cannot create an admin key; regular user cannot create an operator key).
   - If an admin/operator user's role is later revoked on their account, any keys they own automatically cannot exceed their downgraded user permissions (effective role = `user_role AND key_role`).
   - The user's default/initial key or existing keys without explicit restrictions should maintain maximum permissible permissions for that user.
2. **API Keys can be created over API with custom scope, expiration, and comments**:
   - `POST /api/v1/users/me/api_keys` already supports `expiration` and `comment` (via PR #7907 and PR #7908).
   - It must now support specifying the desired permission scope (e.g. `is_operator`, `is_admin`, or `role` parameter), validating that it does not exceed the calling user's current permissions.
   - The Web UI (`/api_keys`) should also reflect key permissions and allow selecting them upon key creation up to the user's role.

---

## Architectural Analysis

### Database Schema (`OpenQA::Schema::Result::ApiKeys`)
Currently, `api_keys` table holds:
- `id` (bigint)
- `key` (text, unique)
- `secret` (text)
- `user_id` (bigint, foreign key)
- `t_expiration` (timestamp, nullable)
- `comment` (text, default '')
- `t_created`, `t_updated` (timestamps)

To support role scoping per key:
- Add `is_operator` (boolean/integer, default 1, not null).
- Add `is_admin` (boolean/integer, default 1, not null).
- Defaulting to 1 (true) for both fields ensures backwards compatibility: existing keys automatically inherit whatever permissions the parent user possesses (equal to user's permissions).
- When a key has `is_admin => 0, is_operator => 1`, an admin user authenticating with this key acts only as an operator.
- When a key has `is_admin => 0, is_operator => 0`, an admin or operator user authenticating with this key acts as an unprivileged regular user.
- Schema migration from 107 to 108 using `script/upgradedb --prepare_upgrades`.

### Effective Role Resolution in Authentication (`OpenQA::Shared::Controller::Auth`)
In `OpenQA::Shared::Controller::Auth`:
- `_key_auth`: When verifying HMAC with an API key, stash both the user and the authenticated API key:
  `$self->stash(current_api_key => $api_key)`.
- Helper checks (`is_operator`, `is_admin` in `OpenQA::Shared::Plugin::SharedHelpers`):
  When an API key is present in stash (`$c->stash('current_api_key')`), compute effective roles:
  - `effective_is_admin = $user->is_admin && $api_key->is_admin`
  - `effective_is_operator = ($user->is_admin && $api_key->is_admin) || ($user->is_operator && $api_key->is_operator)`
- Ensure controller checks and route guards (`auth_operator`, `auth_admin`, `$c->is_operator`, `$c->is_admin`) observe the effective permissions.
- In `OpenQA::Shared::Controller::Auth::check`: Also respect effective operator status when checking API key access for livehandler/scheduler/websockets.

### REST API Controller (`OpenQA::WebAPI::Controller::API::V1::User`)
- `POST /api/v1/users/me/api_keys`:
  - Validate parameters `is_operator` and `is_admin` (or role names if specified).
  - Enforce constraint: `is_admin` can only be 1 if `$user->is_admin` is 1; `is_operator` can only be 1 if `$user->is_operator` is 1. Return 400 Bad Request if requested permissions exceed caller's permissions.
  - Default permissions when omitted: match the user's current permissions (or default 1/1 bounded by user).
  - Return `is_operator` and `is_admin` in JSON response.
- `GET /api/v1/users/me/api_keys`:
  - Include `is_operator` and `is_admin` in the returned key objects.

### Web UI Controller & Template (`OpenQA::WebAPI::Controller::ApiKey` & `templates/webapi/api_key/index.html.ep`)
- Form validation in `ApiKey#create` to accept and validate `is_operator` and `is_admin`.
- Form dropdown or checkboxes in `index.html.ep` enabling users to select role level (e.g. User, Operator, Administrator) up to their own role.
- Display key role/permissions in the API keys table.

---

## Work Breakdown (Atomic Commits)

### Task 1: Schema Migration & Model Support (dbicdh 107 -> 108)
- **Goal:** Add `is_operator` and `is_admin` columns to `api_keys` table with default 1.
- **Files:**
  - `lib/OpenQA/Schema.pm` (bump `$VERSION` to 108)
  - `lib/OpenQA/Schema/Result/ApiKeys.pm` (add column definitions)
  - `dbicdh/PostgreSQL/upgrade/107-108/001-auto.sql` and deploy files (generated via `script/upgradedb --prepare_upgrades`)
- **Tests:**
  - `t/07-api_keys.t`: Verify column defaults and attributes on new ApiKeys records.
- **Verification:**
  `COVERAGE=1 make test-unit-and-integration TESTS=t/07-api_keys.t`

### Task 2: Authentication & Effective Role Scoping
- **Goal:** Scope effective user permissions by the authenticating API key's permissions.
- **Files:**
  - `lib/OpenQA/Shared/Controller/Auth.pm` (stash `current_api_key` in `_key_auth` and personal access token auth; adjust `check` method)
  - `lib/OpenQA/Shared/Plugin/SharedHelpers.pm` (adjust `_is_operator` and `_is_admin` helpers to check `$c->stash('current_api_key')`)
- **Tests:**
  - `t/api/01-auth.t` or dedicated subtest in `t/api/15-users.t`:
    - Admin user using an operator-scoped key cannot access admin-only endpoints (`/api/v1/user/...`) but can access operator endpoints.
    - Operator user using an unprivileged-scoped key cannot access operator endpoints.
    - Regular user cannot elevate privileges via an API key.
- **Verification:**
  `COVERAGE=1 make test-unit-and-integration TESTS=t/api/15-users.t`

### Task 3: REST API Support for Scoped API Keys
- **Goal:** Allow specifying permissions when creating API keys via REST API and expose permissions in list.
- **Files:**
  - `lib/OpenQA/WebAPI/Controller/API/V1/User.pm` (`create_api_key` and `list_api_keys`)
- **Tests:**
  - `t/api/15-users.t`:
    - Create key with restricted permissions (`is_operator => 0`, `is_admin => 0`).
    - Attempt to create key with permissions exceeding caller's role (rejected with 400).
    - Verify `list_api_keys` outputs `is_operator` and `is_admin`.
- **Verification:**
  `COVERAGE=1 make test-unit-and-integration TESTS=t/api/15-users.t`

### Task 4: Web UI Support for Scoped API Keys
- **Goal:** Allow users to choose permission scope when creating keys in Web UI and display permissions in table.
- **Files:**
  - `lib/OpenQA/WebAPI/Controller/ApiKey.pm`
  - `templates/webapi/api_key/index.html.ep`
- **Tests:**
  - `t/ui/04-api_keys.t`:
    - UI test creating keys with specific permission scope.
    - Validate table displays permission column.
- **Verification:**
  `COVERAGE=1 make test-unit-and-integration TESTS=t/ui/04-api_keys.t`

### Task 5: Final Verification & Style
- **Goal:** Ensure full test checkstyle, line coverage, and gitlint compliance.
- **Commands:**
  - `make tidy`
  - `make test-checkstyle`
  - `make check-line-coverage`

---

## Approvals
- **Decision:** Scope API key permissions with `is_operator` and `is_admin` columns defaulting to true (1) to preserve backward compatibility while enforcing `effective_role = user_role AND key_role`.
- **Approver:** okurz
- **Date:** 2026-03-30

## Gates
- **Commit 1 (db migration & result class):**
  `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/07-api_keys.t && make check-line-coverage`
- **Commit 2 (effective role scoping in auth):**
  `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS="t/07-api_keys.t t/api/15-users.t" && make check-line-coverage`
- **Commit 3 (REST API params & validation):**
  `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/api/15-users.t && make check-line-coverage`
- **Commit 4 (Web UI creation form & list table):**
  `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/ui/04-api_keys.t && make check-line-coverage`
- **Post-commit:**
  `make test-gitlint`

## Session starter
```markdown
Execute task 1 from tasks/217_oqa4_poo207879_api_key_handling.md.
Skills to load: perl-dev, git-workflow, testing.
Commit unit: Task 1 - Schema Migration & Model Support (dbicdh 107 -> 108).
Confirm with user before executing schema migration tools or creating DB files.
```
