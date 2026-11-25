# 179 Expose job impact in the job API and on the job details page

Theme: `174_job_impact_theme_overview.md`. Depends on: 127.

## Commit 1: feat(api): include impact in job details

- `GET /api/v1/jobs/:id` (`to_hash` in `lib/OpenQA/Schema/Result/Jobs.pm`):
  add `impact => {seconds, energy_kwh, carbon_g, cost => {energy, hardware,
human, total}, currency, model_version, estimated => \1}`, only when a
  record exists.
- In `GET /api/v1/jobs` (list), add it only when `?impact=1` is passed and
  prefetch with `prefetch => 'impact'`. This avoids larger responses and extra
  joins for existing clients.
- Tests: `t/api/02-jobs.t`:
  - The field is present or absent depending on whether a record exists.
  - In the list, the field appears only with `impact=1`.
  - Check the query count by counting DBIC queries with the existing
    test helper, if one is available.

## Commit 2: feat(webui): show estimated impact in job info panel

- `templates/webapi/test/infopanel.html.ep`:
  - Add one line after the "ran for …" line (around :64):
    `Estimated impact: ≈ 0.042 € · ≈ 12 g CO₂e`
  - Add a help popover that uses the existing popover helper pattern. It
    shows:
    - power, energy, cost breakdown and resolved factor sources
    - model version
    - a link to `methodology_url` or `docs/JobImpact.md`
- Add a template helper `format_job_impact` in
  `lib/OpenQA/WebAPI/Plugin/Helpers.pm` that delegates to
  `OpenQA::JobImpact::format_estimate`.
- Do not render anything when there is no record or the feature is disabled.
- Tests:
  - `t/ui/18-tests-details.t`: the line and popover content appear for a
    fixture with a record and do not appear without one.
  - Helper unit test in `t/job_impact.t`.

## Acceptance

- No extra query on the job page beyond a single `impact` lookup.
- Old API clients are unaffected (additive field).

## Status

Implemented on branch `feature/128_job_impact_api_and_details_page`:

- Commit 1: `2dd59a026 feat(api): include impact in job details`
- Commit 2: `fcb198224 feat(webui): show estimated impact in job info panel`

Verification:

- `make tidy` and `make test-checkstyle` passed cleanly.
- `make test-gitlint` passed across all commits.
- Full statement coverage verified on all modified lines.
