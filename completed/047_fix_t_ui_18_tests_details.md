# Execution Plan: Fix Sporadic Test Failure in t/ui/18-tests-details.t

## Analysis of the Problem

The test `t/ui/18-tests-details.t` sporadically fails on the "running job" subtests with the following errors:

- `liveview-loading is still hidden after tab switch`
- `liveview loading animation hides after live view starts`
- `running job`

Commit `44604a4e2` introduced "deferred rendering" for test tabs to handle cases where a user switches tabs while content is still loading.
In `assets/javascripts/test_result.js`:

1. When a tab is activated, it performs a `fetch` to load the content. If the user switches away from the tab before the fetch completes, the fetch continues in the background and the result is stored in `tabConfig._deferredResponse`.
2. When the user switches back to the tab, `activateTab` finds the `_deferredResponse` and calls `renderTabContent(tabConfig, response)`.
3. It then expects `renderTabContent` to return a Promise so it can call `.then()` to clear the `_deferredResponse`.
4. However, `renderTabContent` delegates to custom renderers (e.g., `renderLiveTab` for the Live View, `renderCommentsTab` for comments). These custom renderers typically return `undefined` instead of a Promise.
5. Because `renderTabContent` returns `undefined`, calling `.then()` on it inside `activateTab` throws a synchronous `TypeError: Cannot read properties of undefined (reading 'then')`.
6. This uncaught exception crashes the function before `tabConfig._deferredResponse = undefined` can execute.
7. Consequently, every subsequent time the user switches to the Live View tab, `activateTab` mistakenly believes it still needs to process the deferred response. It re-renders the Live View tab, repeatedly overwriting the DOM and recreating the `#liveview-loading` spinner in its default visible state.
8. This causes the UI tests to fail if the initial AJAX fetch for the Live View tab completed _after_ the first tab switch in the test script (which depends on server timing, perfectly explaining the sporadic nature).

## Proposed Fix

Modify `renderTabContent` in `assets/javascripts/test_result.js` to ensure it always returns a Promise. Wrapping the custom renderer call in `Promise.resolve()` will allow the `.then()` chain to safely execute, catching any errors and successfully clearing the `_deferredResponse` flag.

## Changes Required

### 1. `assets/javascripts/test_result.js`

Update the `renderTabContent` function to guarantee a Promise return value:

```javascript
function renderTabContent(tabConfig, response) {
  const customRenderer = tabConfig.renderContents;
  if (customRenderer) {
    return Promise.resolve(customRenderer.call(tabConfig, response));
  }
  tabConfig.panelElement.innerHTML = response;
  return Promise.resolve();
}
```

### 2. Clean up dead code (Optional but recommended)

In `deactivateTab`, there is unreachable code intended to abort the fetch:

```javascript
if (!tabConfig.initialized && tabConfig._abortController) {
  tabConfig._abortController.abort();
  tabConfig._abortController = undefined;
}
```

Because `tabConfig.initialized` is assigned a DOM Element object when initialization starts, `!tabConfig.initialized` is always `false`. If the intended behavior of the commit is to defer the rendering of the response rather than canceling the background fetch, this `abort()` call is both unreachable and contradictory to the deferred rendering design. It can be safely removed or refactored.

## Verification

- Run `make test-unit-and-integration TESTS=t/ui/18-tests-details.t` to ensure the sporadic failure is resolved. Running it repeatedly in a loop is recommended to prove the race condition is fixed.
- Check the browser JavaScript console while navigating between test tabs (like Live View, Details, Comments) to ensure no `TypeError` exceptions are thrown.
- Ensure `make tidy` and `make test-checkstyle` pass.
