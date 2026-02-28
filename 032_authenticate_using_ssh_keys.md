# Implementation Plan - Task 32: SSH Key Authentication

Provide a way to authenticate using SSH keys instead of API key+secret for the openQA API.

## User Story

As an openQA user or developer, I want to authenticate my API requests using my existing SSH keys so that I don't have to manage another set of credentials (API key/secret) and can leverage the security of asymmetric cryptography.

## Proposed Architecture

### 1. Database Schema

A new table `ssh_keys` will be created to store public keys associated with users.

**Decision: Separate Table vs. Reusing Existing Tables**

- **Symmetric vs. Asymmetric:** `api_keys` stores symmetric secrets. `ssh_keys` stores public keys. Mixing them would lead to confusing column semantics (e.g., storing a public key in a "secret" column).
- **Multiple Keys:** A separate table naturally supports multiple keys per user (e.g., home vs. work) without cluttering the `users` table.
- **Metadata:** Allows storing SSH-specific metadata like `fingerprint` for efficient lookups and `comment` for user reference.
- **Maintainability:** Clear separation of authentication concerns simplifies logic in `OpenQA::Shared::Controller::Auth` and future schema migrations.

**Table `ssh_keys`**:

- `id`: BigSerial (Primary Key)
- `user_id`: BigInt (Foreign Key to `users.id`, ON DELETE CASCADE)
- `key`: Text (The public key, e.g., `ssh-ed25519 AAAAC3Nza...`)
- `fingerprint`: Text (SHA256 fingerprint for quick lookup)
- `comment`: Text (Optional comment from the key)
- `created_at`: Timestamp
- `updated_at`: Timestamp

### 2. Authentication Flow

We will introduce a new authentication method in `OpenQA::Shared::Controller::Auth`.

**Why Signing is Necessary**
A public key is, by definition, public. Simply providing it does not authenticate a user, as anyone could claim any user's public key. To authenticate, the client must prove possession of the corresponding private key. This is achieved by **signing** a "proof of identity" (a combination of request path and timestamp). This is the standard way to "conveniently reuse" SSH keys for stateless authentication without a challenge-response handshake.

**Required Headers**:

- `X-SSH-Key-Fingerprint`: The SHA256 fingerprint of the public key.
- `X-SSH-Signature`: A Base64-encoded signature of the payload.
- `X-SSH-Microtime`: A timestamp (same purpose as `X-API-Microtime`).

**Payload to Sign**:
The payload should be the concatenation of:

- The full request path (e.g., `/api/v1/jobs`)
- The `X-SSH-Microtime` value
- (Optional) A hash of the request body for POST/PUT requests.

**Verification on Server**:

1. Look up the `ssh_key` entry by the provided fingerprint.
2. Ensure the associated user exists.
3. Verify the signature using the stored public key.
4. Verify the timestamp is within a reasonable tolerance (e.g., 5 minutes).

### 3. Signature Verification Implementation

We can use `Crypt::PK::RSA` and `Crypt::PK::ED25519` (from `CryptX`) if they are available, or `ssh-keygen -Y verify` if we want to support any key type supported by the system's SSH.
Using `ssh-keygen -Y verify` requires creating a temporary "namespace" and using the SSH signature format.
Alternatively, we can use a Perl library that supports common SSH key types (RSA, ED25519).

## Implementation Steps

### Phase 1: Database & Models

1.  **Migration**: Create a new database migration to add the `ssh_keys` table.
    - Increment schema version in `OpenQA::Schema`.
    - Generate migration scripts using `script/upgradedb --prepare_upgrades`.
2.  **Schema Result**: Create `lib/OpenQA/Schema/Result/SshKeys.pm`.
3.  **User Relation**: Update `lib/OpenQA/Schema/Result/Users.pm` to add the `ssh_keys` relation.

### Phase 2: SSH Key Management

1.  **API V1**: Add endpoints to `OpenQA::WebAPI::Controller::API::V1::User`:
    - `GET /api/v1/users/me/ssh_keys`: List keys.
    - `POST /api/v1/users/me/ssh_keys`: Add a new key (validate public key format).
    - `DELETE /api/v1/users/me/ssh_keys/:id`: Remove a key.
2.  **Web UI**: Update the user profile page (`templates/user/index.html.ep`) to include a "SSH Keys" management section.

### Phase 3: Authentication Logic

1.  **Auth Controller**: Update `lib/OpenQA/Shared/Controller/Auth.pm`:
    - Implement `_ssh_auth`.
    - Integrate it into the `auth` method (check for `X-SSH-Key-Fingerprint`).
2.  **Signature Verification**: Implement a helper to verify signatures against a public key.

### Phase 4: Client Support & Documentation

1.  **Documentation**: Update API documentation to explain the new SSH authentication method.
2.  **Example**: Provide a script or update `openqa-client` to support signing requests with an SSH agent or a private key file.

## Verification Plan

### Automated Tests

- **Unit Tests**:
  - Test SSH public key parsing and fingerprint generation.
  - Test signature verification logic with various key types (RSA, ED25519).
- **Integration Tests**:
  - Test the full authentication flow using a test private/public key pair.
  - Test rejection of invalid signatures, expired timestamps, and unknown fingerprints.
  - Test API endpoints for key management.
- **UI Tests**:
  - Test adding and deleting SSH keys via the web interface.

### Manual Verification

- Add an SSH key via the UI.
- Use a `curl` command with a signed payload to verify authentication works as expected.
- Verify that deleting the SSH key revokes API access for that key.
