# Task: Fix "None" auth provider API access and redundant DB writes

Problem:
The "None" authentication provider implementation in d96d5c3e1 causes two main issues:

1. API clients making POST/PUT/DELETE requests fail with "Bad CSRF token!" because they are automatically identified as 'admin' by the `current_user` helper, triggering CSRF protection.
2. The `current_user` helper performs database writes (`create_user`, `update`) on every request if the user is missing or not fully privileged, which is inefficient and breaks in read-only environments.

Proposed Changes:

1. Modify `lib/OpenQA/Shared/Plugin/SharedHelpers.pm` to:
   - Only default to 'admin' user if there's no session AND it's NOT an API request (no Authorization/X-API-Key headers).
   - Remove `create_user` and `update` calls from the helper. Rely on `auth_setup` to have provisioned the user.
2. Update `lib/OpenQA/WebAPI/Auth/None.pm` to ensure `auth_setup` is idempotent and handles potential race conditions during startup.

Verification:

1. Run the repro test `t/99-repro-issue.t` (should pass after fix).
2. Run existing auth tests `t/03-auth.t`.
3. Verify that UI still works without login when `auth = None`.
