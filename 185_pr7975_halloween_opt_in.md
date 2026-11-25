# 185 PR #7975 round 2: Halloween theme must be opt-in

Comment: Martchus r4313336094 on
`templates/webapi/layouts/bootstrap.html.ep:80` (`% if (current_theme ne 'light')
{`): "So we also include the Halloween layout in the regular dark mode? That
seems wrong."

## Evaluation

Valid. The overlay is included for `dark` and `detect` so that the October
auto-activation from the commit Motivation can fire client-side, which means
users who deliberately chose plain dark mode get Halloween decorations without
asking. Explicit dark mode is a deliberate accessibility/contrast choice; a
cosmetic seasonal change must be opt-in. Opt-in is also simpler: no server-side
calendar helper, no season data attribute, no client-side theme upgrade, no SVG
markup shipped to every dark/detect user.

Consequence: the October auto-activation is dropped; the PR becomes an opt-in
theme selectable on the appearance page.

## Changes

- `templates/webapi/layouts/bootstrap.html.ep`: keep only
  `data-theme-preference` on `<html>`; include the overlay only when
  `current_theme eq 'dark_halloween'`.
- `assets/javascripts/theme.js`: drop the season upgrade and `data-halloween`;
  map `dark_halloween` to Bootstrap's `dark`.
- `assets/stylesheets/halloween.scss`: key all rules on
  `[data-theme-preference='dark_halloween']`; `#halloween-overlay` needs no
  display toggling because the markup is only present for that theme; update
  the header comment.
- `lib/OpenQA/WebAPI/Plugin/Helpers.pm`: remove `is_halloween_season`.
- `t/ui/04-appearance.t`: drop the `localtime` coupling; assert
  `div#halloween-overlay` exists for `dark_halloween` and is absent for `dark`,
  `detect` and `light`; assert no `data-halloween-season` attribute.
- Amend the commit message: Motivation states opt-in, Design Choices describe
  static template markup for the selected theme only.
- Checks: `make tidy`, `make test-checkstyle`,
  `COVERAGE=1 make test-unit-and-integration TESTS=t/ui/04-appearance.t` +
  coverage of `Helpers.pm`, `git commit --fixup cc0cfe266` + autosquash,
  `make test-gitlint`. Mutation checks: overlay for `dark` must fail, presence
  of `data-halloween-season` must fail.

## Prevention

Class: design, "user-facing behaviour enabled site-wide by default instead of
via explicit opt-in". Prior occurrences: os-autoinst-scripts#710 r4106522333
(default-enable new features, support explicit disabling) and
salt-states-openqa#MR1804 r1103032 (global blocklists in common templates,
scope exemptions). 3rd occurrence, so promote: rewrite the `Scope` section of
`~/.config/opencode/review-checklist.md` with one question covering default-on
vs opt-in. Pre-push missed it because the commit Motivation stated
auto-activation as the goal, so the implementation was reviewed against the
design, not the design itself.

No repo-linter change: opt-in vs default-enable is not machine-checkable.
