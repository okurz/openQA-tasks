# Plan: 102 Badge Markdown Copy

## Motivation
Users often want to embed test or build status badges into external systems (like GitHub PRs, wikis, or external dashboards). Constructing the markdown snippet manually is tedious. Providing a built-in copy functionality improves user experience.

## Design Choices
1. **Dropdown UI for Copying:** Add a dropdown menu containing the Markdown snippet and an explanation text. This avoids cluttering the UI while keeping the snippet easily accessible.
2. **Locations:** 
   - Test Details (`templates/webapi/test/infopanel.html.ep`): Next to the "Result: " text.
   - Build Overview (`templates/webapi/test/overview.html.ep`): In the `#summary` card-body alongside the other filter/action buttons.
3. **Snippet Generation:**
   - Test Details: `[![Test Status](<%= url_for('test_result_badge', testid => $job->id)->to_abs %>)](<%= url_for('test', testid => $job->id)->to_abs %>)`
   - Build Overview: `[![Build Status](<%= url_with('tests_overview_badge')->to_abs %>)](<%= url_with->to_abs %>)`
4. **JavaScript Handler:** Add a generic copy handler in `assets/javascripts/openqa.js` that listens to `.copy-badge-btn`, reads the target input field, copies to clipboard via `navigator.clipboard.writeText`, and flashes a checkmark icon to provide feedback.
5. **Testing:** Adapt existing tests or add new checks to ensure the badges and dropdowns are present in the DOM.

## Benefits
- Simple, discoverable UX for obtaining badge markdown.
- Consistent approach for both individual tests and build overviews.

## Required Changes
1. **assets/javascripts/openqa.js**:
   - Add an event listener for `.copy-badge-btn` that prevents default, copies the value from `this.dataset.clipboardTarget`, and temporarily changes the icon to a checkmark (`fa-check text-success`) for 2 seconds.
2. **templates/webapi/test/infopanel.html.ep**:
   - Locate the area printing `Result: <b><%= $job->result %></b>`.
   - Append a Bootstrap dropdown with a "Badge" button.
   - Inside the dropdown menu, add the explanation text and an input group with the Markdown snippet and the `.copy-badge-btn`.
3. **templates/webapi/test/overview.html.ep**:
   - Locate the `<div class="card-body">` in the `#summary` div.
   - Add the same dropdown button style as in `infopanel.html.ep`, but using the `tests_overview_badge` and `url_with` helpers to construct the markdown.
4. **t/ui/10-tests_overview.t** (or similar):
   - Add a check for the existence of the badge copy button.
5. **t/ui/18-tests-details.t** (or similar):
   - Add a check for the existence of the badge copy button.
