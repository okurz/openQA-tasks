# Implementation Plan - SSH Key Authentication

This plan describes how to implement SSH key-based authentication for the openQA WebAPI, allowing users to use their existing SSH keys instead of API keys/secrets.

## User Story

As an openQA user or administrator, I want to authenticate my API requests using my SSH private key (via `ssh-agent` or `ssh-keygen`), so that I don't have to manage and store separate openQA-specific API secrets.

## Proposed Changes

### 1. Database Schema

- Create a new table `ssh_keys` to store user public keys.
- Table structure:
  - `id` (BIGINT, PK, Auto-increment)
  - `user_id` (BIGINT, FK to `users.id`, NOT NULL)
  - `title` (TEXT, NOT NULL) - A descriptive name for the key.
  - `public_key` (TEXT, NOT NULL) - The OpenSSH public key string.
  - `last_used` (TIMESTAMP, NULLABLE)
  - `created_at`, `updated_at` (TIMESTAMPS)
- Migration: Add a new migration in `dbicdh/` to create this table.

### 2. Model Layer

- Create `OpenQA::Schema::Result::SshKeys`.
- Define relationships: `belongs_to` user.
- Update `OpenQA::Schema::Result::Users` to have many `ssh_keys`.

### 3. Web UI

- Update the API keys management page (`/api_keys` -> `OpenQA::WebAPI::Controller::ApiKey#index`).
- Add a new section for SSH keys.
- Implement `OpenQA::WebAPI::Controller::SshKey`:
  - `index`: List user's SSH keys.
  - `create`: Add a new SSH key (validate public key format).
  - `destroy`: Remove an SSH key.
- Update templates: `templates/webapi/api_key/index.html.ep` (or create a new one).

### 4. Authentication Logic

- Update `OpenQA::Shared::Controller::Auth`.
- Implement `_ssh_auth($reason, $key_title)`:
  1.  Look for headers: `X-SSH-Key-Title` (or `X-SSH-Key-ID`), `X-SSH-Signature`, and `X-API-Microtime`.
  2.  Retrieve the user's public key from the database by title.
  3.  Construct the data to verify (same as HMAC auth): `$base_path . $request . $remote_timestamp`.
  4.  Verify the signature using `ssh-keygen -Y verify`.
      - The server will need to write a temporary `allowed_signers` file for this check.
      - Signature should be in the `SSH SIGNATURE` format (OpenSSH 8.0+).
  5.  Update `last_used` timestamp on success.

### 5. Client Support (openqa-client)

- Add support for SSH signing in `OpenQA::RestClient`.
- Allow users to specify `--ssh-key` or automatically use `ssh-agent`.
- Signing command (example): `echo -n "$data" | ssh-keygen -Y sign -n openqa -f ~/.ssh/id_rsa`.

### 6. Verification Plan

#### Automated Tests

- **Unit Tests:**
  - Test `SshKeys` result set (CRUD operations).
  - Test public key validation logic.
- **Integration Tests:**
  - Add tests in `t/ui/13-admin.t` or similar for the new UI.
  - Create a new test file `t/api/20-ssh_auth.t`:
    - Mock `ssh-keygen` behavior to test signature verification.
    - Test with various key types (RSA, Ed25519) if possible in the test environment.
    - Verify that `last_used` is updated.
    - Verify that invalid signatures or expired timestamps are rejected.

#### Manual Verification

- Manually add an SSH key via the UI.
- Use a modified `openqa-client` or a curl command with a manually generated signature to verify authentication.
- Check the audit log to ensure the authentication is correctly attributed to the user.

## Dependencies

- OpenSSH 8.0+ on the server for `ssh-keygen -Y verify`.
- No new Perl dependencies required if we use `ssh-keygen`.

## Future Enhancements

- Support for multiple "namespaces" or "principals" in SSH signatures.
- Integration with system SSH keys if applicable.
