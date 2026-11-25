# Implementation Plan - Task 32: SSH Key Authentication

Provide a way to authenticate using SSH keys instead of API key+secret for the openQA API.

## User Story

As an openQA user or developer, I want to authenticate my API requests using my existing SSH keys so that I don't have to manage another set of credentials (API key/secret) and can leverage the security of asymmetric cryptography.

## Approvals

| Decision | Choice | Approver | Date |
|---|---|---|---|
| Key identifier header | `X-SSH-Key-Fingerprint` | okurz | 2026-11-12 |
| Signature verification | `ssh-keygen -Y verify`, namespace `openqa` | okurz | 2026-11-12 |
| Timestamp header | `X-SSH-Microtime` (separate from `X-API-Microtime`) | okurz | 2026-11-12 |
| Web UI placement | API keys page (`ApiKey#index`) with a dedicated `SshKey` controller | okurz | 2026-11-12 |
| Column naming | `public_key`, `title` | okurz | 2026-11-12 |
| Request body | SHA256 hash of body included in signed payload | okurz | 2026-11-12 |
| Key ownership | A key belongs to exactly one user; duplicate fingerprints are rejected | okurz | 2026-11-12 |
| Key types | Accept whatever `ssh-keygen` accepts; no extra openQA restriction | okurz | 2026-11-12 |
| Signer scope | `ssh-keygen` runs only in web UI/API workers, never Minion workers | okurz | 2026-11-12 |
| Replay protection | Out of scope; same 5-minute window as HMAC auth; listed under Future Enhancements | okurz | 2026-11-12 |
| Conflicting auth headers | Reject requests carrying both SSH and API-key headers | okurz | 2026-11-12 |
| Key expiration | None; keys live until deleted | okurz | 2026-11-12 |
| Role checks | `auth_operator`/`auth_admin` apply unchanged to SSH-authenticated requests | okurz | 2026-11-12 |
| Deletion on user anonymize | Delete SSH keys in `Users::anonymize` alongside `api_keys` (application-level, inside the same transaction) | okurz | 2026-11-12 |

## Proposed Architecture

### 1. Database Schema

A new table `ssh_keys` stores public keys associated with users.

**Decision: Separate Table vs. Reusing Existing Tables**

- **Symmetric vs. Asymmetric:** `api_keys` stores symmetric secrets. `ssh_keys` stores public keys. Mixing them would lead to confusing column semantics (e.g., storing a public key in a "secret" column).
- **Multiple Keys:** A separate table naturally supports multiple keys per user (e.g., home vs. work) without cluttering the `users` table.
- **Metadata:** Allows storing SSH-specific metadata like `fingerprint` for efficient lookups.
- **Maintainability:** Clear separation of authentication concerns simplifies logic in `OpenQA::Shared::Controller::Auth` and future schema migrations.

**Table `ssh_keys`**:

- `id`: BigSerial (Primary Key)
- `user_id`: BigInt (Foreign Key to `users.id`, ON DELETE CASCADE, NOT NULL; mirrors `api_keys_fk_user_id`)
- `public_key`: Text, NOT NULL (The OpenSSH public key, e.g. `ssh-ed25519 AAAAC3Nza...`)
- `fingerprint`: Text, NOT NULL, UNIQUE (SHA256 fingerprint for lookup; UNIQUE enforces one owner per key)
- `title`: Text, NOT NULL (Descriptive name for display)
- `last_used`: Timestamp, NULLABLE
- `created_at`, `updated_at`: Timestamps

### 2. Model Layer

- Create `OpenQA::Schema::Result::SshKeys` (`lib/OpenQA/Schema/Result/SshKeys.pm`) with a `belongs_to` relation to the user.
- Update `OpenQA::Schema::Result::Users` to have many `ssh_keys`.
- Update `OpenQA::Schema::Result::Users::anonymize` to delete `ssh_keys` in the same transaction as `api_keys`.
- Migration: increment the schema version in `OpenQA::Schema` and generate migration scripts with `script/upgradedb --prepare_upgrades` (the `dbicdh/` directory).

### 3. Authentication Flow

We introduce a new authentication method in `OpenQA::Shared::Controller::Auth`.

**Why Signing is Necessary**
A public key is, by definition, public. Simply providing it does not authenticate a user, as anyone could claim any user's public key. To authenticate, the client must prove possession of the corresponding private key by **signing** a "proof of identity" (request path, timestamp and body hash). This is the standard way to reuse SSH keys for stateless authentication without a challenge-response handshake.

**Required Headers**:

- `X-SSH-Key-Fingerprint`: SHA256 fingerprint of the public key.
- `X-SSH-Signature`: Base64-encoded signature in the SSH signature format.
- `X-SSH-Microtime`: Timestamp, same purpose as `X-API-Microtime` in HMAC auth.

**Payload to Sign**:

- The full request path (e.g., `/api/v1/jobs`), i.e. the same `$base_path . $request` used by HMAC auth
- The `X-SSH-Microtime` value
- SHA256 hash of the request body (empty-body hash for GET/DELETE)

**Verification on Server**:

1. Look up the `ssh_keys` entry by `X-SSH-Key-Fingerprint`; reject if absent.
2. Ensure the associated user exists.
3. Verify the signature with `ssh-keygen -Y verify` against a temporary `allowed_signers` file built from the stored `public_key`, namespace `openqa`.
4. Verify the timestamp is within the same tolerance as HMAC auth (`_is_timestamp_valid`, currently 5 minutes). Replay within this window is accepted (see Future Enhancements).
5. On success, update `last_used`.

