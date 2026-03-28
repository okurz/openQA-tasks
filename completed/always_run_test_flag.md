# Plan: Implement "always_run" test flag support

The new os-autoinst test flag `always_run` needs to be fully supported in openQA, including database storage, API exposure, and UI rendering.

## Database Schema Update

- [ ] Bump version to 104 in `lib/OpenQA/Schema.pm`.
- [ ] Add `always_run` column to `lib/OpenQA/Schema/Result/JobModules.pm`.
- [ ] Generate migration files for PostgreSQL:
  - `script/initdb --prepare_init`
  - `script/upgradedb --prepare_upgrade`

## Backend Changes

- [ ] Update `lib/OpenQA/Schema/Result/Jobs.pm`: Include `always_run` in the `insert_module` SQL query and parameter list.
- [ ] Update `lib/OpenQA/Utils.pm`: Include `always_run` in `read_test_modules` so it's passed to the frontend.
- [ ] Update `lib/OpenQA/WebAPI/Controller/Test.pm`: Add `always_run` to the flags list in the `details` method.
- [ ] Update `lib/OpenQA/WebAPI/Controller/API/V1/Job.pm`: Add `always_run` to the flags list in the jobs API.

## Frontend Changes

- [ ] Update `assets/javascripts/render.js`: Add logic to render the `always_run` icon (`fa-play`) with the title "Always run: test module is executed even if a previous test module failed with fatal".

## Verification

- [ ] Update `t/fixtures/05-job_modules.pl`: Add `always_run => 1` to at least one test module.
- [ ] Update `t/ui/18-tests-details.t`: Add a test case to verify the `always_run` flag is displayed correctly.
- [ ] Run `make tidy` and `make test-checkstyle`.
- [ ] Run tests: `make test-unit-and-integration TESTS=t/ui/18-tests-details.t`.
