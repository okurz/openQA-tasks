# 203 — Local user management (auth method `Local`)

## Context

openQA loads an auth provider dynamically from `auth.method` config (`lib/OpenQA/Setup.pm:553-565`): the class
`OpenQA::WebAPI::Auth::<Method>` must exist. Existing providers: `OpenID`, `OAuth2`, `Fake`, `None`. Each
provider implements the duck-typed contract consumed by `OpenQA::Shared::Controller::Session`:

- `auth_setup($server)` — optional init hook at startup (`Auth/None.pm` creates the default admin user)
- `auth_login($c)` — called by `session#create` (`/login` GET+POST, `lib/OpenQA/WebAPI.pm:119-122`); returns
  a hash: `(error => 0)` on success, `(error => msg)` on failure, `(manual => ...)` to stop without redirect
- `auth_logout($c)` — called by `session#destroy` (`/logout` GET+DELETE)
- `auth_response($c)` — only for redirect-based flows (OpenID); not needed for `Local`

Session state is just `$c->session->{user} = <username>`; `current_user` (`lib/OpenQA/Shared/Plugin/SharedHelpers.pm:52-70`)
resolves it via `Users->find({username => $id})`. CSRF is enforced centrally in `Session::_check_csrf_token` /
`Auth::_auth`. Users schema (`lib/OpenQA/Schema/Result/Users.pm`) has `username`+`provider` unique, no password
column, and already supports GDPR-style deletion via `anonymize`/`deleted_at`/`is_deleted`. `create_user`
(`lib/OpenQA/Schema/ResultSet/Users.pm`) rejects provider mismatches and makes the first user admin+operator.

## Design decisions

- New auth method `Local`, users stored with `provider => 'Local'`.
- Password stored in a new nullable `password` column on `users`, holding a bcrypt hash
  (`$2b$...`, cost 12) produced via `CryptX`'s `Crypt.bcrypt` — `perl(CryptX)` is already in
  `dist/rpm/openQA.spec` `main_requires`, so no new packaging dependency. Fallback to glibc
  `crypt()` SHA-512 (`$6$`) only if `Crypt.bcrypt` is unavailable at runtime.
- Registration is explicit: `POST /register` (form), not implicit on login. Password policy: ≥ 8 chars,
  no whitespace-only, reject username == password. Username policy: `^[A-Za-z0-9_.@+-]{3,64}$`.
- Login form rendered by `Auth::Local::auth_login` on GET (render form, return `(manual => 1)`), verified on
  POST. Constant-time comparison via `Mojo::Util::secure_compare` over the bcrypt verify result.
- Account deletion reuses `Users::anonymize` (sets `deleted_at`, strips personal data, keeps FK integrity).
  Own-account deletion via `POST /delete_account`; admin deletion via admin user page.
- All account mutations (register, password change, delete) write `AuditEvents` rows.
- API keys, Bearer tokens and HMAC API auth keep working unchanged — they are provider-agnostic.
- Frontend: login/register/change-password forms as new `templates/webapi/` pages; no inline JS (AGENTS.md).

## Atomic tasks (each = one commit, tests green at every step)

Work on branch `feature/104_local_user_management`. Gates after every commit: `make tidy`,
`make test-checkstyle`, `make test-gitlint`. Strict statement coverage: run touched tests with
`COVERAGE=1` then `make check-line-coverage`.

### T1 — Schema: password column

- `lib/OpenQA/Schema/Result/Users.pm`: add `password => { data_type => 'text', is_nullable => 1 }`.
- Fixture `t/fixtures/03-users.pl`: add a bcrypt-shaped dummy `password` to one user (verifies column
  round-trips through `Test::Case::init_data`).
- Tests: extend `t/06-users.t` with a subtest asserting the column exists, is nullable, and that
  `create({username => ...})` without password still works.
- Commit: `feat(users): Add password column to user schema`

### T2 — Password hashing helpers

- New `lib/OpenQA/WebAPI/Auth/Local.pm` skeleton with `hash_password($pw)` / `verify_password($pw, $hash)`
  using `Crypt.bcrypt` from CryptX; lazy `require` with `crypt()` SHA-512 fallback; `use` only what exists.
- Unit test `t/40-password-hashing.t` (data-driven, no in-file comments): hash/verify round-trip, wrong
  password fails, two hashes of same password differ (salt), fallback path exercised via mock.
- Commit: `feat(auth): Add bcrypt password hashing helpers`

### T3 — Auth::Local plugin: login/logout

- Implement `auth_login`: GET → render login form (username/password POST to `/login`), return
  `(manual => 1)`; POST → look up `Users` with `provider eq 'Local'`, `verify_password`, set
  `session->{user}`, return `(error => 0)`; unknown user / bad password → `(error => '...')` with
  identical message for both (no user-existence oracle).
