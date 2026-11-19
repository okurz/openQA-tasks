# Plan: Highlight check_screen results with deleted needles (Ticket 185899)

## Context
When a test failure occurs, developers often check the last passing job to investigate the root cause. If the needle that previously matched a `check_screen` or `assert_screen` has since been deleted from the repository, there is currently no clear indication in the step view of the passing job that the matching needle no longer exists. 

## Analysis
1. In `lib/OpenQA/WebAPI/Controller/Step.pm`, the `viewimg` action populates the step details and the matched/candidate needles.
2. It attempts to load needle details using `$self->_basic_needle_info(...)` for the primary match and `$self->_extended_needle_info(...)` for secondary candidates.
3. If the needle file has been deleted from the needle repository, these methods return `undef`.
4. Currently, the controller simply ignores the `undef` return value. As a result, the deleted needle is completely omitted from the UI (or the primary match detail isn't fully populated), providing no feedback to the user about its deletion.

## Proposed Changes

### 1. Backend: `lib/OpenQA/WebAPI/Controller/Step.pm`
Modify the `viewimg` route to handle the case where `_basic_needle_info` or `_extended_needle_info` returns `undef`:
- When retrieving the primary needle match (`my $needle = $module_detail->{needle}`):
  - If `$needleinfo` is `undef`, construct a fallback dummy `$info` hash containing:
    - `name => $needle`
    - `image => ''`
    - `areas => []`
    - `error => $module_detail->{error}`
    - `primary_match => 1`
    - `selected => 1`
    - `deleted => 1`
  - Pass this fallback hash through `_calc_matches` (which processes the original matched area from `$module_detail->{area}`) and append it using `$append_needle_info->(undef, $info)` (which defaults it to the "tags unknown" category).
- Apply a similar fallback logic when parsing the other candidate needle matches in the `$module_detail->{needles}` array.

### 2. Frontend: `templates/webapi/step/viewimg.html.ep`
Update the step view template to highlight the deleted status:
- In the needle list iteration (`% for my $needle (@{$needles_by_tag->{$tag}}) {`), add a visual indicator next to the needle name:
  ```html
  %= $needle->{name}
  % if ($needle->{deleted}) {
      <span class="badge bg-danger" title="This needle has been deleted from the repository">Deleted</span>
  % }
  ```
- Hide the "View area-only diff" and "View full diff" trigger icons if the needle is deleted, because there is no reference image available to perform a visual diff against:
  ```html
  % unless ($needle->{deleted}) {
      <i class="fa-solid fa-image trigger-diff" ...></i>
      <i class="fa-solid fa-eye trigger-diff" ...></i>
  % }
  ```

## Verification & Testing
**Every code change must have corresponding test adaptations or new tests.**
- **Test File**: `t/ui/18-tests-details.t` or a dedicated test script (`t/ui/31-deleted-needles.t`).
- **Test Logic**:
  - Setup a mocked test job step (or a test fixture) with a `check_screen`/`assert_screen` result that references a non-existent needle name in its `module_detail->{needle}`.
  - Visit the web UI route for that step (`/tests/...#step/.../X`).
  - Wait for the step preview/detail container to load via AJAX.
  - Assert that the step UI includes the "Deleted" badge element (e.g., query for `.badge.bg-danger` containing the text "Deleted").
  - Assert that the diff trigger icons (`.trigger-diff`) are NOT present for this specific needle row.
- Ensure the complete test suite (`make test-unit-and-integration`) passes and that there are no regressions. 
- Ensure `make tidy` and `make test-checkstyle` pass cleanly.
