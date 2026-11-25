# 208 — Font Awesome 7 visual regressions and a guard against CSS-dependency breakage

`a18f45f52` bumped `@fortawesome/fontawesome-free` from 6.7.2 to 7.3.1. It
passed CI because the only test touching Font Awesome asserts that *some* font
file is listed in the asset pipeline (`t/25-serverstartup.t`, `ttf` → `woff2`).
Three visual regressions shipped to openQA.org; they were reverted in
`a7c2bf44e`. Screenshots: `tasks/Screenshot_20261018_0944*_…_spinning_fontawesome_loading_text.png`,
`…_0945*_…_text_in_bubbles.png`, `…_0945*_…_overlapping_text.png`.

## Root causes (all reproduced locally, see "Verification")

1. **FA 7 dropped the `.sr-only` / `.fa-sr-only` helper.** FA 6 shipped it
   (`fontawesome.css:6221`); Bootstrap 5 defines only `.visually-hidden`.
   openQA uses `class="sr-only"` in 10 templates and `job_next_previous.js`, so
   with FA 7 the spans become visible: `Loading…` next to the spinner on the
   index page (screenshot 1). Measured: computed `position` of
   `#build-results-loading .sr-only` is `absolute` with FA 6, `static` with
   FA 7.
2. **`assets/stylesheets/comments.scss` hard-codes `font-family: 'Font
   Awesome 6 Free'`** for `.openqa-label::before` / `.openqa-flag::before`
   (content `\f02e` / `\f024`). FA 7 renames the family to
   `Font Awesome 7 Free`, so the family is never loaded and the PUA codepoint
   falls back to the default font — a tofu box inside the comment bubbles
   (screenshot 2). Measured: `document.fonts` lists `Font Awesome 7 Free`
   while the computed `font-family` of the pseudo-element is
   `Font Awesome 6 Free`.
3. **FA 7 changes the icon box model.** `.fa` gains
   `width: var(--fa-width, 1.25em)` and `text-align: center`, and
   `::before` becomes `content: var(--fa)/""` (trailing space separator).
   Measured on the tests overview / group overview / admin group pages:
   `.status.fa-circle` 26.69 px → 18.69 px, `.badge-all-passed` 14.41 px →
   23 px, `.tag i` 71.31 px → 23 px. Adjacent text shifts and overlaps
   (screenshot 3). Pixel diffs vs. the FA 6 baseline: tests_overview 6937 px,
   details 3115 px, group_overview 1401 px, admin_groups 2057 px.

## Fix

Keep the revert as the immediate mitigation. Adopt FA 7 only with the three
openQA-side changes below, each an atomic commit.

1. `fix(ui): use Bootstrap's .visually-hidden instead of FA's .sr-only`
   Replace `class="sr-only"` with `class="visually-hidden"` in the 10
   templates and `assets/javascripts/job_next_previous.js`. Bootstrap 5 ships
   `.visually-hidden` and it is already in the `bootstrap.css` topic via
   `bootstrap-utilities.scss`.
2. `fix(assets): resolve the Font Awesome family via FA's custom property`
   In `comments.scss` use
   `font-family: var(--fa-style-family-classic, 'Font Awesome 6 Free')`.
   FA 6 defines `--fa-style-family-classic`; FA 7 defines
   `--fa-family-classic` and keeps `--fa-style-family-classic` as a
   deprecated alias, so the fallback keeps working across versions.
   Longer term, emit `<i class="fa-solid fa-…">` from `OpenQA::Markdown`
   instead of a `::before` with a hard-coded codepoint.
3. `fix(assets): keep the FA 6 icon box model`
   In `assets/stylesheets/overall.scss`:

   ```scss
   :root { --fa-width: auto; }
   html :is(.fa, .fa-solid, .fa-regular, .fa-brands, .fas, .far, .fab, .fa-classic)::before {
     content: var(--fa);
   }
   ```

   `--fa-width: auto` restores natural glyph width; `.fa-fw` sets
   `--fa-width` itself so fixed-width icons keep working. The `html` prefix
   raises specificity above FA's own rule (the FA CSS is appended after
   `openqa.scss` in `assets/assetpack.def`, so equal specificity would lose).
   Measured effect: pixel diffs drop to tests_overview 3637 px, details 552 px,
   group_overview 754 px, admin_groups 30 px. The residual is FA 7's redesigned
   glyph shapes, which is the intended new look and should be accepted by
   updating the baselines.

## Verification

Reproduction recipe (local, no production instance needed) — capture and compare
the pages with the pixel test, and read the computed-style notes from
`t/ui/31-visual-contract.t`:

