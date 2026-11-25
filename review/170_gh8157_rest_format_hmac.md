# 170 gh#8157: REST plugin's `format` → `_format` rewrite breaks HMAC verification

Ticket: https://github.com/os-autoinst/openQA/issues/8157 (GH issue, assignee okurz)
Baseline: `origin/master` `e4d215515`; worktree `~/local/os-autoinst/oqa-170-gh8157-format-hmac`
Branch: `feature/170_gh8157_rest_format_hmac` (branched from `origin/master`)
Numbering: prefix `170` = next free number across `tasks/` and local branches.

## Problem

`OpenQA::WebAPI::Plugin::REST::register` maps the deprecated `format` parameter to
`_format` in a `before_dispatch` hook by mutating `$req->query_params` (=
`$req->url->query`) and `$req->body_params` in place (commit `0c72ddd9f9`, PR #8104).
`OpenQA::Shared::Controller::Auth::_key_auth` verifies HMACs over
`$req->url->to_string`, so for a signed request that carries `format` in the query
the server hashes `…&_format=X` while the client (`OpenQA::UserAgent::_path_query`,
hence `openqa-cli`) signed `…&format=X` → 403.

Impact today is latent (every route constrained on `format` is a UI GET outside
API-key auth), but it ties signature verification to a content-negotiation shim.

## Fix

Two changes, both needed for "the signature covers the query the client sent":

1. `Auth`: verification must hash the query re-serialized by `Mojo::Parameters`
   (`_signing_url`), not whatever raw percentage encoding the request line carried.
   Today that normalization only happens because the REST hook parses
   `$req->query_params` in place; `OpenQA::UserAgent::_path_query` mirrors it
   (`%20` → `+`). Hashing must not depend on another component's parse side effect.
2. `REST`: keep the request URL untouched and rewrite only the merged parameter
   view that content negotiation reads: build `$req->{params}` (the cache behind
   `$req->param`/`$req->params`) from cloned `body_params`/`query_params` with the
   same per-source `format` → `_format` mapping as today, merged in the same order
   as `Mojo::Message::Request::params` (body clone + appended query).

- `$req->url` stays semantically untouched, so the HMAC basis is the client query.
- `Mojo::Renderer::accepts` no longer sees `format`, so the `?format=*`
  deprecation warning stays suppressed (precedence unchanged: `param()` returns
  the last value, existing `_format` wins per source).
- `_method` keeps working; it is read from the rewritten params.

## Tasks (two commits)

C1 — `fix(auth): hash the client-serialized query for API signatures`
Files: `lib/OpenQA/Shared/Controller/Auth.pm`, `t/api/03-auth.t`.
Behaviour-preserving today (the REST hook already parses the query).
- Add `_signing_url` (clone URL, parse query) and use it in `check` and `_key_auth`;
  keep the `X-Original-URI` branch for `/api/v1/auth` as is.
- Extend the "Auth::check validation …" subtest with a `%20` query: signing the
  raw encoding fails, signing the client-serialized `+` form succeeds.

C2 — `fix(rest): map format to _format without rewriting the request URL`
Files: `lib/OpenQA/WebAPI/Plugin/REST.pm`, `t/api/03-auth.t`.
- Add the helper that clones a `Mojo::Parameters` and maps `format` → `_format`
  (only when the source has no `_format`), used for both body and query params.
- Replace the in-place mutation + `delete $req->{params}` with the clone/merge
  assignment; keep `format`/`_format` precedence and `_method` handling.
- New subtest in `t/api/03-auth.t` (after "access granted for admins"):
  - `PUT /api/v1/operator_plugin?format=json` with the standard client signing
    → 200;
  - same request with `X-API-Hash` computed over the server-side `_format`
    rewrite → 403.
- Existing `t/17-build_tagging.t` "content negotiation" subtest must stay green
  unchanged (`?format=`, `?_format=`, body `format`, `_method`);
  `t/api/04-jobs.t` (`?comment=via restart`, i.e. `%20` in a signed query) is the
  regression guard for C1.

## Gates

```
COVERAGE=1 make test-unit-and-integration TESTS="t/api/03-auth.t t/api/04-jobs.t t/17-build_tagging.t"
make check-line-coverage                      # only changed lines
make tidy && make test-checkstyle             # checkstyle's xt/45 needs a committed tree
```

Wider set run before committing: all `t/api/*.t`, `t/03-auth.t`,
`t/10-tests_overview.t`, `t/17-build_tagging.t` (928 tests, pass).

## Approvals

- Fix strategy (keep URL semantically intact, rewrite the params view only, plus
  canonicalize the query in `Auth` instead of relying on the plugin's parse side
  effect) chosen from the three options listed in gh#8157. Recorded 2026-02-24,
  per the ticket author (okurz).

## Out of scope

- Avoiding `body_params` parsing for non-form request bodies (pre-existing cost
  from #8104); no behaviour change here.
- Changing what `?format=`/`?_format=` precedence *should* be.

## Session starter

```
Read tasks/170_gh8157_rest_format_hmac.md in full, run `git status` first, and
keep the baseline at origin/master e4d215515. Load the `perl-dev`, `testing`,
`openqa`, `git-workflow` skills. Implement C1 then C2 on
feature/170_gh8157_rest_format_hmac, run the gates above, then open the PR.
Never stage tasks/.
```
