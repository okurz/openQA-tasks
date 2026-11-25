# Plan: Shim-less Migration to Font Awesome 6

This plan outlines the steps required to remove the `v4-shims.css` dependency and fully migrate the openQA codebase to native Font Awesome 6 syntax.

## Motivation

- Reduce bundle size by removing the compatibility shim.
- Align with modern CSS and Font Awesome standards.
- Future-proof the icon usage for upcoming FA updates.

## Design Choices

- **Prefix Transition**: Replace the universal `fa` prefix with style-specific ones (`fa-solid`, `fa-regular`, `fa-brands`).
- **Icon Renaming**: Map legacy Font Awesome 4 icon names to their Font Awesome 6 equivalents (e.g., `fa-trash-o` → `fa-regular fa-trash-can`).
- **Selector Updating**: Update Scss, JavaScript, and Perl files to use the new prefixes and icon names.

## Proposed Steps

### 1. Identify Icon Mappings

The following common legacy icons used in openQA need specific renaming:

- `fa-trash-o` → `fa-regular fa-trash-can`
- `fa-file-o` → `fa-regular fa-file`
- `fa-file-video-o` → `fa-regular fa-file-video`
- `fa-file-archive-o` → `fa-regular fa-file-zipper`
- `fa-undo` → `fa-solid fa-rotate-left`
- `fa-bolt` → `fa-solid fa-bolt-lightning`
- `fa-edit` → `fa-solid fa-pen-to-square`
- `fa-save` → `fa-solid fa-floppy-disk`
- `fa-times` / `fa-close` → `fa-solid fa-xmark`
- `fa-times-circle-o` → `fa-regular fa-circle-xmark`
- `fa-plus-square-o` → `fa-regular fa-square-plus`
- `fa-minus-square-o` → `fa-regular fa-square-minus`
- `fa-circle-o` → `fa-regular fa-circle`
- `fa-question-circle-o` → `fa-regular fa-circle-question`
- `fa-play-circle-o` → `fa-regular fa-circle-play`

### 2. Implementation Strategy

#### Phase A: Prefix Replacement

- Global replace of `fa fa-` with `fa-solid fa-` across the project as a baseline.
- Revert or adjust for `fa-brands` icons if any are discovered (e.g. `fa-github`).

#### Phase B: Selective Icon Renaming

- Run targeted `sed` or `edit` operations for icons with name changes (the list from Step 1).

#### Phase C: CSS Selector Update

- Update Scss files (e.g., `assets/stylesheets/test-details.scss`) to target `[class^="fa-"]` or specific new prefixes instead of `.fa`.

#### Phase D: Selenium Test Adaptation

- Update UI tests (`t/ui/*.t`) that search for elements by icon class names (e.g., `.fa-file-video-o`).

### 3. Verification

- Run `make tidy` to ensure no syntax errors were introduced.
- Run `make test-ui` to verify that test drivers can still find the updated icons.
- Inspect the UI manually (or via snapshots) to ensure no icons are missing or broken.

### 4. Final Cleanup

- Remove `../node_modules/@fortawesome/fontawesome-free/css/v4-shims.min.css` from `assets/assetpack.def`.
