# Task 144: Avoid format content negotiation deprecation warning

- Ticket: [poo#210252](https://progress.opensuse.org/issues/210252)
- Branch: `feature/144_poo210252_avoid_format_content_negotiation_deprecation`

## Approvals

- Decision: Map query parameter `format` to `_format` in `OpenQA::WebAPI::Plugin::REST` before dispatch to avoid Mojolicious 9.17+ content negotiation deprecation warnings while maintaining backward compatibility.
- Approver: User
- Date: 2026-11-12

## Gates

- Verification: `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS="t/17-build_tagging.t" && COVER_REPORT_OPTS="-select_re 'lib/OpenQA/WebAPI/Plugin/REST\.pm'" make check-line-coverage && make test-gitlint`

## Session starter

```bash
git status
make test-unit-and-integration TESTS="t/17-build_tagging.t"
```

## Requirements & Problem Statement

Production openQA web UI logs on o3 reported:

```
Nov 12 09:26:27 ariel openqa-webui-daemon[1878073]: The ?format=* parameter is deprecated in favor of ?_format=* for content negotiation at /usr/lib/perl5/vendor_perl/5.42.0/Mojolicious/Plugin/DefaultHelpers.pm line 28.
Nov 12 09:26:27 ariel openqa-webui-daemon[1878073]: The ?format=* parameter is deprecated in favor of ?_format=* for content negotiation at /usr/lib/perl5/vendor_perl/5.42.0/Mojolicious/Plugin/DefaultHelpers.pm line 28.
```

1. Mojolicious 9.17 deprecated the query parameter `?format=*` in favor of `?_format=*` for content negotiation in `Mojolicious::Renderer`.
2. When any client request includes `?format=*` (e.g. `?format=json` or `?format=rss`), Mojolicious outputs a deprecation warning via `carp` whenever `$c->respond_to` or `$c->accepts` is called.
3. This warning triggers alerts in monitoring tools like `logwarn` and pollutes daemon journal logs.

## Root Cause Analysis

In `Mojolicious::Renderer::accepts`:

```perl
sub accepts {
  my ($self, $c) = (shift, shift);

  # DEPRECATED!
  my $req   = $c->req;
  my $param = $req->param('format');
  deprecated 'The ?format=* parameter is deprecated in favor of ?_format=* for content negotiation' if defined $param;

  # List representations
  my $fmt  = $param // $req->param('_format') || $c->stash->{format};
  ...
```

If any client sends `?format=*` in the query string and the controller invokes `$c->respond_to(...)` or `$c->accepts(...)` (or if `OpenQA::WebAPI`'s `before_render` hook checks `$c->accepts('html')` and `$c->accepts('json')`), Mojolicious unconditionally emits this deprecation warning.

## Proposed Solution

1. In `lib/OpenQA/WebAPI/Plugin/REST.pm`:
   In the `before_dispatch` hook (which already handles method override via `_method`), intercept incoming query parameter `format`. If defined:
   - Map it to `_format` (unless `_format` is already present).
   - Remove `format` from `query_params`.
   - Clear cached `params` from `$c->req` (`delete $c->req->{params}`).
2. In `t/17-build_tagging.t`:
   Add test cases under `content negotiation` verifying that:
   - `?format=json` responds with `application/json` without emitting deprecation warnings.
   - `?_format=json` responds with `application/json`.
   - `?format=rss` responds with `application/rss+xml`.
   - `?_format=rss` responds with `application/rss+xml`.
3. Verification:
   Pass `make tidy`, `make test-checkstyle`, `make test-gitlint`, statement coverage check with `COVERAGE=1`.

## Progress Log

- [x] Phase 1: Planning and task breakdown
- [x] Phase 2: Implementation in `lib/OpenQA/WebAPI/Plugin/REST.pm` and `t/17-build_tagging.t`
- [x] Phase 3: Verification (`make tidy`, `make test-checkstyle`, `COVERAGE=1`, `make check-line-coverage`, `make test-gitlint`)
- [x] Phase 4: Commit `331834092` (`fix(rest): avoid ?format=* deprecation warning`) following `git-workflow`
- [x] Phase 5: Address pre-push review feedback (handle `body_params`, preserve multi-valued parameters, document internal cache clear, add test cases)