- `auth_logout`: clear session like other providers.
- `auth_setup`: no-op (no auto-created user for Local).
- Login form template `templates/webapi/main/login.html.ep` (or reuse existing login rendering path);
  hidden CSRF input via existing `csrf_token` helper.
- Tests: new `t/ui/31-local-auth.t` — set `auth.method=Local` via config override (pattern from
  `t/ui/05-auth.t`), assert GET /login renders form, POST with valid creds logs in, invalid creds → 403,
  logout works.
- Commit: `feat(auth): Add Local auth provider plugin`

### T4 — Registration

- Route `POST /register` (named `register`) in `WebAPI.pm` near the login routes; handler in
  `Auth::Local` (or `Session`-adjacent controller): validate username/password policy, reject
  existing username (any provider), call `create_user(username, provider => 'Local', password => hash)`,
  write audit event `user_register`.
- Register form template; navbar link only when `auth.method eq 'Local'`.
- Tests: extend `t/ui/31-local-auth.t` — register first user becomes admin (existing `create_user`
  behavior), duplicate username → 403 with message, policy violations rejected, registered user can log in.
- Commit: `feat(auth): Add local user registration`

### T5 — Password change

- Route `POST /password_change` (named `password_change`), requires `ensure_user` + valid CSRF;
  re-hash, `user->update({password => ...})`, audit event `user_password_change`. Render the new
  password form page via GET on the same route for the browser flow.
- Tests: logged-in user changes password, old password no longer accepted, new one is; CSRF missing → 403.
- Commit: `feat(auth): Allow local users to change password`

### T6 — Account deletion (self + admin)

- `POST /delete_account` for the logged-in user: confirm-token param, then `user->anonymize` +
  invalidate session (`delete $c->session->{user}`), audit event `user_delete_account`.
- Admin route `POST /admin/user/<id>/delete` guarded by `ensure_admin`, same anonymize path.
- Guard: system user (`provider ''`, username `system`) must not be deletable via these routes.
- Tests: extend `t/ui/31-local-auth.t` — self-deletion anonymizes (`is_deleted` true, username becomes
  `deleted-user-<id>`), session invalidated, subsequent login impossible; system user deletion refused.
- Commit: `feat(auth): Support local account deletion`

### T7 — Admin user management page

- Extend `templates/webapi/admin/user/` pages: show provider, admin/operator flags, and (Local only)
  enable/disable buttons for promote/demote + delete action; POST endpoints under `ensure_admin`.
- Tests: new subtest in `t/ui/31-local-auth.t` (or `t/ui/31-admin-users.t` if cleaner): admin promotes
  operator, demotes, deletes another local user; non-admin gets 403.
- Commit: `feat(admin): Manage local user accounts`

### T8 — Config & docs

- `lib/OpenQA/Setup.pm`: nothing structural needed (method is free-form), but validate early:
  `Local` requires no oauth2/openid keys; add a startup warning if `auth.method eq 'Local'` and
  served over plain HTTP without `no_localhost_auth` (password forms need HTTPS in production).
- Docs: `docs/UsersGuide.md` (or the auth section wherever `auth.method` is documented) — document
  `auth.method=Local`, registration flow, password policy, deletion semantics.
- Commit: `docs(auth): Document local auth provider`

### T9 — Integration sweep & coverage

- Run `COVERAGE=1 make test-unit-and-integration TESTS='t/40-password-hashing.t t/ui/31-local-auth.t t/06-users.t'`
  then `make check-line-coverage`; close any uncovered lines in new/changed files.
- Ensure `t/ui/05-auth.t` and `t/api/03-auth.t` still pass untouched (provider-agnostic paths).
- No commit unless fixes were needed; if so: `fix(auth): ...`.

## Sequencing & dependencies

T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9. T4-T7 depend on T3's plugin; T7 depends on T6's delete
endpoint. T1 must land before T2/T3 because fixtures and `create_user` attrs touch the column.

## Risks / open questions

- bcrypt cost 12 blocks login for ~300 ms; acceptable for openQA's traffic, note in docs.
- `current_user` looks up by username only; a Local username colliding with an OpenID username is
  prevented by the `[username provider]` unique constraint only per-provider — registration must
  reject usernames already taken under any provider (implemented in T4).
- `Fake`/`None` remain the test-mode defaults; CI config must not switch to `Local` accidentally.
- Packaging: verify `Crypt.bcrypt` is present in the CryptX version pinned by the spec's
  `main_requires`; if not, T2's `crypt()` fallback is the shipped behavior.
