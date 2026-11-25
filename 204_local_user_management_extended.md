# 204 — Extended local user management

## Context

Branch: `feature/104_local_user_management`.

The local auth feature is already present:

- `OpenQA::WebAPI::Auth::Local` provides `hash_password`, `verify_password`, login/logout.
- `OpenQA::Shared::Controller::Session` provides `/register`, `/password_change`, `/delete_account`.
- `OpenQA::WebAPI::Controller::Admin::User` provides admin role updates and admin user deletion.
- Audit events are recorded for register/password change/delete.
- Tests exist in `t/ui/31-local-auth.t`, `t/40-password-hashing.t`, `t/06-users.t`.

This task extends the local user management path with industry best-practice hardening.

## Design decisions

- Keep local auth scoped to `auth.method == 'Local'`.
- Admin password reset is admin-only and applies only to non-deleted `provider == 'Local'` users.
- Admins never see existing passwords.
- Admin reset supports two modes:
  - explicit new password supplied by admin, validated with the same policy;
  - generated temporary password returned once.
- Password policy becomes stricter but remains testable:
  - minimum 8 characters;
  - maximum 128 characters;
  - reject whitespace-only;
  - reject password equal to username;
  - reject a small built-in common-password blocklist;
  - reject passwords containing the username.
- Password hashing prefers Argon2id when available, otherwise bcrypt, and fails closed in production if neither strong KDF is available.
- Existing bcrypt hashes must continue to verify.
- Authenticated password change no longer requires `old_password`; session + CSRF is sufficient.
- Password changes and admin password resets invalidate existing sessions for the affected user.
- Login and registration get simple in-memory rate limiting plus failed-login audit events.
- Admin user management guards prevent demoting the last admin and modifying system users.
- Admin password reset optionally revokes API keys for the target user.
- Docs document the new behavior.

## Atomic tasks

Each task is one commit. After every code commit:

- `make tidy`
- `make test-checkstyle`
- `make test-gitlint`
- targeted tests with `COVERAGE=1`
- `make check-line-coverage`

Do not stage or commit `tasks/204_local_user_management_extended.md`.

### T1 — Password policy hardening

Files:

- `lib/OpenQA/Shared/Controller/Session.pm`
- `t/ui/31-local-auth.t`

Changes:

- Extract password validation into a reusable helper if not already central.
- Add max length 128.
- Reject passwords containing username.
- Reject common passwords from a small module-level list.
- Keep existing error messages stable where possible.
- Update tests for:
  - too-long password;
  - password containing username;
  - common password rejection;
  - existing valid passwords still accepted.

Commit:

`feat(auth): Harden local password policy`

### T2 — Strong password hashing preference

Files:

- `lib/OpenQA/WebAPI/Auth/Local.pm`
- `t/40-password-hashing.t`
- `t/ui/31-local-auth.t`

Changes:

- Add optional Argon2id support if `Crypt::Argon2` or equivalent is available.
- Keep bcrypt as fallback.
- Keep existing bcrypt hash verification.
- Add a production guard: if `hash_password` is called and no strong KDF is available, croak instead of using weak `crypt()` fallback.
- Keep test fallback path only when explicitly requested by tests or config.

Commit:

`feat(auth): Prefer strong password hashing`

### T3 — Remove old-password requirement for authenticated password change

Files:

- `lib/OpenQA/Shared/Controller/Session.pm`
- `templates/webapi/main/password_change.html.ep`
- `t/ui/31-local-auth.t`

Changes:

- `POST /password_change` requires only `new_password`.
- Remove `old_password` form field.
- Keep CSRF and `ensure_user`.
- Update tests to remove old-password cases and assert missing `new_password` fails.

Commit:

`fix(auth): Use session for password change`

### T4 — Invalidate sessions on credential changes

Files:

- `lib/OpenQA/Shared/Controller/Session.pm`
- `lib/OpenQA/WebAPI.pm`
- `t/ui/31-local-auth.t`

Changes:

