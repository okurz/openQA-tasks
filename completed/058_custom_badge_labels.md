# Execution Plan: Custom Badge Labels

## Objective

Extend the current SVG badge rendering in openQA to support custom labels on the left side (the prefix), replacing the hardcoded "openQA" text and logo when specified. This allows users to request custom badges like `?label=Core%20Maintenance%20Updates`.

## Background

Currently, `lib/OpenQA/WebAPI/Controller/Test.pm` defines `sub _render_badge` which hardcodes `badge_prefix_width` to 85. The template `templates/webapi/test/badge.svg.ep` hardcodes the "openQA" text at `x="29"` and the background color split at `x="85"`. It also includes an SVG path for the openQA logo.

## Files to Modify

1. `lib/OpenQA/WebAPI/Controller/Test.pm`
2. `templates/webapi/test/badge.svg.ep`
3. `t/10-overview_badge.t` (and/or other relevant badge test files)

## Step-by-Step Execution

### 1. Update `lib/OpenQA/WebAPI/Controller/Test.pm`

Modify `sub _render_badge` to support a dynamically calculated prefix label:

- Fetch the custom label from the query parameters using `$self->param('label') // 'openQA'`.
- If the label is `'openQA'`, retain the default behavior (`badge_prefix_width = 85`, `prefix_x = 29`).
- If the label is customized:
  - Calculate `badge_prefix_width` dynamically by considering the string length, left/right padding (e.g., 6px), and the `%BADGE_CHARLENS` adjustments.
  - Set `prefix_x = 6` (or appropriate padding) for the text start coordinate since the logo will be omitted.
- Pass the dynamically calculated `badge_prefix_text`, `badge_prefix_width`, and `prefix_x` to the `stash` so the template can use them.
- Ensure the total `badge_width` calculation utilizes the dynamically adjusted `badge_prefix_width`.

### 2. Update `templates/webapi/test/badge.svg.ep`

Modify the SVG template to be dynamic:

- Wrap the `<path>` block (the openQA logo) with an `% if ($badge_prefix_text eq 'openQA') { ... }` so it does not render when a custom label is used.
- Replace `<rect x="85" ... />` with `<rect x="<%= $badge_prefix_width %>" ... />`.
- Replace the hardcoded `<text x="29" ...>openQA</text>` tags with `<text x="<%= $prefix_x %>" ...><%= $badge_prefix_text %></text>`.
- Replace the suffix text tags' absolute coordinates `<text x="90" ...>` with `<text x="<%= $badge_prefix_width + 5 %>" ...>`.

### 3. Add Tests

Add tests in `t/10-overview_badge.t` to verify the new feature works as expected:

- Request `/tests/overview/badge?label=Core%20Maintenance%20Updates` and ensure the response is `200 OK` and contains the string `Core Maintenance Updates`.
- Request an individual job badge with the `label` parameter and assert its presence in the generated SVG.
- Validate that the old behavior (`?show_build=1` without `label`) remains fully functional and still renders `openQA`.

### 4. Verify & Commit

- Run `make test-unit-and-integration TESTS=t/10-overview_badge.t` to ensure the new tests pass.
- Run `make tidy` and `make test-checkstyle` to fulfill code style constraints.
- After passing verification, the task is considered successfully planned and ready for implementation.