```
npm install @fortawesome/fontawesome-free@<version>
export TEST_PG="DBI:Pg:dbname=openqa_test;host=/dev/shm/tpg" \
  OPENQA_BASEDIR=$PWD/t/data OPENQA_CONFIG=$PWD/t/data OPENQA_DATABASE=test \
  OPENQA_WEBUI_MODE=test SCHEMA_NAME=<unique> \
  PERL5OPT="-I$PWD/lib -I$PWD/t/lib -I$PWD/external/os-autoinst-common/lib"
OPENQA_VISUAL_BASELINE=1 perl -Ilib -It/lib t/ui/32-visual-baseline.t   # writes t/data/screenshots/*.png
perl -Ilib -It/lib t/ui/32-visual-baseline.t                            # compares
perl -Ilib -It/lib t/ui/31-visual-contract.t                           # computed styles
perl -Ilib -It/lib t/44-frontend-contract.t                            # static contract
```

`make tidy` and `make test-checkstyle` must pass (stylelint accepts the rules
above). Verified on the committed branch:

- `make tidy`, `make test-checkstyle-standalone` (stylelint, eslint, shellcheck,
  shfmt, yamllint, markdown, gitlint) and `make test-gitlint`: pass.
- `xt/01-style.t`, `xt/02-perlcritic.t`, `xt/02-pod.t`: pass
  (`stabilise_page` needed a `($driver)` signature).
- `make test-unit-and-integration` with
  `OPENQA_TEST_TIMEOUT_SCALE_FACTOR=6` (the machine is loaded, so the 10 s
  default limit is too tight): 161 files, 4547 tests, `Result: PASS`, including
  `t/25-serverstartup.t`, `t/44-frontend-contract.t`, `t/ui/15-comments.t`,
  `t/ui/31-visual-contract.t` and `t/ui/32-visual-baseline.t`.
- No file under `lib/` changed, so `make check-line-coverage` is not applicable.

## Commits on `feature/fix_fontawesome7` (on top of the FA 7 revert)

1. `fix(ui): use Bootstrap's .visually-hidden instead of FA's .sr-only`
2. `fix(assets): resolve the Font Awesome family via FA's custom property`
3. `fix(assets): keep the natural icon width and icon content`
4. `fix(assets): use the fa-solid fa-folder-open icon class`
5. `test: guard the contract between the web UI and its CSS dependencies`
6. `test: check every asset referenced by the node_modules CSS is listed`
7. `test: assert rendered icons and hidden content in a browser`
8. `chore(deps): bump @fortawesome/fontawesome-free from 6.7.2 to 7.3.1`
9. `test: compare web UI pixels against committed baselines`
10. `chore(ci): group major bumps of the frontend CSS dependencies`

The bump follows the openQA-side fixes and the baselines follow the bump, so
every commit keeps CI green: the references are FA 7 output, and with FA 6 the
pixel test compares 6.7.2 pixels against them.

## Testing extension

The regressions were invisible to CI because no test asserts *rendering*.
Add three layers, cheapest first.

### 1. Static contract tests (no browser, run in the normal suite)

New `t/44-frontend-contract.t`:

- Parse `node_modules/@fortawesome/fontawesome-free/css/fontawesome.min.css`
  for the `@font-face` family names and forbid a literal `Font Awesome` family
  in `assets/stylesheets/**`: the family must be referenced through
  `var(--fa-style-family-classic)`, which fails on the hard-coded
  `Font Awesome 6 Free` string.
- Collect the `.fa-*` icon classes the package defines and assert every icon
  class used by `templates/**` and `assets/javascripts/**` is among them; this
  fails on `fa-folderpen`.
- Assert `templates/**` and `assets/javascripts/**` contain no
  `sr-only` class, since Bootstrap 5 defines only `visually-hidden`.
- Extend the existing `t/25-serverstartup.t` subtest: instead of
  `qw(scss css js png svg woff2)`, collect every `url(…)` target from the FA
  CSS files listed in `assets/assetpack.def` and assert each appears in
  `OpenQA::Assets::list` output. This catches the ttf→woff2 change and any
  future asset-pipeline drop, which the current extension-list assertion
  cannot.

### 2. Browser contract test (Selenium, reuses `OpenQA::SeleniumTest`)

New `t/ui/31-visual-contract.t` over the pages listed in the verification
recipe, asserting computed styles rather than pixels:

- every `i[class*=fa-]` has a non-empty `--fa` custom property (Chrome
  serialises PUA `::before` content as `""`, so `--fa` is the property to
  read) and its `::before` `font-family` is present in `document.fonts` with
  status `loaded`;
- every element that hides content for screen readers (`.sr-only,
  .visually-hidden`) computes `width:1px`, `height:1px`, `overflow:hidden`,
  `position:absolute`, `white-space:nowrap` and `clip: rect(0 …)` — Bootstrap
  5.3.8 uses `clip`, not `clip-path: inset(50%)`;
- every `.fa-*` icon is as high as its line box, and the text of a label sits
  on the same line as its icon, so an icon must not push text beside it.

These assertions are deterministic, cheap, and fail with root causes 1 and 2.
Root cause 3 (box-model shift) moves glyphs by sub-pixel amounts, so the
overlap check does not detect it; the pixel baselines do.

