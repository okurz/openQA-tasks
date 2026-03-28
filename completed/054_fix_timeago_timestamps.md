# Plan: Fix timeago timestamps showing "just now"

## Background

PR #7126 replaced jQuery timeago plugin with timeago.js (vanilla JS) for jQuery 4 compatibility. However, all timestamps started showing "just now" - indicating the timestamps aren't being parsed correctly.

PR #7188 reverted #7126 due to this issue.

## Root Cause

The timeago.js library expects proper ISO 8601 datetime format. In several places, timestamps are passed incorrectly:

1. **audit_log.js:123**: `timeago.format(data + ' UTC')` - Adding ' UTC' creates invalid format like "2026-03-25T12:00:00.000 UTC" which timeago.js cannot parse
2. **audit_log.js:366**: `timeago.format(data + 'Z')` - May work but inconsistent

The timestamps from templates use format like `2026-03-25T12:00:00` (ISO without timezone). Adding 'Z' makes it valid ISO 8601.

## Implementation Steps

### 1. Identify all timeago.js usages

Search all JS files for `timeago.format(` to find all call sites:

- `assets/javascripts/openqa.js`
- `assets/javascripts/running.js`
- `assets/javascripts/tests.js`
- `assets/javascripts/job_next_previous.js`
- `assets/javascripts/comments.js`
- `assets/javascripts/audit_log.js`
- `assets/javascripts/admin_needle.js`

### 2. Fix timestamp format in each file

**audit_log.js:123** - Change `timeago.format(data + ' UTC')` to `timeago.format(data + 'Z')`

**audit_log.js:366** - Already uses `data + 'Z'`, verify correctness

**openqa.js:459** - Check how `job.t_finished` is passed

**running.js:752** - Check how timestamp is passed

**tests.js:125** - Check format

**comments.js:17** - Check format

**admin_needle.js:33** - Check format `new Date(data)` - may need adjustment

### 3. Test the changes

Run UI tests to verify timestamps display correctly:

```bash
make test-unit-and-integration TESTS=t/ui/15-admin-workers.t
make test-unit-and-integration TESTS=t/ui/16-activity-view.t
```

### 4. Verify no regressions

Run full UI test suite or at least tests that use timeago:

- t/ui/15-comments.t
- t/ui/15-admin-workers.t
- t/ui/25-developer_mode.t
- t/ui/16-activity-view.t

## Expected Outcome

After fix, timestamps should display proper relative time (e.g., "2 hours ago", "1 day ago") instead of "just now".

## Alternative Approaches

If timestamp format conversion is too scattered, consider:

- Creating a centralized helper function that handles format conversion
- Using `new Date(data)` explicitly where needed
- Using timeago.js's built-in parsing capabilities properly
