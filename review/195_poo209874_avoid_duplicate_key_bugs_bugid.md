# Task 143: Avoid duplicate key error on bugs_bugid unique constraint

- Ticket: [poo#209874](https://progress.opensuse.org/issues/209874)
- Branch: `feature/143_poo209874_avoid_duplicate_key_bugs_bugid`

## Approvals

- Decision: Handle concurrent bug creation in `OpenQA::Schema::ResultSet::Bugs::get_bug` using `ON CONFLICT (bugid) DO NOTHING` to prevent `bugs_bugid` unique constraint errors, and avoid rendering HTML markdown in MCP `openqa_get_job_info` comments.
- Approver: User
- Date: 2026-11-10

## Gates

- Verification: `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS="t/25-bugs.t t/api/17-mcp.t" && COVER_REPORT_OPTS="-select_re 'lib/OpenQA/(Schema/ResultSet/Bugs|WebAPI/Plugin/MCP)\.pm'" make check-line-coverage && make test-gitlint`

## Session starter

```bash
git status
make test-unit-and-integration TESTS="t/25-bugs.t t/api/17-mcp.t"
```

## Requirements & Problem Statement

Production openQA web UI log reported:

```
Nov 05 11:16:06 openqa openqa-webui-daemon[735111]: [error] MCP request failed: DBIx::Class::Storage::DBI::_dbh_execute(): DBI Exception: DBD::Pg::st execute failed: ERROR:  duplicate key value violates unique constraint "bugs_bugid"
```

1. Concurrent requests querying or mentioning the same newly referenced bug ID can encounter a race condition where both attempt to insert into `bugs`, triggering a Postgres unique constraint violation (`bugs_bugid`).
2. In `OpenQA::WebAPI::Plugin::MCP`, `tool_openqa_get_job_info` rendered comments via `extended_hash` (defaulting to `$render_markdown = 1`), outputting HTML formatted markdown (`renderedMarkdown`) into a plain-text template (`openqa_get_job_info.txt.ep`) and invoking `get_bug` during read-only tool calls.

## Root Cause Analysis

1. In `lib/OpenQA/Schema/ResultSet/Bugs.pm`:

   ```perl
   sub get_bug ($self, $bugid = undef, %attrs) {
       return undef unless $bugid;
       my $bug = $self->find_or_new({bugid => $bugid, %attrs});
       return ($bug->refreshed && $bug->existing) ? $bug : undef if $bug->in_storage;
       $bug->insert;
       OpenQA::App->singleton->emit_event(openqa_bug_create => {id => $bug->id, bugid => $bug->bugid, implicit => 1});
       return undef;
   }
   ```

   Between `find_or_new` and `$bug->insert`, a concurrent process or request may insert the same bug. When the second process executes `$bug->insert`, it fails with `ERROR: duplicate key value violates unique constraint "bugs_bugid"`.

2. In `lib/OpenQA/WebAPI/Plugin/MCP.pm`:
   `my @comments = map { $_->extended_hash } $job->search_related(comments => {})->all;`
   and in `openqa_get_job_info.txt.ep`:
   `<%= $comment->{renderedMarkdown} %>`
   This unnecessarily parses markdown, extracts bugrefs, and invokes `get_bug` (which inserts records into `bugs` during what is supposed to be a read-only MCP tool call) while dumping HTML tags into the plain-text MCP response.

## Proposed Solution

1. **Atomic bug insertion with conflict handling in `OpenQA::Schema::ResultSet::Bugs::get_bug`**:
   - First check if the bug already exists: `if (my $bug = $self->find({bugid => $bugid})) { return ($bug->refreshed && $bug->existing) ? $bug : undef; }`
   - Use `INSERT INTO bugs (bugid, t_created, t_updated) VALUES (?, now(), now()) ON CONFLICT (bugid) DO NOTHING RETURNING id` (as in `Screenshots.pm` and `Assets.pm`).
   - If an `id` is returned, emit `openqa_bug_create` and return `undef`.
   - If no row is returned (conflict occurred), re-query `$self->find({bugid => $bugid})` and return `($bug && $bug->refreshed && $bug->existing) ? $bug : undef`.

2. **Clean text comments in MCP `openqa_get_job_info`**:
   - Call `$_->extended_hash(0)` in `tool_openqa_get_job_info`.
   - Use `<%= $comment->{text} %>` in `openqa_get_job_info.txt.ep`.

3. **Verification**:
   - Add unit test in `t/25-bugs.t` verifying concurrent/duplicate `get_bug` insertion without errors.
   - Update `t/api/17-mcp.t` verifying comments with bug references are returned as plain text without side effects.
   - Pass `make tidy`, `make test-checkstyle`, `COVERAGE=1 make test-unit-and-integration`, and line coverage check.

## Progress Log

- [x] Phase 1: Planning and task breakdown
- [x] Phase 2: Implementation in `lib/OpenQA/Schema/ResultSet/Bugs.pm` and `t/25-bugs.t`
- [x] Phase 3: Commit 1: `63fc1d905` (`fix(db): avoid duplicate key error on bugs_bugid`)
- [x] Phase 4: Implementation in `lib/OpenQA/WebAPI/Plugin/MCP.pm` and `t/api/17-mcp.t`
- [x] Phase 5: Commit 2: `7c6fcf20f` (`fix(mcp): use plain text comments in openqa_get_job_info`)
- [x] Phase 6: Verification (`make tidy`, `make test-checkstyle`, `make test-gitlint`, `COVERAGE=1`, `make check-line-coverage`)
- [x] Phase 7: Pre-push review and fix-up addressing reviewer findings
- [x] Phase 8: Address Martchus's PR review feedback in `lib/OpenQA/Schema/ResultSet/Bugs.pm` (`_insert_implicit` always returns the bug object, eliminating duplicate `$self->find` logic). Rebase onto latest master with PR #8110, verified with `make tidy`, `make test-checkstyle`, `make test-gitlint`, and 100% statement coverage.
