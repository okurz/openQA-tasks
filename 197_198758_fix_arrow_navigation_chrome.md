# Task: 037_198758_fix_arrow_navigation_chrome

## Ticket

- ID: 198758
- URL: https://progress.opensuse.org/issues/198758
- Title: Arrow navigation is not working in Chrome based browsers

## Problem

Regression: Left/right arrow keys don't work for navigating between needles on the /tests/<id> page in Chrome-based browsers. Works in Firefox.

## Root Cause Analysis

1. Found arrow key handling in `assets/javascripts/test_result.js:315` - function `handleKeyDownOnTestDetails`
2. Originally used deprecated `KeyEvent.DOM_VK_LEFT`, `KeyEvent.DOM_VK_RIGHT`, etc. via `e.which`
3. These constants are defined in `assets/javascripts/keyevent.js` but Chrome doesn't fully support them

## Fix

Instead of fixing the KeyEvent polyfill, the better approach is to use modern `e.key` property:

Changed `handleKeyDownOnTestDetails` in `assets/javascripts/test_result.js` to use:

- `e.key === 'ArrowLeft'` instead of `e.which === KeyEvent.DOM_VK_LEFT`
- `e.key === 'ArrowRight'` instead of `e.which === KeyEvent.DOM_VK_RIGHT`
- `e.key === 'Escape'` instead of `e.which === KeyEvent.DOM_VK_ESCAPE`
- `e.key === 'ArrowUp'` instead of `e.which === KeyEvent.DOM_VK_UP`
- `e.key === 'ArrowDown'` instead of `e.which === KeyEvent.DOM_VK_DOWN`

## Test Added

Added UI test in `t/ui/18-tests-details.t` to verify arrow key navigation works:

- Click on step link to select it
- Press right arrow to navigate to next step
- Press left arrow to navigate back to previous step

## Verification

- Ran `make tidy` - passed
- Ran `make test-checkstyle` - passed (pre-existing failures unrelated to this change)
- Ran arrow key navigation test: `make test-unit-and-integration TESTS=t/ui/18-tests-details.t` - passed (all 18 subtests)