- Password change invalidates current session after success.
- Account deletion already invalidates; keep behavior.
- Add helper `_invalidate_user_session` if useful.
- Test that after password change, the user must log in again.

Commit:

`fix(auth): Invalidate sessions on credential changes`

### T5 — Admin password reset route

Files:

- `lib/OpenQA/WebAPI.pm`
- `lib/OpenQA/WebAPI/Controller/Admin/User.pm`
- `templates/webapi/admin/user/index.html.ep`
- `assets/javascripts/admin_user.js`
- `t/ui/31-local-auth.t`

Changes:

- Add admin route `POST /admin/users/:userid/password_reset`.
- Guard with `ensure_admin`.
- Reject deleted, system, and non-Local users.
- Accept either:
  - `new_password`;
  - `generate=1` and return generated password once in JSON/flash.
- Validate explicit password with hardened policy.
- Update password via `hash_password`.
- Record audit event `user_password_reset`.
- Invalidate target user's session if currently logged in.
- Add UI form/button on admin user page.
- Keep generated password display-once semantics.

Commit:

`feat(admin): Add local user password reset`

### T6 — Admin user management guards

Files:

- `lib/OpenQA/WebAPI/Controller/Admin/User.pm`
- `templates/webapi/admin/user/index.html.ep`
- `t/ui/31-local-auth.t`

Changes:

- Admin role update rejects system users.
- Admin role update rejects demoting the last remaining admin.
- Admin delete already rejects system; keep and test.
- Audit event data records actor username and old/new role where feasible.
- UI hides or disables actions for system users.

Commit:

`fix(admin): Guard privileged user management`

### T7 — Failed login auditing and rate limiting

Files:

- `lib/OpenQA/WebAPI/Auth/Local.pm`
- `lib/OpenQA/Shared/Controller/Session.pm`
- `lib/OpenQA/WebAPI.pm`
- `t/ui/31-local-auth.t`

Changes:

- Record failed login audit event `user_login_failed` when username exists or is syntactically valid.
- Do not store password or hash.
- Add simple in-memory rate limiter keyed by username/IP/session bucket.
- Return generic invalid credentials message.
- Add rate-limit test for repeated failed logins.
- Keep limiter conservative and test-friendly.

Commit:

`feat(auth): Audit and throttle failed local logins`

### T8 — API key revocation on admin password reset

Files:

- `lib/OpenQA/WebAPI/Controller/Admin/User.pm`
- `t/api/15-users.t`
- `t/ui/31-local-auth.t`

Changes:

- Admin password reset revokes all API keys for target user by default.
- Add optional `keep_api_keys=1` to skip revocation.
- Audit event records whether keys were revoked.
- Tests assert keys are gone after reset and retained when opted out.

Commit:

`feat(admin): Revoke API keys on password reset`

### T9 — Docs and config notes

Files:

- `docs/Installing.md`
- `docs/UsersGuide.md`

Changes:

- Document admin password reset.
- Document password policy and hashing preference.
- Document failed-login throttling and audit events.
- Document API key revocation behavior.

Commit:

`docs(auth): Document extended local user management`

### T10 — Integration sweep and coverage

Files:

- no new files unless fixes needed

Changes:

- Run targeted tests:
  - `t/40-password-hashing.t`
  - `t/ui/31-local-auth.t`
  - `t/api/15-users.t`
  - `t/06-users.t`
- Run `make check-line-coverage`.
- Fix any uncovered lines or missing tests.
- Commit only if fixes are needed.

Commit if needed:

`test(auth): Cover extended local user management`

## Sequencing

T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10.

Dependencies:

- T5 depends on T1/T2/T4.
- T6 depends on admin user route behavior.
- T8 depends on T5.
- T9 depends on final behavior.
- T10 verifies all.

## Risks

- Argon2 Perl module availability may vary; bcrypt fallback must remain.
- In-memory rate limiter is not a full security boundary but is enough for openQA's current architecture without adding a new dependency.
- Session invalidation may require a per-user session epoch because current session stores only username.
- Audit event schema may need `event_data` to carry actor details; avoid schema changes unless necessary.
