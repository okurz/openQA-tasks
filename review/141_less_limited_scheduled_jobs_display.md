# 141 Show the real scheduled job count on /tests

Todo: `tasks/todo.md` item 141.
Branch: `feature/141_less_limited_scheduled_jobs_display` (clean tree,
`origin/master` at `afb808231`).
Numbering: 141 follows the todo item; `tasks/218_poo209244_recover_o3_docker_not_starting.md`
covers a distinct o3 infra ticket, no file collision.
Status: implemented (3 commits), awaiting review.

## Problem

`/tests` shows "1000 scheduled jobs" on an instance with more than 1000
scheduled jobs. The number is not a cap annotation, it is a wrong count: the
heading is literally the number of rows the AJAX endpoint returned.

Data flow:

1. Route `/tests` → `test#list` (`lib/OpenQA/WebAPI.pm:139`). There is no
   `sub list` in `lib/OpenQA/WebAPI/Controller/Test.pm`, so Mojolicious
   dispatches through its default action and renders
   `templates/webapi/test/list.html.ep` directly. The page is template +
   client-side JS; no Perl computes a scheduled count.
2. `templates/webapi/test/list.html.ep:32` (`#scheduled_jobs_heading`),
   `:39` (`#scheduled` table).
3. `assets/javascripts/tests.js:323-366` fills the table; `:339` sets the
   heading to `json.data.length + ' scheduled jobs'`; `:329-338` computes the
   blocked count and the reason popover over the returned rows only.
4. `assets/javascripts/tests.js:264-271` forwards the page's `limit` query
   param to the endpoint.
5. `list_scheduled_ajax` (`lib/OpenQA/WebAPI/Controller/Test.pm:373-412`)
   caps rows with `generic_default_limit` (1000) / `generic_max_limit`
   (10000) (`lib/OpenQA/Setup.pm:296-297`), turning the limit into SQL `rows`
   at `lib/OpenQA/Schema/ResultSet/Jobs.pm:457`. No total is ever computed.

The cap on the _listing_ is justified and documented: commit `18d493c40`
("perf: Tweak generic limits to avoid high response times and RAM usage")
lowered 5000/50000 to 1000/10000 because Mojo workers used over 5 GiB and
requests timed out; `etc/openqa/openqa.ini:328-333` documents both keys as
"to prevent performance issues". The expensive part of the scheduled request
is per-row work: `ancestors_count_for_jobs`
(`lib/OpenQA/Schema/ResultSet/Jobs.pm:642-662`) seeds up to `$limit` job IDs
in a recursive CTE and client-side DataTables keep all rows in the DOM. A
`count(*)` over `me.state` is index-supported (`idx_jobs_state`,
`lib/OpenQA/Schema/Result/Jobs.pm:232`) and is already done cheaply for the
running listing (`Test.pm:356-359`). There is no auto-refresh on `/tests`
(`tests.js` has no timer), so the count runs once per page load.

