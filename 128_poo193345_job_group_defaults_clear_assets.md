# 128_poo193345: Clear unused assets once per job group via YAML defaults

Follow-up of https://progress.opensuse.org/issues/193345.

## Goal

Instead of per test suite overrides, use job group YAML
`defaults.<arch>.settings` (`public/schema/JobTemplates-01.yaml:64-79`) to
clear posted assets for groups of HDD-booting tests, e.g.:

```yaml
defaults:
  x86_64:
    machine: 64bit
    priority: 50
    settings:
      _DROP_SETTINGS: ISO,ASSET_* # after task 127, before: '+ISO': ''
```

## Implementation

- [ ] Verify that defaults settings become job template settings and that
      `+ISO: ''` there beats a posted `ISO` (precedence in
      `lib/OpenQA/JobSettings.pm:45-80`). Add a test if not yet covered.
- [ ] Document the pattern in `docs/UsersGuide.md` (job group YAML section)
      referencing task 127.
- [ ] o3 (manual, not in this repo): using the worklist from task 129, apply
      defaults to affected job groups, starting with groups only containing
      HDD-booting tests. Verify with the next Tumbleweed build that jobs
      pass and `jobs_assets` no longer link the cleared assets.

## Tests

- [ ] `t/api/02-iso.t` or `t/api/08-jobtemplates.t`: post YAML with
      `defaults` containing `+ISO: ''`, isos post with `ISO=foo.iso`, assert job
      has empty/no `ISO` and no linked iso asset.
- [ ] Full statement coverage via `COVERAGE=1` + `make check-line-coverage`.

## Commit

`test(job-groups): Cover clearing posted assets via YAML defaults` plus
`docs: …` as separate commit.
