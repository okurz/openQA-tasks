# 184 Address review comments for PR #7975 (Halloween dark theme)

Reviewer: Martchus, `pullrequestreview-5570254138` (changes requested), plus
inline comments r4312782761 and r4312787284. Commit under review: `7980cce5c`
(feat: Add Halloween dark theme).

## Comments and decisions

1. Review body "Computing what could probably be a single static HTML/SVG
   document in JavaScript is not nice" — valid.
   - Move the overlay markup from `assets/javascripts/halloween.js` into
     `templates/webapi/layouts/halloween.html.ep` as static SVG (`<symbol>`
     defs + `<use>`), included from `templates/webapi/layouts/bootstrap.html.ep`
     for every theme except light (the theme of `detect` users is only known in
     the browser, so the markup must be present and hidden by CSS).
   - `halloween.scss`: `#halloween-overlay` is `display: none` by default and
     `display: block` under `[data-halloween='true']`; positioning rules move
     out of the attribute selector.
   - Delete `assets/javascripts/halloween.js` and its `assets/assetpack.def`
     entry, including the `setupHalloween()` call.
2. r4312782761 "include that as assets like we do for other images" — the
   suggestion is not implementable: AssetPack serves assets on
   `/asset/:checksum/*name`, so a relative `url()` inside the bundled CSS
   resolves to the CSS asset's own checksum path and serves the CSS, not the
   image; an absolute path breaks under a non-root `baseurl`. No CSS file in the
   repo references an image asset (images are referenced server-side, e.g.
   `favicon_url`). Decision: drop the custom cursor, which also stops overriding
   the user's cursor site-wide.
3. r4312787284 sentence case — accept the suggestion verbatim.
4. Self-found repo rule (AGENTS.md "No Inline Scripts"): the commit added 6
   lines to the inline `<script>` of `bootstrap.html.ep`, a file whitelisted in
   `xt/01-style.t`, so the linter passed. Move theme resolution to
   `assets/javascripts/theme.js` reading `data-theme-preference` and
   `data-halloween-season` from `<html>`, delete the inline script, add
   `%= asset 'theme.js'` to the head and a `! theme.js` topic to
   `assets/assetpack.def`.

## Tests

- `t/ui/04-appearance.t`: replace the `content_like` regexes that match the
  inline script with DOM assertions:
  - `html[data-theme-preference="dark_halloween"]` and
    `html[data-halloween-season]` on `/`
  - `div#halloween-overlay` exists for `dark`, `dark_halloween` and `detect`,
    `element_exists_not` for `light`
  - option label text equals `Dark mode (Halloween season)`
- `make tidy`, `make test-checkstyle`,
  `COVERAGE=1 make test-unit-and-integration TESTS=t/ui/04-appearance.t`,
  `make check-line-coverage`, `make test-gitlint` on the amended commit.
- Amend the commit message: no JS-injected decorations, no custom cursor,
  static template markup, theme script in an external file.

## Prevention

- Rewrite the sentence-case line in `~/.config/opencode/review-checklist.md` to
  cover dropdown option labels and parenthetical qualifiers (4th occurrence of
  the class).
- On a separate branch from `origin/HEAD`: remove
  `templates/webapi/layouts/bootstrap.html.ep` from the inline-script whitelist
  of `xt/01-style.t` once the file contains no `<script>`, so the repo rule is
  enforced for the file this PR extended.
