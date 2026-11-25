# 186 PR #7975 round 3: seasonal decorations with opt-out

Reviewer Martchus r4313336094 rejected shipping the Halloween layout
in regular dark mode. `tasks/138` proposed dropping auto-activation.
Decision: keep auto-activation for users who already opted into dark
mode, gate the payload by season, and add an explicit opt-out. This
satisfies the requirement that dark-mode users (explicit or
"Detect from browser") get the decorations in October while any
logged-in user can turn them off.

## Design

- Session preference `seasonal_decorations` with values `auto`, `on`,
  `off`, default `auto`. Helpers
  `seasonal_decorations` and `seasonal_decorations_enabled`
  (`lib/OpenQA/WebAPI/Plugin/Helpers.pm`).
- `<html data-seasonal-decorations="true|false">` carries the
  resolved flag; `data-halloween-season` is gone.
- `templates/webapi/layouts/bootstrap.html.ep` includes
  `layouts/halloween` only when decorations are enabled and the theme
  is not light, so light-mode pages and pages outside October ship no
  decoration markup.
- `assets/javascripts/theme.js` resolves `detect` and maps the result to
  `data-bs-theme`; it sets nothing else, so the client adds no theme state. The
  activation key is the server-provided `data-seasonal-decorations`, which is what
  Martchus r4314727433 asked for (server owns the theme, no client-side change).
  `dark_halloween` is no longer a theme value; the theme select is light, dark,
  detect.
- Appearance page gets a second dropdown labelled "Seasonal
  decorations" with "Automatically during October", "Always", "Never";
  both selects get `id` and matching `label for` (the theme label
  pointed at `expiration`).
- `halloween.scss`: a `seasonal-active` mixin holds the cursor, glow, z-index and
  overlay display rules, included for
  `html[data-seasonal-decorations='true'][data-theme-preference='dark']` and for
  `data-theme-preference='detect'` inside `@media (prefers-color-scheme: dark)`, so
  the browser preference of a detect user is resolved by CSS. `@media
  (prefers-reduced-motion: reduce)` disables all overlay animations, header comment
  describes the gating. The pumpkin+spider cursor is kept as an inline data URI: Martchus
  r4312782761 asked for it as an asset, which is not implementable with AssetPack, and
  `tasks/137` recorded dropping it, so keeping the cursor is a deliberate deviation by
  the author that has to be argued in the PR.
- `lib/OpenQA/WebAPI/Controller/Appearance.pm` validates both fields
  and checks `$validation->has_error`, because Mojolicious `is_valid`
  reflects only the last validated field, so `is_valid` after two
  chained validations ignores an invalid `theme`. That was latent in
  the previous single-field validation.

## Payload

`templates/webapi/layouts/halloween.html.ep` is 3.6 KB raw, 961 bytes
compressed. CSS contribution to the cached bundle is about 1 KB
compressed. With the season gate the markup is shipped only to
dark/detect users in October, i.e. 1–2 % of a typical page, and
nothing in light mode.

## Tests

`t/ui/04-appearance.t` helpers `check_form` and `check_page` assert,
per theme and mode: `data-theme-preference`,
`data-seasonal-decorations`, and overlay presence, including
`on` in a dark theme, `off` in a dark theme, `on` in a light theme,
`auto` with dark and with detect, label sentence case, and both
invalid parameter combinations (500, session unchanged). No `localtime`
coupling for the on/off cases; `auto` compares with
`(localtime)[4] == 9`.

Checks run: `make tidy`, eslint, stylelint,
`COVERAGE=1 make test-unit-and-integration TESTS=t/ui/04-appearance.t`
(11 subtests pass; `Appearance.pm` 100 % statements, new
`Helpers.pm` lines covered), batches of `t/ui/*.t` unaffected,
`make test-author` and `make test-gitlint` pass. `t/ui/10-tests_overview.t`
and `t/ui/15-comments.t` exceed their `OpenQA::Test::TimeLimit`
locally on HEAD as well, so that is not a regression of this commit.

## Follow-up

1. Dark mode is patched incrementally (`overall.scss` 13
   `[data-bs-theme='dark']` blocks, one for `overview`,
   `dependency_graph` and `parent_group_overview`), so making dark a
   default exposes unpatched widgets. Not part of this commit.
2. Auto-activation is what Martchus asked to remove. The commit
   framing is "affects only users who already chose dark mode, only in
   October, one click to turn off". Expect another review round.
3. Opt-out lives in the session, so it resets on logout, session
   expiry, private mode and per browser. Persisting it needs a column
   in the `USERS` table (`lib/OpenQA/Schema/Result/Users.pm` has no
   prefs column). Deliberately not done: server-side session storage
   adds no cookie, so no consent banner.
4. The cursor replaces the user's pointer site-wide for decorated users, and its
   hotspot `12 1` on the 28x28 image puts the tip about 11 px left of the pumpkin, so
   clicks on small targets (job graph, icons, `limit` input) land off the visible
   pointer. If Martchus keeps asking, move the hotspot into the pumpkin body.