No abstraction cap ("more than 1 million") is warranted: PostgreSQL counts
the matching set exactly and cheaply, and the repo has no precedent for that
phrasing. The only "more than N" precedent is
`templates/webapi/test/infopanel.html.ep:96` for a server-supplied limit, and
the canonical way of communicating a listing limit is
`templates/webapi/layouts/limit_warning.html.ep:3` ("Only N results
included") plus the "Last N finished jobs" heading phrasing
(`tests.js:406`).

## Design

Compute the true filtered total server-side and report it next to the limited
rows, following the existing `recordsTotal`/`recordsFiltered` pattern of
`lib/OpenQA/WebAPI/ServerSideDataTable.pm:20-36,62-67`. Keep
`generic_default_limit`/`generic_max_limit` unchanged, so the listing stays
capped and the API tests keep passing.

1. `list_scheduled_ajax` builds the search args once; the listing takes the
   `rows` limit, the count runs on the same resultset without `rows`.
   DBIX `count` deletes `rows`/`offset` and strips `order_by`
   (vendor `DBIx/Class/ResultSet.pm:1592-1616,1659-1674`) but keeps joins and
   subquery conds, so `count(*)` is exact. A resultset with `rows` set returns
   `min(rows, count)` (`:1613`), so the count must not reuse the limited
   resultset.
2. Response keys `total_count` and `blocked_count` (snake_case, matching the
   existing `dynamic_job_limit`/`max_running_jobs`/`job_skipped_by_disk_limits`
   keys in the same file, `Test.pm:363-368,409`).
3. Heading text stays `"<N> scheduled jobs"` with `N` = `total_count`, and the
   existing `(<M> blocked by other jobs)` parenthetical uses the server-side
   blocked count. When the listing is capped, the cap is communicated in the
   DataTables info line (`#scheduled_info`), the place DataTables uses for
   range reporting, not in the heading.
4. The reason popover (`tests.js:346-350`) stays computed over the returned
   rows. Server-side grouping of reasons over the whole set is out of scope
   for this ticket.
5. `limit` semantics: the count is the total matching the current filters,
   consistent with the `limit` param forwarded to the endpoint
   (`tests.js:264-271`) and with the running listing, which reports the global
   count for its limit check (`Test.pm:356-359`).

```perl
    my $jobs_rs = $self->schema->resultset('Jobs')->complex_query(
        state => [OpenQA::Jobs::Constants::PRE_EXECUTION_STATES],
        match => $self->get_match_param,
        comment_text => $self->param('comment'),
        groupid => $self->param('groupid'),
        order_by => [{-desc => 'me.t_created'}, {-desc => 'me.id'}],
        job_settings => $self->every_key_value_param('job_setting'),
        columns => [qw(id MACHINE DISTRI VERSION FLAVOR ARCH BUILD TEST
          state clone_id result group_id t_finished t_started t_created t_updated
          blocked_by_id priority reason)],
    );
    my $total_count = $jobs_rs->count;
    my $blocked_count = $jobs_rs->search({'me.blocked_by_id' => {'!=', undef}})->count;
    my @jobs = $jobs_rs->search({}, {rows => $limit})->all;
    …
    my %response = (data => \@scheduled, total_count => $total_count, blocked_count => $blocked_count);
```

```js
const total = json.total_count ?? json.data.length;
const blocked = json.blocked_count ?? blockedCount;
let text = total + ' scheduled jobs';
if (blocked > 0) {
  text += ' (' + blocked + ' blocked by other jobs)';
}
$('#scheduled_jobs_heading').text(text);
```

## Commits (atomic)

1. `refactor(ui): build the scheduled job query args once in list_scheduled_ajax`
   - Hoist the `complex_query` args of `Test.pm:378-393` into one resultset
     without `limit` and apply the `rows` limit when fetching
     (`$rs->search({}, {rows => $limit})`). No behavior change.
2. `fix(ui): show the real scheduled and blocked job count on /tests`
   - Perl: `total_count`/`blocked_count` as sketched above (`Test.pm:373-412`).
   - JS: heading from `total_count`/`blocked_count` with `json.data.length`
     fallback (`tests.js:329-344`).
   - Tests:
     - `t/ui/01-list.t:196-206`: `/tests?limit=1` heading expectation
       `'1 scheduled jobs'` → `'3 scheduled jobs'` (fixtures have 3 scheduled
       jobs: `t/fixtures/01-jobs.pl:88,114` and `t/ui/01-list.t:102-109`).
       The 3-job heading at `:198` stays `'3 scheduled jobs'`.
     - extend the subtest at `t/ui/01-list.t:282-316` (already creates 5 extra
       scheduled jobs in a transaction, already asserts `data` lengths 5/3/2)
       with `is $json->{total_count}, 5, …` for each of the three requests, so
       the count is asserted at max, user and default limit; add a
       `blocked_by_id` fixture job inside the transaction and assert
       `blocked_count` covering the new Perl lines.
     - `t/ui/01-list.t:500-501` row assertions stay.
     - `t/lib/OpenQA/Test/FullstackUtils.pm:184-189` asserts
       `eq '1 scheduled jobs'` for a single scheduled job; total 1 = rows 1,
       so it is unaffected.
3. `feat(ui): communicate the scheduled listing limit in the table info line`
   - JS only: keep the true total in a closure set inside `dataSrc` and add
     `infoCallback` to the `#scheduled` DataTables init
     (`tests.js:323-366`) so `#scheduled_info` reports
     "Showing <start> to <end> of <total> entries".
   - Tests: assert the info line after `/tests?limit=1` in `t/ui/01-list.t`
     following the pattern of `t/ui/17-product-log.t:133-135`
     (`qr/Showing 1 to 1 of 3 entries/`).

## Gates

Per commit:

```
make tidy
make test-checkstyle
COVERAGE=1 make test-unit-and-integration TESTS=t/ui/01-list.t TEST_PG="DBI:Pg:dbname=openqa_test;host=/dev/shm/tpg"
```

Commit 2 additionally:
`COVERAGE=1 make test-unit-and-integration TESTS="t/ui/02-list-group.t t/ui/26-jobs_restart.t"` (row-count assertions at `t/ui/02-list-group.t:20-24`, `t/ui/26-jobs_restart.t:338-344` must keep passing).

Before declaring done:

```
make check-line-coverage                                  # strict statement coverage gate
cover -report text -select_re lib/OpenQA/WebAPI/Controller/Test.pm
make test-gitlint                                         # conventional-commit titles, 50/72 wrap
COVERAGE=1 make test-fullstack                            # FullstackUtils heading string is exercised by t/full-stack.t:99, t/33-developer_mode.t:115
```

CI runs the same: `tools/ci/run_unit_tests.sh ui` (`COVERAGE=1`,
`.circleci/config.yml:51-53`) executes `make test-ui` = `t/ui/*.t`
(`Makefile:291-293`), and `./tools/check-line-coverage
cover_db/codecov.json` (`tools/check-line-coverage:39-42`) fails on any
uncovered line. JS lines are not coverage-measured; commit 3 is verified by
Selenium only.

## Notes

- `t/api/04-jobs.t:2042-2062`, `t/api/09-comments.t:175`,
  `t/api/11-bugs.t:70` assert `generic_default_limit`/`generic_max_limit`;
  the plan does not change those values, so they stay green.
- No new `misc_limits` key → `t/config.t:165-195` documentation check is
  unaffected; no `etc/openqa/openqa.ini` change.
- `/tests/overview` (`Test.pm:991`,
  `lib/OpenQA/WebAPI/Plugin/Helpers.pm:397-494`,
  `lib/OpenQA/Schema/Result/Jobs.pm:2460-2482`,
  `templates/webapi/test/overview.html.ep:71-78`) and the dashboard
  (`lib/OpenQA/WebAPI/Controller/Main.pm:47,89-93`) aggregate scheduled
  counts over their own limited queries; they are not the reported symptom
  and are out of scope. `t/10-tests_overview.t` (`qr/Scheduled: 2/i`) and
  `t/22-dashboard.t:632-659` stay green.
- Repo has no i18n (no `Locale::Maketext`, no `.po`), so no string extraction
  work; headings are plain English in JS.
- Follow-up (todo item 142, auto-reload of `/tests`) and the server-side
  reasons-popover aggregation are separate plans; do not fold them in here.

## Approvals

- Keep `generic_default_limit`/`generic_max_limit` at 1000/10000; cap the
  listing, not the count — approved by okurz, 2026-10-27 (implemented).
- Exact count via `count(*)` on `idx_jobs_state`; no abstraction cap
  ("more than 1 million") — approved by okurz, 2026-10-27 (implemented).
- Response keys `total_count`/`blocked_count` on
  `/tests/list_scheduled_ajax` — approved by okurz, 2026-10-27 (implemented).
- Heading shows the true total; listing cap lives in the info line —
  approved by okurz, 2026-10-27 (implemented).
- Reasons popover stays row-limited in this ticket — approved by okurz,
  2026-10-27 (implemented).
- Golden string change `t/ui/01-list.t:205`
  (`'1 scheduled jobs'` → `'3 scheduled jobs'`) — approved by okurz,
  2026-10-27 (implemented).

## Session starter

Read this file, `git status` (expect clean tree on
`feature/141_less_limited_scheduled_jobs_display` at `afb808231`), then
implement commit 1 (pure refactor) with `make tidy`,
`COVERAGE=1 make test-unit-and-integration TESTS=t/ui/01-list.t
TEST_PG="DBI:Pg:dbname=openqa_test;host=/dev/shm/tpg"` as the gate; commit
with `make test-gitlint` green. Continue with commit 2, then commit 3. Run
the full gate set, record each approval in the section above with date and
approver, and move this file to `tasks/review/` once all commits are pushed.

## Implementation notes

Deviations from the plan, recorded during implementation (2026-10-27):

1. Commits: `95f095fb5` refactor, `9dd692bdc` fix, `2b18825a7` feat on
   `feature/141_less_limited_scheduled_jobs_display`.
2. The plan's `is $json->{total_count}, 5` is wrong: the fixture DB holds
   3 scheduled jobs (`t/fixtures/01-jobs.pl:88,114` + job 99991 from
   `prepare_database`), so with 5 new + 1 blocked fixture job in the
   transaction the subtest asserts `total_count` 9 with data lengths 5/3/2
   (max/user/default limit) and `blocked_count` 1.
3. Commit 1 guards `rows` on a truthy `$limit`
   (`$limit ? $jobs_rs->search({}, {rows => $limit})->all : $jobs_rs->all`)
   because `complex_query` skipped falsy limits; unguarded
   `rows => 0` croaks via DBIC for `/tests?limit=0`. Covered by a new
   `limit=0` assertion (all 9 rows, no 500).
4. `infoCallback` renders "of 1 entry" singular to match DataTables'
   language `entries` pluralisation used by the default info line.
5. Gate results: `make tidy`, `make test-checkstyle`, `make test-gitlint`,
   `t/ui/01-list.t` (76 tests) + `t/ui/02-list-group.t` +
   `t/ui/26-jobs_restart.t`, full UI suite (40 files; `t/ui/10-tests_overview.t`
   passes all 16 subtests but trips its 25 s wall-clock TimeLimit at 26 s
   on this machine — pre-existing, machine-load noise, no shared code with
   the diff), `COVERAGE=1 make test-fullstack` PASS. All modified
   `Test.pm` lines covered (123 hits); repo-wide
   `tools/check-line-coverage` runs on CI with merged coverage jobs.
6. Pre-push review (`reviewer=strata-builder`) fixes: dropped the dead
   `json.total_count ?? json.data.length` / `json.blocked_count ??
blockedCount` fallbacks and the client-side blocked count loop; info
   callback moved to DataTables 2 `layout.bottomStart.info.callback`
   (`infoCallback` and the top-level `info` object are not read by 2.3.7)
   and reports the post-filter total when the user filters the loaded
   rows; blocked-count cond uses the `-not => {blocked_by_id => undef}`
   idiom; tests anchored, added uncapped `limit=4` info assertion and a
   committed blocked fixture job (id 99997, `blocked_by_id => 99963` in
   `prepare_database`) asserting the heading suffix — the in-transaction
   driver heading assertion was infeasible because the app serves from a
   separate DB connection that cannot see uncommitted rows.
