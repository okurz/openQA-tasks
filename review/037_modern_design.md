# Task 037: Modernize openQA design and Bootstrap 5 migration

## Context

openQA currently uses Bootstrap 5.3.8. However, the codebase still contains many legacy patterns from earlier Bootstrap versions (3 and 4), and the design has remained largely the same for years. While functional, it could benefit from a "refresh" to look more modern and leverage the full capabilities of Bootstrap 5, especially its native color modes (dark mode).

## Goals

1.  **Full Bootstrap 5 Compliance**: Remove all remaining legacy classes and patterns.
2.  **Modern Aesthetic**: Update the UI with modern design trends (better spacing, subtle shadows, improved typography).
3.  **Clean Stylesheets**: Refactor SCSS to use Bootstrap 5 CSS variables and utility classes instead of heavy custom overrides.
4.  **Enhanced Dark Mode**: Better integration with Bootstrap 5's native dark mode support.

## Proposed Execution Plan

### 1. Audit and Cleanup

- [ ] **Identify legacy classes**: Search for and replace:
  - `.jumbotron` (replaced by utility classes or custom simplified divs)
  - `.hidden-*-*` / `.visible-*-*` (replaced by `.d-none .d-md-block`, etc.)
  - `.card-outline-*` (check if these are still the standard)
- [ ] **Templates**: Update `templates/webapi/layouts/bootstrap.html.ep` and other key templates to ensure they follow the latest Bootstrap 5 structure (e.g., removing unnecessary `container-fluid` wrappers if not needed).

### 2. SCSS Refactoring

- [ ] **Use CSS Variables**: Move custom colors from `openqa_theme.scss` to Bootstrap's CSS variable system (e.g., `--bs-primary`, `--bs-body-bg`).
- [ ] **Native Dark Mode**: Refactor `overall.scss` to use Bootstrap 5's `[data-bs-theme="dark"]` correctly, primarily by overriding Bootstrap SCSS variables instead of manual selector-based overrides.
- [ ] **Theming**: Consolidate `openqa_theme.scss` and `openqa.scss` to make it easier to maintain and extend themes.

### 3. Visual Refresh

- [ ] **Typography**: Review the use of "Roboto". Consider modern system font stacks or updating the Roboto implementation for better rendering.
- [ ] **Dashboard Update**: The main dashboard (`index.html.ep`) is the face of openQA. Propose a more compact yet informative layout using modern card designs.
- [ ] **Icons**: Evaluate "Fork-Awesome". Consider switching to a more modern and regularly updated icon set like Font-Awesome 6 Free or Lucide.
- [ ] **Spacing and Grids**: Increase whitespace where appropriate to reduce "visual noise".

### 4. Implementation Steps

1.  **Phase 1: Foundation**: Refactor `assets/stylesheets/openqa_theme.scss` to use Bootstrap 5 maps.
2.  **Phase 2: Cleanup**: Automated search & replace for legacy classes across all `.html.ep` files.
3.  **Phase 3: Component Refresh**: Redesign one key component at a time (Dashboard, Test Details, Admin pages).
4.  **Phase 4: Verification**:
    - Run `make tidy` and `make test-checkstyle`.
    - Manual UI verification in both light and dark modes.
    - Check responsiveness on various screen sizes.

## Verification Plan

- **Automated**:
  - `make tidy`
  - `make test-checkstyle`
  - `make test` (to ensure no functional breakage due to class changes)
- **Manual**:
  - Verify layout in Chrome, Firefox, and Safari.
  - Test dark mode toggle functionality.
  - Verify responsiveness on mobile/tablet viewports.
