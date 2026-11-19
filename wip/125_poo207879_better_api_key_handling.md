# 125_poo207879: Better API Key Handling

## Context & Requirements

- Ticket: [Issue #207879](https://progress.opensuse.org/issues/207879)
- User Guidance: Consider a generic "comment field" instead of the proposal for a "name". Research industry best practices for API credential handling.

### Industry Best Practices Summary

- **Identification / Metadata:** Generic `comment` field allows human-readable context (bot name, machine, purpose, expiration rationale, owner contact) without enforcing artificial uniqueness.
- **Secret Lifecycle:** Secrets must be returned on creation (`POST /api/v1/users/me/api_keys`) so API creation is functional. In listing operations (`GET /api/v1/users/me/api_keys`), secrets must remain omitted. In the Web UI, secrets should not be exposed indefinitely.
- **HMAC Constraint:** openQA relies on HMAC-SHA1 request signing (`X-API-Hash`), requiring the plaintext secret on the server for signature verification.
- **Least Privilege Scoping:** Additional keys can have equal or lower permissions than the user's role ceiling.

## Implementation Phases

### Phase 1: Generic Comment Field & Functional API Key Creation

- [x] Schema Migration:
  - Add `comment` (`data_type => 'text', is_nullable => 1`) to `OpenQA::Schema::Result::ApiKeys`.
  - Bump `$VERSION` in `lib/OpenQA/Schema.pm` from 106 to 107.
  - Generate dbicdh migration files (`dbicdh/PostgreSQL/upgrade/106-107/001-auto.sql` and `dbicdh/PostgreSQL/deploy/107/001-auto.sql`).
- [x] REST API (`lib/OpenQA/WebAPI/Controller/API/V1/User.pm`):
  - In `create_api_key`: Accept optional `comment`, return `{id, key, secret, comment, t_expiration}`.
  - In `list_api_keys`: Include `comment` in returned list of keys (keep `secret` omitted).
- [x] Web UI (`lib/OpenQA/WebAPI/Controller/ApiKey.pm` and `templates/webapi/api_key/index.html.ep`):
  - In `ApiKey.pm -> create`: Accept `comment` parameter and pass to DB.
  - In `templates/webapi/api_key/index.html.ep`:
    - Add `comment` text input field in the creation form.
    - Add `Comment` column to the table displaying `$key->comment`.
- [x] Tests:
  - Update `t/api/15-users.t` to test `comment` in `create_api_key` and `list_api_keys`, and verify secret is returned on create.
  - Update `t/ui/04-api_keys.t` to verify `comment` in UI create and table display.
  - Update `t/07-api_keys.t` to verify `comment` column attribute.

### Phase 2: Role / Permission Scoping (Follow-up)

- [ ] Schema: Add `role` column to `ApiKeys` (`admin`, `operator`, `user`).
- [ ] Authentication: Stash `auth_api_key` in `Auth.pm`.
- [ ] Authorization: Cap permissions in `_is_operator` and `_is_admin` by key role ceiling.

### Phase 3: Credential Hygiene & Ephemeral Lifecycle (Follow-up)

- [ ] Mask secret in Web UI table and display only in one-time flash alert upon creation.
- [ ] Ephemeral key cleanup job.

## Progress & Status

- Architecture research & design completed via `pro-architect`.
- Branch `feature/125_poo207879_better_api_key_handling` created.
- Phase 1 implemented via `flash-builder` and reviewed/fixed via `precision-fixer`.
- Verified 100% statement coverage on modified lines, passed `make tidy` and `make test-checkstyle`.
- Split into two clean, atomic commits following conventional commits and project conventions:
  - Commit 1 (`ac9c2ce6f`): `fix: Return secret on API key creation`
  - Commit 2 (`45a4baccc`): `feat: Add comment field to API keys`
- All tests and linters verified (`make tidy`, `make test-checkstyle`, `make test-gitlint`, `make test-unit-and-integration`).
- No remote push performed.
