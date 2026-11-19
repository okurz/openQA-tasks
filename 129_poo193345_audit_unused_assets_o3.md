# 129_poo193345: Read-only audit script for likely unused job assets

Follow-up of https://progress.opensuse.org/issues/193345.
Repository: os-autoinst-scripts (`../os-autoinst-scripts`), follow its
`AGENTS.md`, Python with `uv`, pytest in `tests/`.

## Goal

Produce the worklist for tasks 128 and 130 and measure progress: which
test suites / job groups on o3 link assets they most likely do not use, and
how much space and transfer that costs.

## Implementation

- [ ] New script `openqa-find-unused-job-assets` (Python, read-only,
      `--host` defaulting to `https://openqa.opensuse.org`, `--group`, `--build`
      optional filters, `--format text|json`).
- [ ] Data: latest jobs per scenario (`/api/v1/jobs/overview` or
      `/api/v1/jobs?latest=1&groupid=…`), job settings, asset sizes from
      `/api/v1/assets`.
- [ ] Heuristics, each reported with a reason:
  - `ISO` set while `BOOT_HDD_IMAGE=1` and `HDD_1` set → ISO likely unused
  - `ASSET_*` vagrant boxes (`*.vagrant.*.box`) set while test name/settings
    do not relate to vagrant
  - `ASSET_256` (ISO checksum) set while ISO likely unused
- [ ] Output aggregated by job group and test suite: job count, candidate
      settings, total bytes (job count × asset size), sorted descending.
- [ ] Clearly label results as candidates: some HDD-booting tests still use
      the ISO, e.g. as add-on/repo media; verification is done via the next
      build after changing settings.

## Tests

- [ ] pytest with mocked API responses covering each heuristic, aggregation,
      sorting and output formats; follow repo coverage requirements.
- [ ] `make test` / checkstyle targets of os-autoinst-scripts pass.

## Commit

`feat: Add openqa-find-unused-job-assets to report likely unused assets`
