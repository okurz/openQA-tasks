# Execution Plan: Improve responsiveness of tabs in job view

## Ticket Information

- **Ticket ID:** 196991
- **URL:** https://progress.opensuse.org/issues/196991
- **Status:** Workable
- **Priority:** Normal
- **Assignee:** okurz

## Problem Statement

When opening big openQA test jobs with many test modules (e.g. ltp_syscalls), users see a "Loading test modules…" spinner. This blocks clicking on other linear tabs (Logs & Assets, Settings, Investigation, Comments, Next & previous results) until the entire test is loaded, which can take up to 1 minute.

## Acceptance Criteria

| ID  | Criterion                                                                                                                     | Verification                                                                          |
| --- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| AC1 | "Big jobs" do not prevent switching to other test details tabs while loading (during AJAX request and client-side processing) | Manual test with a large job (1000+ modules), verify tabs are clickable while loading |
| AC2 | Test details for small jobs are as easily accessible as before                                                                | Manual test with a small job (100 modules), verify no regression in load time         |

## Suggested Approaches

### Option A: Async Tab Switching with Loading Cancellation

- Implement abortable AJAX requests for test modules
- When clicking a different tab, cancel the ongoing modules loading
- Allow background loading to continue for the newly selected tab

### Option B: Incremental/Rendered-on-Demand Details

- Only render module details when explicitly requested
- Add "Load details" button for "big jobs" (> threshold, e.g. 500 modules)
- Show module list without full rendering initially

### Option C: Chunked DOM Insertions

- Split large DOM insertions into smaller chunks using requestAnimationFrame or setTimeout
- Allow event loop to run between chunks to keep UI responsive
- Show progress indicator during chunked loading

## Implementation Plan

### Phase 1: Investigation and Analysis

- [ ] Research existing code for job details tab loading in the codebase
- [ ] Identify the code that loads test modules (Perl backend + JavaScript frontend)
- [ ] Find how tabs are currently implemented
- [ ] Identify the AJAX endpoint for loading test modules
- [ ] Locate the JavaScript code handling tab switches

### Phase 2: Implementation

- [ ] Choose approach based on complexity vs benefit analysis
- [ ] Implement loading cancellation for tab switches (if Option A)
- [ ] OR implement chunked DOM insertion (if Option C)
- [ ] OR implement on-demand details loading (if Option B)
- [ ] Add appropriate UI feedback (loading state for active tab)

### Phase 3: Testing

- [ ] Create or update unit tests for the new functionality
- [ ] Manual testing with a large job (e.g., LTP syscall tests)
- [ ] Verify no regression for small jobs
- [ ] Test tab switching behavior during and after loading

### Phase 4: Cleanup and Documentation

- [ ] Ensure code passes `make tidy` and `make test-checkstyle`
- [ ] Update any relevant documentation
- [ ] Verify all tests pass

## Technical Notes

### Key Files to Investigate

- Job details templates (likely in templates/)
- JavaScript for tab handling
- Controller/backend code for test module loading
- AJAX routes for job details

### Testing Data

- Use LTP syscall tests or similar large job for testing
- Consider openqa.opensuse.org group 132 (Investigation) with >10k jobs as mentioned in journals

### Related Journal Notes

- 2026-02-23: Task tracking in feature branch
- 2026-02-28: Related issue with overview page and large job groups - consider using similar approach as overview page (2000 result limit)
