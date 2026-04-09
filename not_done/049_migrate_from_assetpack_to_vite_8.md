# Implementation Plan - Migrate from AssetPack to Vite 8

This plan describes the migration of the openQA asset pipeline from the Perl-based `Mojolicious::Plugin::AssetPack` to `Vite 8` (using `Rolldown`). This migration will modernize the frontend build process, improve performance, and align with industry standards.

## User Story

As an openQA developer, I want to use modern frontend tooling (Vite, Sass, ES modules) so that I can develop and build the web UI more efficiently and leverage the modern JavaScript ecosystem.

## Current State (AssetPack)

- **Configuration**: Assets are defined in `assets/assetpack.def` (54+ bundles) and `assets/assetpack.yml`.
- **Processing**: Uses Perl modules (`CSS::Sass`, `JavaScript::Minifier::XS`) via AssetPack pipes.
- **Templates**: Assets are included using `%= asset 'bundle_name.ext'` and `icon_url 'name.png'`.
- **Build**: `tools/generate-packed-assets` triggers pre-generation during build/install.
- **Serving**: Assets are served from `public/asset/` with content-based checksums.

## Proposed Architecture (Vite 8)

- **Bundler**: Vite 8 with Rolldown as the default engine.
- **Integration**:
  - New Mojolicious plugin `OpenQA::Plugin::Vite` to replace `AssetPack`.
  - **Development**: Proxies asset requests to the Vite dev server (HMR enabled).
  - **Production**: Uses `manifest.json` to map logical names to hashed production files in `public/dist/`.
- **Asset Organization**:
  - Entry points will be created in `assets/entry/` for each bundle currently in `assetpack.def`.
  - Sass/SCSS will be processed by Dart Sass via Vite.

## Implementation Steps

### 1. Environment & Dependencies

- Update `package.json`:
  - Add `vite@^8.0.0`, `sass`, `postcss`, `autoprefixer` as dev dependencies.
  - Add scripts: `"dev": "vite"`, `"build": "vite build"`.
- Update `dependencies.yaml` and `cpanfile` to mark `Mojolicious::Plugin::AssetPack` and related Perl modules for removal.

### 2. Vite Configuration

- Create `vite.config.ts`:
  - Configure `root: 'assets'`.
  - Configure `build.outDir: '../public/dist'`.
  - Enable `build.manifest: true`.
  - Define `rollupOptions.input` for all 54 logical bundles (CSS, JS, and Images).
  - Configure `resolve.alias` to handle `node_modules` correctly.

### 3. Asset Restructuring & Entry Points

- Create a script (or manual process) to convert `assetpack.def` sections into Vite entry points.
- Example `assets/entry/bootstrap.scss`:
  ```scss
  @import 'bootstrap/scss/bootstrap';
  @import '../stylesheets/openqa';
  // ... other imports from assetpack.def
  ```
- Example `assets/entry/bootstrap.js`:
  ```javascript
  import 'jquery';
  import '../javascripts/openqa';
  import 'bootstrap';
  // ... other imports from assetpack.def
  ```

### 4. Mojolicious Integration

- Implement `lib/OpenQA/Plugin/Vite.pm`:
  - Add `vite` helper (to replace or supplement `asset`).
  - Logic to handle `manifest.json` in production.
  - **Robustness**: Ensure the manifest is found relative to the project root, even when `OPENQA_BASEDIR` is set (e.g., in `make run-webui-test-db`).
  - **Mapping**: Implement robust mapping from logical bundle names (e.g., `bootstrap.css`) to Vite manifest keys (e.g., `entry/bootstrap.scss`).
- Update `lib/OpenQA/Assets.pm` to register the new plugin and remove AssetPack.
- Update `lib/OpenQA/WebAPI/Plugin/Helpers.pm` to use the new system for `icon_url`.

### 5. SCSS & Build Optimization

- **Fix Deprecations**:
  - Migrate from `@import` to `@use` where possible.
  - Replace deprecated Sass functions like `darken()` and `lighten()` with `color.adjust()`.
- **Chunk Optimization**:
  - Configure `build.rollupOptions.output.manualChunks` in `vite.config.ts` to better distribute large libraries (like Ace or D3).
  - Adjust `chunkSizeWarningLimit`.

### 6. Verification & Bug Fixes

- **Fix Broken Assets**: Address the issue where assets are not served correctly in `test` mode (`make run-webui-test-db`).
- **Template Migration**: Ensure all templates use the unified `asset` or `vite` helpers.

### 7. UI Test & Script Execution Compatibility

- **Script Initialization Timing**: Vite's use of `<script type="module">` defers script execution until after HTML parsing. Ensure that UI components (e.g., search boxes, tables) are fully initialized before Selenium tests attempt to interact with them, or adjust scripts that assume immediate execution.
- **Global Scope Adjustments**: ES modules isolate variables to the module scope. Legacy inline event handlers (e.g., `onclick="doSomething()"`) or inter-script dependencies will fail. Explicitly attach required functions and variables (like `jQuery` or specific UI callbacks) to the global `window` object.
- **Test Adaptations**: Update Selenium tests (`t/ui/*.t`) to include explicit waits for elements or initialization states (e.g., waiting for specific DOM changes or a global readiness flag) that may now occur asynchronously due to module loading changes.

## Verification Plan

### Automated Tests

- **Unit Tests**: Create `t/99-vite.t` to verify the `Vite` plugin (manifest parsing, dev server detection).
- **Integration Tests**: Run `t/ui/*.t` to ensure the UI still renders correctly and all JS/CSS functionality is preserved.
- **CI**: Ensure `make generate-assets` passes in the CI environment.

### Manual Verification

1.  Run `npm run dev` and verify that the openQA UI works with HMR.
2.  Run `npm run build` and check the contents of `public/dist/`.
3.  Run openQA in `production` mode and verify that assets are loaded from hashed paths.

## Rollback Plan

- Revert changes to `lib/OpenQA/Assets.pm`.
- Restore `assetpack.def` and `assetpack.yml`.
- Revert `Makefile` and `package.json`.

## Dependencies

- Node.js 20+ (for Vite 8/Rolldown).
- Vite 8.
- Dart Sass.
