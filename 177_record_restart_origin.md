# 177 Record the restart origin on cloned jobs

Theme: `174_job_impact_theme_overview.md`. Depends on: nothing.

## Goal / motivation

Different kinds of restart have different value:

- Automatic retries (`RETRY`, `auto_clone_regex`) often finish overnight,
  before reviewers start, and so save human review time.
- A manual restart without investigation costs hardware time **and** blocks
  product workflows a second time until the new jobs finish.

To report these separately (task 131) and to show restart history on the job
page, every clone must record why it was created. Today the only traces are
comments (`handle_retry`) and the reason text (`auto_clone`).

## Commit 1: feat(schema): add jobs.restart_origin column

- `lib/OpenQA/Schema/Result/Jobs.pm`: add the column `restart_origin`
  (`text`, nullable). Allowed values:
  - `user`: web UI, API or CLI by a non-system user
  - `retry`: the `RETRY` setting
  - `auto_clone`: `auto_clone_regex`
  - `system`: other internal callers, e.g. obsoleting or investigation
  - NULL: an original job, not a clone
- Bump `$VERSION` in `lib/OpenQA/Schema.pm` (to the next free number at
  implementation time; 107 if this task lands first, coordinate with 127).
  Then run `./script/upgradedb --prepare_upgrade` and commit the generated
  `dbicdh/PostgreSQL/{deploy,upgrade}` files.
- Add constants to `lib/OpenQA/Jobs/Constants.pm`: `RESTART_ORIGIN_USER`,
  `RESTART_ORIGIN_RETRY`, `RESTART_ORIGIN_AUTO_CLONE`, `RESTART_ORIGIN_SYSTEM`,
  and the list `RESTART_ORIGINS`.
- Tests: `t/14-grutasks.t`/`t/schema` deploy tests stay green;
  `t/10-jobs.t` checks that the column defaults to undef.

## Commit 2: feat: set restart_origin when duplicating jobs

- `duplicate($args)`/`_create_clones`: accept `$args->{restart_origin}` and set
  it on **every** clone in the cluster, not only on the job that triggered the
  restart, so that cluster costs can be attributed.
- Callers:
  - `lib/OpenQA/Resource/Jobs.pm` `job_restart`: `user` when a `user_id` of a
    non-system user is present, otherwise `system`.
  - The `handle_retry` path and the minion `restart_job` task
    (`lib/OpenQA/Task/Job/Restart.pm` or similar): pass `retry` through
    `enqueue_restart({restart_origin => 'retry'})`.
  - The `auto_clone_regex` branch in `done()`: pass `auto_clone`.
  - Grep for all other `auto_duplicate`/`duplicate` callers and assign each an
    explicit origin. Missing origins default to `system`.
- Tests:
  - `t/10-jobs.t` and `t/api/02-jobs.t`, data-driven per path: the API restart
    sets `user`; `RETRY=1` with a failing job sets `retry` on all cluster
    clones; a matching `auto_clone_regex` sets `auto_clone`; the default is
    `system`.
  - Cover parallel/chained clusters (use the existing cluster fixtures in
    `t/05-scheduler-dependencies.t`).

## Commit 3: feat(webui): show restart origin in job info panel

- `templates/webapi/test/infopanel.html.ep`: next to the existing
  "restarted N times" / "Clone of" info, show the origin as a small badge:
  "manual restart", "automatic retry (RETRY)" or "auto-clone".
- Tests: in `t/ui/18-tests-details.t`, check the badge text for a fixture clone
  with each origin.

## Acceptance

- Each clone created by any code path has a non-NULL `restart_origin`, enforced
  by tests that cover every caller.
- No behavior change to restarting itself.

## Status

Implemented on branch `feature/126_record_restart_origin`:

- Commit 1: `220541c3d feat(schema): add jobs.restart_origin column`
- Commit 2: `8c46c0a24 feat: set restart_origin when duplicating jobs`
- Commit 3: `2831c3ef5 feat(webui): show restart origin in job info panel`

Verification:

- `make tidy` and `make test-checkstyle` passed cleanly.
- `make test-gitlint` passed across all commits.
- Full statement coverage verified on all modified lines.
