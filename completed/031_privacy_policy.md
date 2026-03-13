# Task 31: Create Privacy Policy

## Objective

Create a privacy policy for openQA following industry best practices.

## Context

openQA stores limited user data and needs a privacy policy to inform users about:

- What data is collected
- How data is used
- How data is protected
- User rights regarding their data

## Research Phase

### 1. Inventory User Data in openQA

**Completed - Findings:**

| Database Table       | Data Collected                                                         |
| -------------------- | ---------------------------------------------------------------------- |
| `users`              | username, email, fullname, nickname, is_operator, is_admin, timestamps |
| `api_keys`           | key (hashed), secret (hashed), expiration date                         |
| `comments`           | text, job_id/group_id, user reference, flags                           |
| `audit_events`       | event type, event_data (JSON), user_id, connection_id                  |
| `developer_sessions` | job_id, user_id, ws_connection_count                                   |
| `job_settings`       | key/value pairs for job configuration                                  |
| Session data         | Mojo session store (user_id, login time)                               |

No third-party data sharing identified in codebase.

### 2. Review Industry Best Practices

**Completed:**

- Privacy policy sections aligned with GDPR requirements
- Standard sections: data collection, usage, protection, sharing, user rights, cookies, changes
- GDPR compliance requires clear disclosure and data access/deletion rights

### 3. Examine Existing openQA Documentation

**Completed:**

- No existing privacy policy found
- Task 30 (user deletion with anonymization) is implemented and should be referenced

## Planning Phase

### 4. Define Policy Sections

**Recommended Sections (based on research):**

1. **Introduction**
   - What is openQA
   - Purpose of privacy policy

2. **Data We Collect**
   - Account data: username, email, fullname, nickname
   - Authentication: API keys (hashed), session data
   - Activity: comments, job settings, audit events
   - Developer sessions: job debugging activity

3. **How We Use Your Data**
   - Service operation and job execution
   - Account management and authentication
   - Audit logging for security
   - No marketing or third-party advertising

4. **Data Protection**
   - Passwords/secrets stored encrypted
   - Access controls and authentication
   - Audit logging of changes
   - Anonymization on account deletion (Task 30)

5. **Data Sharing**
   - No third-party data sharing
   - Legal requirements exception

6. **User Rights**
   - Right to access personal data
   - Right to correction/deletion (via Task 30 feature)
   - Data portability (via API)
   - Contact for privacy inquiries

7. **Cookies and Tracking**
   - Session cookies for authentication
   - No third-party analytics

8. **Policy Changes**
   - Version history
   - Effective date

### 5. Implementation Approach

**Decision: Option A** - Keep as AsciiDoc in docs/, link from web UI

**Implementation locations identified:**

1. **Footer** (`templates/webapi/layouts/bootstrap.html.ep`)
   - Add link in footer-legal section

2. **User Settings / API Keys page** (`templates/webapi/api_key/index.html.ep`)
   - Add link near the "Delete My Account" section (line 43-59)
   - This is where users manage their account and see data deletion info

3. **Documentation links**
   - Use pattern: `https://open.qa/docs/PrivacyPolicy.html` or similar
   - Instance operators can configure custom URL if needed

## Documentation Phase

### 6. Draft Privacy Policy

**Completed:**

- Privacy policy document created at `docs/PrivacyPolicy.asciidoc`
- Uses clear, accessible language
- Includes specific data examples from inventory
- References Task 30 (user deletion) for data removal rights
- Covers all 8 defined sections

### 7. Create Supporting Materials

- [ ] Document internal processes for data requests (optional)
- [ ] Prepare brief FAQ for common privacy questions (optional)

## Review Phase

### 8. Review

- [ ] Self-review for completeness and accuracy
- [ ] Verify GDPR compliance alignment
- [ ] Check for regional requirements (CCPA, etc.)

## Implementation

### 10. Deploy Policy

**Implementation steps:**

1. **Add link to footer**
   - File: `templates/webapi/layouts/bootstrap.html.ep`
   - Add privacy policy link in footer-legal section

2. **Add link to user settings**
   - File: `templates/webapi/api_key/index.html.ep`
   - Add link near "Delete My Account" section (references Task 30)

3. **Verify documentation build**
   - Ensure `docs/PrivacyPolicy.asciidoc` is included in docs index

## Verification

### 11. Testing

- [ ] Verify footer link renders correctly
- [ ] Verify user settings link is visible near account deletion
- [ ] Check that docs/PrivacyPolicy.asciidoc is accessible via docs build
- [ ] Verify links open correctly in new tab

## Notes

- Coordinate with Task 30 (user deletion feature) as privacy policy should reference user rights
- Consider privacy policy as living document requiring periodic review
- May need to update as new features collect additional user data
