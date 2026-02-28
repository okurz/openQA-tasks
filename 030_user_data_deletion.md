# Implementation Plan - Task 30: User Data Deletion / Anonymization

Offer each user to delete their user details on an openQA instance. As we track users in places like the audit log we should anonymize user entries there and remove when there is data that is only relevant for this user, e.g. api keys.

## User Story

As an openQA user, I want to be able to delete my personal data from the openQA instance so that I can exercise my right to data privacy and have my personal information removed from the system.

## Background

Currently, openQA has:

- User accounts with username, email, fullname, nickname stored in `users` table
- API keys stored in `api_keys` table (has `user_id` foreign key)
- Developer sessions stored in `developer_sessions` table (has `user_id` foreign key)
- Audit events in `audit_events` table (has `user_id` foreign key)
- Comments in `comments` table (has `user_id` foreign key)

The current implementation allows admin users to delete any user via `DELETE /api/v1/user/<id>`, but:

- No self-service user deletion exists
- No anonymization of audit logs occurs
- User-facing delete option is missing

## Data Handling Strategy

### Data to DELETE (user-specific, no historical value):

1. **API Keys** (`api_keys` table) - Not needed without user account
2. **Developer Sessions** (`developer_sessions` table) - Not needed without user account

### Data to ANONYMIZE (historical data must remain):

1. **Audit Events** (`audit_events` table) - Keep event record but replace user reference with "deleted user" placeholder
2. **Comments** (`comments` table) - Replace username with "deleted user" or keep username but anonymize email
3. **User entry** (`users` table) - Replace username, email, fullname, nickname with generic placeholders (e.g., "deleted-user-123")

## Proposed Architecture

### 1. Database Changes

**Option A: Soft Delete with Anonymization**

Add a new column to the `users` table:

- `deleted_at`: Timestamp (nullable) - marks when user requested deletion
- When `deleted_at` is set, treat user as "deleted" - username replaced with "deleted-user-{id}"

**Option B: Hard Delete with Cascade (NOT recommended)**

Simply delete user and rely on CASCADE - loses historical audit data.

**Recommendation**: Option A - Soft delete with anonymization preserves audit trail while complying with privacy requirements.

### 2. API Changes

Add new endpoints to `OpenQA::WebAPI::Controller::API::V1::User`:

- `POST /api/v1/users/me/request_account_deletion`: Request account deletion (triggers anonymization after grace period)
- `DELETE /api/v1/users/me`: Immediate account deletion with confirmation
- `GET /api/v1/users/me/deletion_status`: Check current deletion request status

### 3. Web UI Changes

Update user profile page (`templates/webapi/api_key/index.html.ep` or create new user profile page):

- Add "Delete My Account" section
- Show current deletion status if request pending
- Require confirmation dialog before deletion

## Implementation Steps

### Phase 1: Database & Schema

1. **Add deletion tracking column**:
   - Add `deleted_at` column to `users` table
   - Increment schema version in `OpenQA::Schema`

2. **Update User Result class** (`lib/OpenQA/Schema/Result/Users.pm`):
   - Add `is_deleted` method checking `deleted_at`
   - Add `anonymize` method for the anonymization process
   - Add relation for comments

### Phase 2: Backend Logic

1. **Create anonymization service** (`lib/OpenQA/Schema/ResultSet/Users.pm` or new module):
   - Method to anonymize audit events for a user
   - Method to anonymize comments for a user
   - Method to delete api_keys for a user
   - Method to end developer sessions for a user
   - Method to update user record with placeholder values

2. **Update User API controller** (`lib/OpenQA/WebAPI/Controller/API/V1/User.pm`):
   - Add `delete_self` action (authenticated user deletes own account)
   - Implement the full deletion/anonymization flow

### Phase 3: API Endpoints

1. **User self-deletion endpoint**:

   ```
   DELETE /api/v1/users/me
   ```

   - Requires authentication
   - Requires CSRF token for web, or proper auth for API
   - Anonymizes all user data as described above

2. **Admin-driven user deletion** (update existing):
   ```
   DELETE /api/v1/user/<id:num>
   ```

   - Update existing admin endpoint to use same anonymization logic instead of hard delete

### Phase 4: Web UI

1. **Create user profile page** (if not exists):
   - Currently there's no dedicated user profile; user settings are on `/api_keys` page
   - Add "Account Settings" or "Privacy" section

2. **Add deletion UI**:
   - "Delete My Account" button
   - Warning modal explaining what will happen to their data
   - Confirmation input field

### Phase 5: Tests

1. **Unit tests**:
   - Test anonymization of user data
   - Test audit event anonymization
   - Test comment anonymization

2. **API integration tests**:
   - Test user can delete own account
   - Test anonymized data appears correctly after deletion
   - Test admin delete uses same logic

3. **UI tests** (optional):
   - Test delete button appears for logged-in user
   - Test confirmation flow

## Edge Cases & Considerations

1. **Grace period**: Consider adding a configurable grace period (e.g., 30 days) during which user can cancel deletion request. This could be a follow-up enhancement.

2. **External auth providers**: If user authenticated via OpenID/OAuth, the external account remains - only local openQA data is affected.

3. **Admin users**: Admins should be able to delete their own account but this should warn about implications.

4. **Jobs created by user**: Job records typically don't have direct user_id reference, but jobs may have comments or be visible to users. This is already handled.

5. **Concurrent sessions**: When deleting, ensure any active sessions are invalidated.

## Verification Plan

### Automated Tests

1. **Unit Tests**:
   - `t/unit/openqa/schema/users.t`: Test anonymization methods

2. **API Integration Tests**:
   - `t/api/15-users.t`: Add tests for user self-deletion
   - Verify audit_events are anonymized
   - Verify api_keys are deleted
   - Verify comments are anonymized

### Manual Verification

1. Create a test user with API keys, comments, audit events
2. Verify user can access `/api_keys` page
3. Click "Delete My Account" and confirm
4. Verify:
   - User can no longer log in
   - API keys are gone
   - Audit logs show "deleted user" instead of username
   - Comments still exist but username is anonymized

## Files Likely to Change

- `lib/OpenQA/Schema/Result/Users.pm` - Add anonymization methods
- `lib/OpenQA/Schema/Result/AuditEvents.pm` - Possibly add anonymization helper
- `lib/OpenQA/Schema/Result/Comments.pm` - Possibly add anonymization helper
- `lib/OpenQA/WebAPI/Controller/API/V1/User.pm` - Add self-deletion endpoint
- `lib/OpenQA/WebAPI.pm` - Add route for user deletion
- `templates/webapi/api_key/index.html.ep` - Add delete account UI (or create new profile page)
- `t/api/15-users.t` - Add tests

## Related Tasks

- Task 31: Create a privacy policy (follow-up)
- Task 32: SSH key authentication (unrelated)
