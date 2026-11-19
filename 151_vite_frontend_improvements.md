# Task 101: Vite Frontend Improvements (Technical Debt)

With the foundational migration to Vite 8 complete, there are several logical follow-up tasks to further modernize the openQA frontend.

## 1. Eradicate Inline Scripts
Currently, there are many `<script>` blocks embedded directly inside Mojolicious `.ep` templates.
These should be moved to dedicated `.js` or `.ts` files inside `assets/javascripts/` (and imported via `assets/entry/` files). This allows them to be properly processed, minified, type-checked, and linted by Vite.

## 2. True ESM Modularization
During the initial migration, a pragmatic shortcut was taken to expose variables to the global scope (e.g., `window.testStatus = testStatus`) to satisfy legacy jQuery logic.
We should gradually phase out these global `window.*` assignments by refactoring the JavaScript files to explicitly use `import` and `export` statements. This will enable Vite to perform true "tree-shaking" and reduce the overall frontend bundle size.

## 3. Enable Hot Module Replacement (HMR)
The `OpenQA::Plugin::Vite` plugin contains basic logic to route requests to the Vite dev server (`npm run dev`). This can be enhanced to support seamless Hot Module Replacement (HMR). With HMR configured, developers will see sub-second UI updates without ever needing to manually reload the browser window or restart a build process locally.

## 4. Remove jQuery Dependency
As the codebase continues to modernize, we should gradually replace legacy jQuery AJAX (`$.ajax()`, `$.get()`) and DOM manipulation calls with native modern browser APIs (like `fetch()`, `document.querySelector()`, and `Element.classList`). This will drastically reduce load times and remove the need to bundle the heavy `core-vendor` chunk over time.
