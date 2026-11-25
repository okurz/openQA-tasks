# Task: 102_poo189312_highlight_deleted_needles

## Motivation

When a needle that originally matched a specific screen/step is subsequently deleted/removed, the web UI fails to load it as a candidate. As a result, the "Candidate needles and tags" dropdown menu in the step details view completely omits the matched needle, displaying only other low-percentage (e.g. 1%) matching needles. This causes extreme confusion for users, as the test step appears to have succeeded/matched, but no matching needle is visible. We need to highlight in the web UI that the originally matched needle has been deleted.

## Analysis

- Candidate needles are fetched and loaded in `lib/OpenQA/WebAPI/Controller/Step.pm:viewimg`.
- Inside `viewimg`, the primary matched needle is fetched via `_basic_needle_info`. If the needle JSON file is deleted, `_basic_needle_info` returns `undef`.
- If the needle is not found, the controller omits it from the `%needles_by_tag` structure, meaning it is never displayed.
- The UI template `templates/webapi/step/viewimg.html.ep` renders the candidates from `%needles_by_tag`.

## Proposed Changes

### 1. Controller Change (`lib/OpenQA/WebAPI/Controller/Step.pm`)

In `viewimg`, if the primary matched needle's `$needleinfo` is `undef` (which indicates it has been deleted):

- Look up the needle in the database by absolute path, relative path, or filename (to support all production, development, and testing directories):
  ```perl
  my $db_needle = $needles_rs->find_needle($real_needle_dir, "$needle.json")
    || $needles_rs->find_needle($needle_dir, "$needle.json")
    || $needles_rs->search({filename => "$needle.json"})->first;
  ```
- Construct a skeleton needle `$info` structure with `deleted => $db_needle ? 1 : 0`. This prevents false positives in minimal mock/development environments where needle folders are present but almost all needle files are absent.
- Calculate matches on this skeleton via `_calc_matches`.
- Pass it to `$append_needle_info` with `$module_detail->{tags}` so that it gets categorized under the tags the step was looking for.

### 2. View Template Change (`templates/webapi/step/viewimg.html.ep`)

- Check if `$needle->{deleted}` is set.
- If it is, display a visual indicator/badge next to its name: `<span class="badge bg-danger text-light ms-1">deleted</span>`.
- Do not render diff and history action icons (`fa-image`, `fa-eye`, `fa-history`) for deleted needles, since their files do not exist.
- Ensure `onclick="setNeedle($(this));"` works (it handles missing/falsy `data-image` correctly on the JS side by clearing overlays and displaying only the screenshot).

### 3. Verification & Testing Strategy

- Add automated integration tests in `t/27-errorpages.t` and a full-stack Selenium UI test in `t/ui/18-tests-details.t`.
- The test dynamically registers the deleted needle in the database and then requests the step view to assert that the deleted badge is shown and action icons are hidden.
- Run tests via `make test-unit-and-integration` and verify exit status 0 and full coverage.
- Perform proactive linting and formatting via `make tidy` and `make test-checkstyle`.

## Implementation Progress & Results

### Phase 1: Planning (Completed)

- Designed architecture to fallback to skeleton needle info when original matched needle file is deleted.
- Refined design to perform database-backed validation to prevent false positives in minimal development/mock environments.

### Phase 2: Code Implementation (Completed)

- Applied backend logic in `lib/OpenQA/WebAPI/Controller/Step.pm`.
- Applied template adjustments in `templates/webapi/step/viewimg.html.ep`.
- Updated test fixture `t/fixtures/07-needles.pl`.
- Executed `make tidy` to ensure clean formatting.

### Phase 3: Verification (Completed)

- Updated `t/27-errorpages.t` to assert that:
  - The deleted needle `inst-timezone-text` is present in the response.
  - The "deleted" visual indicator badge is shown in the HTML output.
  - The diff/history/info icons are not rendered for the deleted needle.
- Updated `t/ui/18-tests-details.t` to assert that:
  - The candidates list shows `bootmenu-dvd-12.3` candidate without badge since it's not registered.
  - The candidates list shows `inst-timezone` with `deleted` badge in the candidates list in the browser.
- Ran tests via `make test-unit-and-integration` -> **PASS**.
- Generated Devel::Cover database and verified **100% statement coverage** of the new code blocks.
- Ran `make test-checkstyle` -> **PASS**.
