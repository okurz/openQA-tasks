# Implementation Plan - Address Review Comments on PR 6988

This plan outlines how to address the remaining feedback on [PR 6988](https://github.com/os-autoinst/openQA/pull/6988).

## Review Comments & Status

- [x] **Comment 1 (admintable.js:490):** Simplify `updateTextArea` invocation on query results.
  - _Status:_ Already addressed in the current branch.
- [ ] **Comment 2 (audit_log.js:309):** Streamline response parsing for AJAX/Fetch calls.
  - _Status:_ We propose to introduce a central `handleJSONResponse` helper in `assets/javascripts/openqa.js` to clean up the 15 repeated inline json/text parsing blocks.
- [ ] **Comment 3 (filter_form.js:12):** Restore smooth transition animation for filter-panel toggle.
  - _Status:_ We will utilize the Bootstrap 5 `bootstrap.Collapse` API on the card body, and adjust the custom stylesheet specificity so it does not block Bootstrap's transition.
- [x] **Comment 4 (filter_form.js:67):** Directly query select options.
  - _Status:_ Already addressed in the current branch.

## Proposed Design Choices

### 1. Zentralized Response Streamlining (Comment 2)

In `assets/javascripts/openqa.js`, we define a reusable helper:

```javascript
function handleJSONResponse(response) {
  return response
    .json()
    .then(json => ({response, json}))
    .catch(() => response.text().then(text => ({response, text})));
}
```

And then in `assets/javascripts/audit_log.js`, we refactor `rescheduleProduct` to use it:

```javascript
function rescheduleProduct(url) {
  fetchWithCSRF(url, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'X-Requested-With': 'XMLHttpRequest'
    }
  })
    .then(handleJSONResponse)
    .then(({response, json, text}) => {
      if (!response.ok || (json && json.error)) {
        throw json?.error || text || `Server returned ${response.status}: ${response.statusText}`;
      }
      const id = json.scheduled_product_id;
      const msg =
        typeof id === 'number'
          ? 'The product has been re-triggered as <a href="/admin/productlog?id=' + id + '">' + id + '</a>.'
          : 'Re-scheduling the product has been triggered.';
      addFlash('info', msg);
    })
    .catch(error => {
      addFlash('danger', 'Unable to trigger re-scheduling: ' + error);
    });
}
```

### 2. Smooth Animation with Bootstrap Collapse (Comment 3)

In `assets/stylesheets/overview.scss`, modify the selectors:

```scss
#filter-panel,
#developer-panel,
#live-log-panel,
#live-terminal-panel {
  .card-body:not(.collapse):not(.collapsing),
  .developer-mode-element {
    display: none;
  }
}
```

In `assets/javascripts/filter_form.js`, use the `bootstrap.Collapse` API:

```javascript
const cardHeader = document.querySelector('#filter-panel .card-header');
if (cardHeader) {
  cardHeader.addEventListener('click', function () {
    const cardBody = document.querySelector('#filter-panel .card-body');
    if (cardBody) {
      cardBody.classList.add('collapse');
      const bsCollapse = bootstrap.Collapse.getOrCreateInstance(cardBody, {toggle: false});
      bsCollapse.toggle();

      cardBody.addEventListener('shown.bs.collapse', function onShown() {
        cardBody.removeEventListener('shown.bs.collapse', onShown);
        if (document.getElementById('filter-panel').classList.contains('filter-panel-bottom')) {
          window.scrollTo({top: document.documentElement.scrollHeight, behavior: 'smooth'});
        }
      });
    }
  });
}
```

## Verification Plan

1. Run `make tidy` to verify code-style compliance.
2. Run `make test-checkstyle` to ensure checkstyle passes.
3. Run the UI tests specifically for the tests overview and dashboard to verify that no functional regressions were introduced:
   - `make test-unit-and-integration TESTS=t/ui/10-tests_overview.t`
