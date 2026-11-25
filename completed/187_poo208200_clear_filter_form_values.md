# Task 134: WebUI: Update filter to show previously selected form values, allow to clear filter

- Ticket: [poo#208200](https://progress.opensuse.org/issues/208200)
- Branch: `feature/134_poo208200_clear_filter_form_values`

## Requirements & Problem Statement

On openQA tests overview (e.g. `/tests/overview?build=...&groupid=...`), filtering jobs by module (e.g. `modules=ioctl_ficlone03`) results in the following issues:

1. When reopening the filter form, the "Module name" input field is empty instead of containing `ioctl_ficlone03`.
2. The filter panel header displays "no filter present, click to toggle filter form" instead of showing active filters.
3. Because the field is empty and `modules` was appended as a hidden input due to not being recognized as a form input, clearing the field and clicking "Apply" does not clear the filter.
4. There is no "Clear filter" button in the UI to easily reset active filters.

## Root Cause Analysis

1. In `assets/javascripts/overview.js`:
   ```javascript
   const input = document.getElementById('filter-' + key.replace(/_/g, '-')) || form.elements[key];
   ```
   For `modules`, `document.getElementById('filter-modules')` matches `<div class="row" id="filter-modules">` rather than `<input name="modules" id="modules">`. Since `div.value` is undefined, the input is never populated and `parseFilterArguments` treats `modules` as an unhandled parameter, creating an unwanted `<input name="modules" hidden>` and leaving the header as "no filter present".
2. In `templates/webapi/test/overview.html.ep` and `templates/webapi/main/index.html.ep`:
   Although `assets/javascripts/filter_form.js` had reset logic for `#filter-reset-button`, the button itself was never placed into the templates.
3. In `assets/javascripts/filter_form.js`:
   The reset button handler did not trigger a submit/reload event, requiring extra manual steps, and removed all `input[hidden]` elements which would lose page context parameters like `build` or `groupid`.

## Architecture & Proposed Solution

1. **Hydrate Form Elements Reliably**:
   In `assets/javascripts/overview.js`, resolve inputs via `form.elements[key]` first:
   ```javascript
   const input = form.elements[key] || document.getElementById('filter-' + key.replace(/_/g, '-'));
   ```
   This ensures form controls with matching name are chosen directly rather than wrapping layout `div` containers.
2. **Add Clear Filter Button**:
   Add `<button type="button" id="filter-reset-button" class="btn btn-secondary">Clear filter</button>` next to "Apply" in:
   - `templates/webapi/test/overview.html.ep`
   - `templates/webapi/main/index.html.ep`
3. **Enhance Reset Behavior**:
   In `assets/javascripts/filter_form.js`:
   - Clear input fields and chosen selects.
   - Preserve page context hidden inputs (`build`, `groupid`, etc.) instead of blind removal, so clearing filters remains on the current build/group overview.
   - Dispatch `submit` event on `filterForm` so filters are instantly cleared.
4. **Test Coverage**:
   - Update `t/ui/10-tests_overview.t` to assert that `modules` filter is populated in the form input.
   - Assert that the header updates to reflect the active filter (`current: ...`).
   - Assert that clicking `#filter-reset-button` clears the module filter and updates the URL and UI.
   - Ensure statement coverage is maintained (`make check-line-coverage`).

## Progress Log

- [x] Phase 1: Architecture & Planning (pro-architect)
- [x] Phase 2: Implementation (strata-builder - delegated from flash-builder)
- [x] Phase 3: Review & Fix-up (precision-fixer)
- [x] Phase 4: Final verification and commit (main agent)
