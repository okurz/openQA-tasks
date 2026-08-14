# Execution Plan - 106_poo204963_ajax_comments_pagination

## Motivation

When browsing through the comments on the group_overview page, the whole page is loaded again, including fetching all the builds, which is costly. Loading comments via AJAX avoids full page reloads, lowers the load on the openQA host, and improves user experience.

## Acceptance Criteria

- **AC1:** The group overview page does not need to reload when going though comments
- **AC2:** Pagination works as before (we can drop the query parameter, though)
- **AC3:** Lower load on the openQA host when group overview and/or comments are retrieved

## Proposed Changes

### 1. Backend Controller (`lib/OpenQA/WebAPI/Controller/Main.pm`)

- In `_group_overview`, add `comments_only` parameter to validation:
  `$validation->optional('comments_only')->num;`
- Fetch `$comments_only` from validation parameters:
  `my $comments_only = $validation->param('comments_only') // 0;`
- Remove the `comments_only` query parameter from the request URL so that any pagination links rendered inside the returned HTML (by `comments/pagination`) do not inherit it and leak it to subsequent clicks:
  `$self->req->url->query->remove('comments_only') if $comments_only;`
- Avoid computing build results if `$comments_only` is true:
  - Initialize `$build_results = []`
  - Avoid calling `OpenQA::BuildResults::compute_build_results`
  - Initialize `$max_jobs = 0`, `$limit_exceeded = 0`, and `$children = undef`.
- In `$self->respond_to`, if `html` is requested and `$comments_only` is true, render the `main/comment_area` template directly without layout:
  `$self->render(template => 'main/comment_area', layout => undef)` instead of rendering the full template.

### 2. Frontend Templates

- Wrap `%= include 'main/comment_area'` in `templates/webapi/main/group_overview.html.ep` and `templates/webapi/main/parent_group_overview.html.ep` in a `<div id="comment-area-wrapper">` block.

### 3. Frontend JavaScript (`assets/javascripts/comments.js`)

- Add an event listener on `#comment-area-wrapper` to intercept pagination link clicks.
- Fetch the new pagination target page via AJAX using `fetch()` with `comments_only=1` in query parameters.
- Replace the HTML of `#comment-area-wrapper` with the fetched HTML.
- Update browser history via `history.pushState` with the original target URL (no `comments_only` in user-facing URL).
- Re-run `updateTimeago()`.
- Add a `popstate` event listener to handle browser back/forward buttons correctly for comment pagination.

### 4. Tests (`t/ui/15-comments.t`)

- Update the pagination test in `t/ui/15-comments.t` to wait for the page element count to change via `wait_until` rather than expecting an instantaneous page reload.
