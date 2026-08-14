# Task 070: Test None Auth CSRF Bypass for API

Ensure that API POST requests are not blocked by CSRF protection when using the "None" authentication provider.

## Motivation
A reported issue indicated that `openqa-clone-job` failed with "Bad CSRF token!" when using "None" auth. Although a fix was implemented, it lacked an explicit integration test to prevent regressions.

## Proposed Changes

### 1. Update `t/03-auth.t`
- Add a new subtest within the `None` subtest or as a separate subtest.
- Use `Test::Mojo` to perform a `POST` request to an API endpoint (e.g., `/api/v1/auth`).
- Include valid API headers (`X-API-Key`, `X-API-Hash`, `X-API-Microtime`).
- Do NOT include a `X-CSRF-Token` header or a session cookie.
- Assert that the response is NOT a 403 with "Bad CSRF token!".

## Verification Plan
- Run `make tidy` to ensure formatting.
- Run `prove -l t/03-auth.t` and ensure it passes.
- Temporarily revert the CSRF fix in `Auth.pm` to verify that the test fails as expected (red-green testing).
