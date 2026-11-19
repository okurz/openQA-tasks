# Task 118: Rework jQuery Removal Branch

## Problem Analysis

The current branch (`feature/007_remove_jquery`, 13 commits on top of `d0f6556ad`) contains:

- Duplicate commit messages (e.g., two `refactor(ui): remove jQuery from admin and log scripts`, two `refactor(ui): remove jQuery from complex interactive scripts`).
- Trailing `fix(ui): ...` commits (`f1d7f7575`, `f1a73ea62`, `9fdfded5f`) that cannot cleanly be squashed into their respective refactoring commits via `git rebase -i` or `git commit --fixup`.
- Conflicts arise because multiple files (`openqa.js`, `needleeditor.js`, `test_result.js`, `job_templates.js`, `admintable.js`, `running.js`, `ws_console.js`) were modified across multiple interleaved commits, and the fix commits were authored against the state after commit 10 (`c15e2c5ea`).
- Commit messages lack required multi-line body headings (`Motivation:`, `Design Choices:`, `Benefits:`).

## Proposed Atomic Commit Structure

Restructure the 42 modified files across 7 clean, independent, atomic commits:

### 1. `refactor(ui): remove jQuery helpers from core openqa utilities`

- **Files**:
  - `assets/javascripts/openqa.js`
  - `assets/javascripts/filter_form.js`
- **Scope**: Core DOM selection, fetch helpers, and generic form filtering utilities.

### 2. `refactor(ui): remove jQuery from admin and audit log scripts`

- **Files**:
  - `assets/javascripts/admintable.js`
  - `assets/javascripts/admin_assets.js`
  - `assets/javascripts/admin_groups.js`
  - `assets/javascripts/admin_needle.js`
  - `assets/javascripts/admin_user.js`
  - `assets/javascripts/admin_worker.js`
  - `assets/javascripts/audit_log.js`
  - `templates/webapi/admin/workers/show.html.ep`
  - `t/ui/15-admin-workers.t`
  - `t/ui/21-admin-needles.t`
- **Scope**: Administration views, tables, asset management, and worker administration.

### 3. `refactor(ui): remove jQuery from needle editor and diff tools`

- **Files**:
  - `assets/javascripts/needleeditor.js`
  - `assets/javascripts/needlediff.js`
  - `assets/javascripts/shapes.js`
  - `t/ui/12-needle-edit.t`
- **Scope**: Needle editor, canvas/shape manipulation, needle diffs, and corresponding UI tests (integrating `f1d7f7575`).

### 4. `refactor(ui): remove jQuery from group overview and live monitoring`

- **Files**:
  - `assets/javascripts/overview.js`
  - `assets/javascripts/parent_group_overview.js`
  - `assets/javascripts/running.js`
  - `assets/javascripts/ws_console.js`
  - `assets/javascripts/comments.js`
  - `assets/javascripts/fullscreen.js`
  - `assets/javascripts/obs_rsync.js`
  - `assets/javascripts/render.js`
  - `assets/stylesheets/overview.scss`
  - `templates/webapi/main/group_overview.html.ep`
  - `templates/webapi/main/parent_group_overview.html.ep`
  - `t/ui/15-comments.t`
  - `t/ui/16-activity-view.t`
- **Scope**: Live job status, WebSocket console, job comments, full-screen view, and overview pages (integrating `f1a73ea62`).

### 5. `refactor(ui): remove jQuery from test result details and navigation`

- **Files**:
  - `assets/javascripts/test_result.js`
  - `assets/javascripts/job_next_previous.js`
  - `assets/javascripts/job_templates.js`
  - `templates/webapi/test/result.html.ep`
  - `t/ui/16-tests_job_next_previous.t`
  - `t/ui/18-tests-details.t`
- **Scope**: Test result details, next/previous job navigation, and job templates (integrating `9fdfded5f`).

### 6. `refactor(ui): migrate test overview DataTables to pure JS initialization`

- **Files**:
  - `assets/javascripts/tests.js`
- **Scope**: Native JS DataTables initialization without jQuery wrappers.

### 7. `refactor(ui): remove jQuery dependencies and layout assets`

- **Files**:
  - `package.json`
  - `package-lock.json`
  - `assets/assetpack.def`
  - `templates/webapi/layouts/bootstrap.html.ep`
  - `t/ui/01-list.t`
  - `t/33-developer_mode.t`
- **Scope**: Removal of jQuery packages from dependencies, layout cleanup, and template test updates.

## Execution Strategy

Instead of interactive rebase conflicts, perform branch reconstruction from the final clean tree:

1. Create a clean staging branch from the base commit `d0f6556ad`:
   ```bash
   git checkout -b feature/007_remove_jquery_reworked d0f6556ad
   ```
2. For each group (1 to 7):
   - Checkout the grouped files from `feature/007_remove_jquery`:
     ```bash
     git checkout feature/007_remove_jquery -- <group_files>
     ```
   - Commit using 50/80 formatted messages with `Motivation:`, `Design Choices:`, and `Benefits:`.
3. Verify:
   - `git diff feature/007_remove_jquery` is empty.
   - Run `make tidy` and `make test-checkstyle`.
   - Run affected UI tests.
4. Replace `feature/007_remove_jquery` with the newly structured branch.
