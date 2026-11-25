# Plan: 103_poo207639_fix_developer_mode_test

## Motivation

`t/33-developer_mode.t` fails intermittently because `open_new_tab($url)` runs asynchronously, and when switching to the tab immediately, the page hasn't finished loading yet. Checking the title right after switching leads to empty title (`got: ''`), and finding `#content` throws a fatal element-not-found exception.

## Design Choices

1. In `t/33-developer_mode.t`, wait for `#content` to be present (using `wait_for_element`) after switching to the second tab. This ensures the page loaded successfully. Then, perform title assertion and get the content text from the returned element.
2. The same vulnerable pattern exists in `t/ui/26-jobs_restart.t` when switching to a second tab. Fix those 5 occurrences to use `wait_for_element` instead of directly calling `$driver->find_element`.
3. Fix a fundamental bug in `wait_for_ajax` helper in `t/lib/OpenQA/SeleniumTest.pm` where pages without jQuery (such as the Needle Editor) would block and time out for 30 seconds due to `window.jQuery` being undefined.

## Tasks

### Phase 1: Implementation

- [x] Implement waiting logic in `t/33-developer_mode.t`
- [x] Implement waiting logic in `t/ui/26-jobs_restart.t`
- [x] Fix the latent bug in `wait_for_ajax` in `t/lib/OpenQA/SeleniumTest.pm` to allow pages without jQuery to return immediately

### Phase 2: Verification

- [x] Run `make tidy` and checkstyle
- [x] Run unit and integration tests: `make test-unit-and-integration TESTS="t/33-developer_mode.t t/ui/26-jobs_restart.t"`
- [x] Verify statement coverage using `COVERAGE=1` and `cover`

## Results and Status

- All code changes implemented cleanly without adding any in-file comments.
- Formatted and validated with `make tidy` and `SKIP_UPDATE_DEPS=1 make test-checkstyle`.
- Both modified test suites passed 100% cleanly:
  - `t/33-developer_mode.t` (PASS)
  - `t/ui/26-jobs_restart.t` (PASS)