### 3. Pixel baselines

New `t/ui/32-visual-baseline.t`: capture the same pages, compare against
reference PNGs in `t/data/screenshots/` with an anti-aliasing-tolerant
per-pixel comparison, and fail when more than 0.1 % of pixels differ.
References are generated by the test itself with
`OPENQA_VISUAL_BASELINE=1`; the CI job runs the comparison. CSS animations are
frozen before capturing so that spinner frames are deterministic.

The comparison is implemented in `t/lib/OpenQA/Test/Screenshot.pm` (8-bit PNG
scanline decoding via `Compress::Zlib` plus `compare_png`). PerlMagick was
dropped as a dependency: it is not in `cpanfile` and not in the CI container.
The decoder was validated against `Image::Magick` pixel data.

Measured sensitivity (800x457 viewport, tolerance 0.1 %):

- run-to-run noise with the fixes applied: 0.000–0.028 % per page,
  so the tolerance has headroom;
- FA 6 against the FA 7 baselines: 0.005–0.031 %, **passes** — with the
  box-model and font-family fixes in place the residual glyph-shape
  differences are below the tolerance, so the pixel test cannot be the
  precise guard for this bump;
- unpatched FA 7 against the FA 7 baselines: the `sr-only` span becomes
  visible, the comment bubbles show tofu and the icon boxes shift, which
  exceeds the tolerance and fails the CI job.

The precise guards for root causes 1 and 2 are `t/44-frontend-contract.t` and
`t/ui/31-visual-contract.t`; the pixel baselines are the coarse net that
catches gross layout change in any CSS dependency bump.

The pixel test is itself the guard for dependency bumps: a bump that changes
layout fails the comparison, and a bump that does not change pixels passes
without touching the references. A separate
`tools/ci/check-frontend-baselines.sh` heuristic (fail when `package.json`
changes while `t/data/screenshots/` does not) would fail legitimate bumps that
render identically, so it is not implemented.

Add `@fortawesome/fontawesome-free` and `bootstrap` to
`.github/dependabot.yml` as a `frontend-css-major` group, so a major bump lands
as one PR that has to regenerate the baselines.

## Tests to touch

- new `t/44-frontend-contract.t` (static contract)
- `t/25-serverstartup.t` (asset listing subtest extended to every `url()`
  target of the FA CSS files, `woff2` added to the expected extensions)
- new `t/ui/31-visual-contract.t` and `t/ui/32-visual-baseline.t`, new
  `t/lib/OpenQA/Test/Screenshot.pm`
- `assets/javascripts/render.js` (`fa-regular fa-folderpen` →
  `fa-solid fa-folder-open`, caught by the icon-class contract)
- `.github/dependabot.yml`
- `.circleci/config.yml` needs no change: the `ui` job runs `make test-ui`,
  which globs `t/ui/*.t` via `tools/ci/run_unit_tests.sh`.

## Implementation status

Committed in the order listed in the previous section on
`feature/fix_fontawesome7`:

1. `sr-only` → `visually-hidden` in 10 templates and
   `assets/javascripts/job_next_previous.js`.
2. `comments.scss` uses `font-family: var(--fa-style-family-classic)`.
3. `overall.scss` sets `:root { --fa-width: auto }` and overrides
   `::before { content: var(--fa) }` with an `html` prefix (the FA CSS is
   appended after `openqa.scss` in `assets/assetpack.def`).
4. `fa-folderpen` → `fa-solid fa-folder-open` in `render.js`.
5. `t/44-frontend-contract.t` — 4 tests, passes with the fixes, fails on
   unpatched FA 7 for all three root causes.
6. `t/25-serverstartup.t` — asset listing extended to every `url()` target of
   the node_modules CSS; verified to fail when a webfont reference is missing.
7. `t/ui/31-visual-contract.t` — 7 subtests, passes with the fixes; on
   unpatched FA 7 it fails on the `sr-only` helper and on the comment label and
   flag bubbles.
8. FA 7.3.1 in `package.json` / `package-lock.json`.
9. `t/ui/32-visual-baseline.t` + `t/lib/OpenQA/Test/Screenshot.pm` + 6 baseline
   PNGs in `t/data/screenshots/`.
10. `frontend-css-major` group in `.github/dependabot.yml`.

Scratch files left in the working tree, safe to delete: `dom5_fa6.html`,
`dom5_fa7fix.html`, `probe5_fa6.html`, `probe5_fa7fix.html` and the perltidy
backups `t/25-serverstartup.t.bak`, `t/44-frontend-contract.t.bak`,
`t/lib/OpenQA/Test/Screenshot.pm.bak`, `t/ui/31-visual-contract.t.bak`,
`t/ui/32-visual-baseline.t.bak`. `public/dist/` is pre-existing asset-pack build
output. Nothing was deleted.
