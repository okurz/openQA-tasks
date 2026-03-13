# Execution Plan: Make openQA handle requests for huge job groups gracefully

## Ticket Information

- **Ticket ID**: 196913
- **Title**: Make openQA handle requests for huge job groups gracefully
- **URL**: https://progress.opensuse.org/issues/196913
- **Priority**: Normal
- **Status**: Workable
- **Assignee**: okurz

## Problem Statement

Issue #196709 revealed that openQA o3 instance yields 502 errors when accessing huge job groups. Job group 132 "Investigation" contains more than 10k jobs, causing significant performance issues.

## Acceptance Criteria

- **AC1**: openQA handles job group retrievals gracefully regardless of the amount of included jobs

## Background

From recent journal entries:

- A PR (#7026) has been created addressing this issue
- The overview page already has a limit of 2000 results with a warning message: "Only 2000 results included, please narrow down your search parameters."
- The same approach should be applied to job group (/group_overview and
  /parent_group_overview) and index pages (/)

## Execution Steps

### Phase 1: Understanding the Current Implementation

1. **Examine existing limit on overview page**
   - Locate where the 2000 result limit is implemented for overview pages
   - Understand the warning message mechanism
   - Identify the code paths that trigger the limit

2. **Identify job group and index page endpoints**
   - Find the controllers/routes handling job group pages (/group_overview and
  /parent_group_overview)
   - Find the controllers/routes handling job group index pages (/) in lib/OpenQA/WebAPI/Controller/Main.pm
   - Map the data flow from database to template rendering

### Phase 2: Code Analysis

3. **Analyze relevant database queries**
   - Find queries that fetch jobs for job groups
   - Identify N+1 query patterns or missing pagination
   - Check for eager loading of related data

4. **Examine Perl controller logic**
   - Review the job group controllers (likely in `lib/OpenQA/WebAPI/Controller/`)
   - Check for any existing limit mechanisms
   - Identify where result set truncation could be added

5. **Review template rendering**
   - Examine job group templates (likely in `templates/` directory)
   - Identify where results are displayed
   - Determine where warning messages should be inserted

### Phase 3: Implementation

6. **Implement result limiting for job group pages**
   - Add similar 2000 limit as used on overview page
   - Add warning message when results are truncated
   - Ensure consistent behavior across all job group views

7. **Implement result limiting for job group index**
   - Apply same limiting logic to job group listing
   - Consider group hierarchy (parent/child groups)

8. **Handle edge cases**
   - Empty job groups
   - Groups with exactly 2000 jobs
   - API endpoints that return job group data

### Phase 4: Testing

9. **Create or update unit tests**
   - Test the limiting behavior
   - Test warning message display
   - Test edge cases

10. **Create integration test**
    - Simulate large job group scenario
    - Verify graceful handling with proper limits

### Phase 5: Verification

11. **Run existing test suite**
    - Ensure no regressions
    - Fix any broken tests

12. **Verify code quality**
    - Run `make tidy`
    - Run `make test-checkstyle`

## Implementation Notes

- Reuse existing pattern from overview page (`limit` parameter + warning message)
- Consider adding a configurable limit (default 2000) for maintainability
- Ensure error messages are user-friendly and localized

## References

- Related issue: #196709
- Existing PR: #7026
- Related pattern: Overview page result limiting (already implemented)
