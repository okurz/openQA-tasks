# Task 069: Improve None Auth Maintainability

Refactor the "None" authentication implementation to address maintainability, style, and architectural concerns raised in the code review of commit b855eae79.

## Problem
1. **Encapsulation Leak**: `SharedHelpers.pm` has hardcoded knowledge of API headers.
2. **Brittle CSRF Logic**: CSRF bypass in `Auth.pm` relies on session presence.
3. **Procedural Code**: `Auth/None.pm` uses verbose check-and-update logic instead of declarative ORM features.
4. **Magic Strings**: 'admin' is hardcoded in multiple locations.

## Proposed Changes

### 1. Refactor `OpenQA::WebAPI::Auth::None`
- Use `update_or_create` in `auth_setup` for both the user and the API key.
- Define a constant for the default admin username.

### 2. Improve `OpenQA::Shared::Plugin::SharedHelpers`
- Move the detection of API credentials to a more generic check or delegate it.
- Ideally, `SharedHelpers` should not know about `X-API-Key`.
- Change: Check for `authorization` header and perhaps a generic "has custom auth headers" helper if possible. Actually, we can check if the request looks like an API request.

### 3. Refactor `OpenQA::Shared::Controller::Auth`
- Improve the CSRF check. Instead of checking `session->{user}`, check if the request is an "authenticated session" request (e.g. has a session cookie AND was authenticated via a session-based method).
- For `None` auth, it's tricky because there is no "login" step necessarily for API calls.

### 4. Code Style
- Ensure functional style in DB operations.
- Remove redundant comments.

## Verification Plan
- Run `make tidy` and `make test-checkstyle`.
- Run `t/03-auth.t`.
- Run API auth tests: `t/api/03-auth.t`.
- Manually verify that POST requests still work with `None` auth (both via browser and API).
