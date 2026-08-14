# Task 085: poo176670 - Allow-list for OSD asset download

## Summary
Add an IP-based allow list for OSD asset downloads to allow certain hosts to access assets without authentication even when `require_for_assets` is enabled.

## Proposed Changes

### Configuration
- Add `assets_allowlist` to `[auth]` section in `openqa.ini`.
- It will be a space-separated list of IP addresses or CIDR blocks.

### Implementation
- Modify `OpenQA::Shared::Controller::Auth` to include an `is_assets_allowlisted` check.
- Add `auth_assets` method to `OpenQA::Shared::Controller::Auth`.
- Update `OpenQA::WebAPI` to use `auth_assets` for asset routes.

### Verification
- Add a new test file `t/api/05-auth_assets.t` or update `t/03-auth.t`.
- Test cases:
    - `require_for_assets = 0` (default): assets public.
    - `require_for_assets = 1`, no allowlist: assets restricted.
    - `require_for_assets = 1`, IP in allowlist: assets accessible without auth.
    - `require_for_assets = 1`, IP NOT in allowlist: assets restricted.

## Detailed Plan
1.  **Preparation**:
    - Study `OpenQA::Shared::Controller::Auth` and `OpenQA::WebAPI` routing.
    - Find a suitable way to match IP addresses/CIDR in Perl (maybe `Net::IP` or just simple prefix matching).
2.  **Implementation**:
    - Add `assets_allowlist` support in `OpenQA::Shared::Controller::Auth`.
    - Implement `auth_assets` in `OpenQA::Shared::Controller::Auth`.
    - Update `OpenQA::WebAPI::startup` to use `Auth#auth_assets`.
3.  **Testing**:
    - Create `t/api/05-auth_assets.t` mimicking `t/03-auth.t`.
    - Use `Test::MockModule` to mock remote IP address.
    - Verify different combinations of `require_for_assets` and `assets_allowlist`.
4.  **Polish**:
    - Run `make tidy` and `make test-checkstyle`.
    - Final verification.
