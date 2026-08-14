# Implementation Plan - Migrate from AssetPack to Vite 8 (Attempt 2)

This plan outlines the renewed effort to migrate the openQA asset pipeline from `Mojolicious::Plugin::AssetPack` to `Vite 8`.
The previous attempt failed due to stale dependencies, pathing issues in ES modules, and SCSS deprecations. This plan addresses those specific roadblocks against the current `master` branch.

## 1. Baseline Verification & Vite Setup

- [x] **Task:** Re-introduce Vite 8, Rolldown, and Dart Sass dependencies to `package.json`.
- [x] **Task:** Create a modern `vite.config.ts` mapping the 54+ asset bundles previously defined in `assetpack.def`.
- [x] **Constraint:** Ensure `chunkSizeWarningLimit` and `manualChunks` are configured to prevent large chunk warnings for `ace-builds` and `d3`.

## 2. Resolve Frontend Dependency Discrepancies

_The previous branch failed due to swapped or missing packages._

- [x] **Task:** Fix Icon Fonts: The SCSS tries to import `fork-awesome`, but `master` now uses `@fortawesome/fontawesome-free`. Update SCSS imports globally to reference FontAwesome.
- [x] **Task:** Fix `timeago.js`: Ensure the correct ES module import path for timeago is used instead of the legacy jQuery timeago path.
- [x] **Task:** Fix missing local scripts: Locate `keyevent.js` (or its successor) and fix the import paths in `assets/entry/bootstrap.js`.

## 3. Handle SCSS Deprecations

- [x] **Task:** Fix lightningcss pseudo-element bug (`::input-placeholder` -> `::placeholder`).
- [x] **Task:** Suppress or fix the `slash-div` deprecation in Dart Sass utilizing Vite's `silenceDeprecations: ['import', 'global-builtin', 'color-functions', 'if-function']`.

## 4. Mojolicious Plugin Integration

- [x] **Task:** Re-introduce `lib/OpenQA/Plugin/Vite.pm` to parse Vite's `manifest.json`.
- [x] **Task:** Map legacy `%= asset 'bootstrap.css'` calls in `.ep` templates to the new Vite helper, and implement a transparent fallback in the Vite plugin to serve the hashed files.
- [x] **Task:** Remove all `AssetPack` references from `lib/OpenQA/Assets.pm`.

## 5. UI JavaScript Compatibility (ESM Isolation)

_Vite uses `<script type="module">`, which isolates variables from the global scope and defers execution._

- [x] **Task:** Expose necessary libraries (e.g., `$`, `jQuery` via `@rollup/plugin-inject`) to the `window` object in `assets/entry/bootstrap.js` so that legacy inline scripts (`onclick="..."`) continue to function.
- [x] **Task:** Attach required openQA callbacks to `window` if they are dynamically invoked from HTML (e.g., `window.is_operator`, `window.restart_url`).

## 6. Selenium Test Adaptations

- [ ] **Task:** Fix `t/ui/10-tests_overview.t` test timeouts.
  - **Issue:** Scripts loaded via `<script type="module">` are deferred. Selenium fires click events (like submitting the filter form) _before_ `assets/javascripts/filter_form.js` has attached its `submit` event listener, causing the AJAX page update to never trigger or behave incorrectly.
  - **Next Step:** Add a specific synchronization flag (e.g., `document.body.dataset.jsLoaded = 'true'`) at the very end of `bootstrap.js` loading.
  - **Next Step:** Update `t/lib/OpenQA/SeleniumTest.pm`'s driver initialization or AJAX wait routines to always wait for this attribute before interacting with elements.
- [ ] **Task:** Run `make test-unit-and-integration TESTS="t/ui/*.t"` to ensure 100% UI test stability.

## 7. Cleanup & Polish

- [ ] **Task:** Ensure `make run-test-env` / `make run-webui-test-env` serves assets correctly.
- [ ] **Task:** Drop `Mojolicious::Plugin::AssetPack` from `cpanfile` and `dependencies.yaml` and tools like `generate-packed-assets`.
- [ ] **Task:** Run `make tidy` and check static analysis tests.