### 4. Signature Verification Implementation

Use `ssh-keygen -Y verify`:

- Accepts whatever key types the system `ssh-keygen` accepts; openQA adds no key-type filter.
- Runs only in web UI/API worker processes; Minion workers never authenticate requests.
- Requests carrying both `X-SSH-Key-Fingerprint` and `X-API-Key`/`X-API-Hash` are rejected.
- Server writes a temporary `allowed_signers` file per check and uses the fixed namespace `openqa`.
- Requires OpenSSH 8.0+ on the server; no new Perl dependencies.

Client-side signing: `echo -n "$data" | ssh-keygen -Y sign -n openqa -f ~/.ssh/id_ed25519`.

## Implementation Steps

### Phase 1: Database & Models

1. Migration to add the `ssh_keys` table (see section 1).
2. Schema result class `SshKeys` and the `Users` relation.

### Phase 2: SSH Key Management

1. **API V1**: endpoints in `OpenQA::WebAPI::Controller::API::V1::User`:
   - `GET /api/v1/users/me/ssh_keys`: list keys
   - `POST /api/v1/users/me/ssh_keys`: add a key (validate public key format)
   - `DELETE /api/v1/users/me/ssh_keys/:id`: remove a key
2. **Web UI**: an "SSH Keys" section on the API keys page (`templates/webapi/api_key/index.html.ep`), backed by a new `OpenQA::WebAPI::Controller::SshKey` (`index`, `create`, `destroy`).
   - JavaScript goes in `assets/javascripts/`, not inline in templates.

### Phase 3: Authentication Logic

1. Update `lib/OpenQA/Shared/Controller/Auth.pm`:
   - Implement `_ssh_auth($reason, $key_fingerprint)`.
   - Dispatch to it from `auth` when `X-SSH-Key-Fingerprint` is present.
2. Implement the signature verification helper (section 4).

### Phase 4: Client Support & Documentation

1. Document the SSH authentication method in the API documentation.
2. Add SSH signing support to `OpenQA::RestClient` / `openqa-client` (`--ssh-key` option, or use `ssh-agent`).

## Verification Plan

### Automated Tests

- **Unit tests**:
  - Public key parsing and fingerprint generation.
  - `SshKeys` result set CRUD.
  - Signature verification with RSA and ED25519 keys.
- **Integration tests** (new `t/api/20-ssh_auth.t`):
  - Full authentication flow with a test key pair.
  - Rejection of invalid signatures, expired timestamps, tampered bodies, and unknown fingerprints.
  - `last_used` is updated on success.
  - Key management API endpoints.
- **UI tests** (e.g. `t/ui/13-admin.t`): add and delete SSH keys via the web interface.
- Every new or modified line must be covered: run with `COVERAGE=1` and `make check-line-coverage`.

### Manual Verification

- Add an SSH key via the UI.
- Send a request with a manually signed payload (curl or `openqa-client`) and confirm authentication.
- Confirm that deleting the key revokes API access for it.
- Check the audit log attributes the request to the correct user.

## Dependencies

- OpenSSH 8.0+ on the server (for `ssh-keygen -Y verify`).

## Future Enhancements

- Replay protection (nonce or per-key seen-timestamp cache).
- Key expiration (analogous to `t_expiration` on API keys).
- Support for multiple namespaces or principals in SSH signatures.
- Integration with system SSH keys, if applicable.

## Implementation Status

Branch `feature/032_oqa5_ssh_key_auth`, commits `aa7e5ef60`..`aaabdf387` plus
review fixes (`a10341cb3`, `dc92a796c`, and the follow-up fix commit).

| Phase | Status | Commits |
|---|---|---|
| 1. Database & models (`ssh_keys`, migration 108, anonymize cascade) | Done | `aa7e5ef60` |
| Signature helper `OpenQA::SSHKey` (ssh-keygen sign/verify) | Done | `b625bc1bf` |
| 3. Auth (`_ssh_auth`, conflict rejection, `last_used`) | Done | `6be23905f`, `2a04deaf2`, `a10341cb3` |
| 2. API endpoints (`/api/v1/users/me/ssh_keys`) | Done | `f316312dc` |
| 2. Web UI on API keys page (`SshKey` controller) | Done | `c49a48879` |
| 4. Client `--ssh-key` (`OpenQA::UserAgent`, `openqa-cli`) | Done | `9e3ad8102` |
| 4. Documentation (`docs/Client.md`) | Done | `00e575902` |

Verification:

- `make test-checkstyle` passes (tidy, perlcritic, pod, shellcheck, yaml, markdown, gitlint).
- Coverage: every new or modified function in the SSH path reports 100% in `codecov.json`.
- Per-file run of all 165 test files: 135+ pass; the remaining failures are pre-existing
  and also occur on the base commit `7c72e3d2f` (`t/14-grutasks-git.t`
  "clones added for distri"; `t/ui/10-tests_overview.t` 25s runtime guard).

Not done (outside the approved scope or needs a human):

- Manual verification against a live instance (UI add/delete, `openqa-cli --ssh-key` on a real host).
- Audit-log attribution check for SSH requests.
- Replay protection and key expiration stay in Future Enhancements, as approved.
