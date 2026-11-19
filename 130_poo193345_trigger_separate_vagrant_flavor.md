# 130_poo193345: Post vagrant boxes in a separate flavor in openqa-trigger-from-obs

Follow-up of https://progress.opensuse.org/issues/193345.
Repository: openqa-trigger-from-obs (`../openqa-trigger-from-obs`).

## Problem

`xml/obs/openSUSE:Factory.xml:12-15` attaches the vagrant libvirt and
virtualbox boxes as `<assets flavor="DVD">` to the `Tumbleweed-DVD` isos post,
so every Tumbleweed DVD job links both boxes although only vagrant tests use
them.

## Implementation

- [ ] Check which o3 test suites actually use the boxes (audit from task 129,
      `ASSET_*` referencing `*.vagrant.*.box`).
- [ ] Move the boxes to their own flavor, e.g. `Tumbleweed-Vagrant`, posted
      without ISO, analogous to the `wsl` batch (`<asset filemask=…>` under its own
      flavor, `openSUSE:Factory.xml:64-67`). Check `script/scriptgen.py:488-534`
      (`assets`/`asset` handling) whether the `<assets flavor=…>` mechanism already
      supports this or needs extension; if extended, add tests there.
- [ ] Check other XMLs with vagrant boxes (e.g. Leap / Slowroll) and apply
      the same where applicable.
- [ ] Coordinated rollout on o3 (manual):
  1. Create medium/product for the new flavor and move vagrant job templates
     to it.
  2. Deploy the trigger change.
  3. Remove remaining `+ASSET_*=` overrides from test suites that are now
     obsolete (e.g. `ping_*` from #193345) or replace with
     `_DROP_SETTINGS` (task 127) where still needed.
  4. Verify with the next build: vagrant tests still pass, DVD jobs link no
     vagrant boxes; compare with task 129 audit output before/after.

## Tests

- [ ] Regenerate expected scripts (`make test_update_before_files`) and
      review the diffs of `t/obs/openSUSE:Factory*/print_openqa.*`.
- [ ] `make test` and `make test_python_style` pass.

## Commit

`feat: Post Tumbleweed vagrant boxes in a separate flavor`
