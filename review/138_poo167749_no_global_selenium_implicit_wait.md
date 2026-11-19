# 138 — Drop the global Selenium implicit wait (poo/167749)

Related issue: https://progress.opensuse.org/issues/167749
Follow-up of `f321c5ccc perf(test): Skip implicit wait for absent elements`.

## Analysis

`OpenQA::SeleniumTest` sets a **global implicit-wait of 2000 ms** on the driver
(`enable_timeout`, t/lib/OpenQA/SeleniumTest.pm:47, enabled in `start_driver`
line 100). Every `find_element`/`find_elements` then blocks up to 2 s when the
element is absent. Tests work around this by toggling the global state:

| pattern                                                                         | count           |
| ------------------------------------------------------------------------------- | --------------- |
| `find_element(` call sites in `t/ui/*.t`                                        | 701             |
| `find_elements(` call sites                                                     | 189             |
| absence-style `find_elements` statements (`scalar … , 0`, `is_deeply [… , []]`) | 30              |
| `element_not_present` (pays 2 s per call)                                       | 14              |
| `element_visible` / `element_hidden` (rely on the implicit wait for presence)   | 64 / 25         |
| `disable_timeout` / `enable_timeout` in tests                                   | 8 / 4 (6 files) |
| explicit-wait helpers `wait_for_element` / `wait_until` / `wait_for_ajax`       | 58 / 28 / 229   |

Waste: ~44 absence checks × 2 s ≈ 88 s per suite run, ×2 in CI (`CI` scale
factor), ×5 under parallel harness. Measured data point: 15-admin-workers.t
21 s → 9 s by wrapping 3 absence checks.

Problems with the current design:

1. **Global mutable state.** `disable_timeout`/`enable_timeout` are exported
   subs with no scope. 4 of the 8 `disable_timeout` calls in tests never
   re-enable, so the driver state is inconsistent between files. An
   exception/`die` between a disable and its enable leaves the driver in the
   wrong state (the `catch` in `wait_for_element` exists only to undo this).
2. **Blunt instrument.** The same 2 s budget applies to a check that must
   wait for an animation and to a check that asserts something is _absent_
   (which can never pass by waiting — it always burns the full timeout).
3. **Hidden intent.** A test that "passes" because the implicit wait
   papered over a missing `wait_for_ajax` is not visible as such.
4. **`wait_until` default timeout is 100 s scaled** (line 321) — a failing
   wait blocks for ~100 s before `fail`.

Precedent: `c84235ef2` (2019, branch
`experimental-enhance/save_time_with_no_implicit_selenium_wait`, unmerged)
already removed `enable_timeout` from `start_driver` with exactly this
rationale. 4 test files effectively do it today via a top-level
`disable_timeout`.

## Design

Invert the default: **implicit wait 0 by default**, waiting is expressed
explicitly at the assertion site with a `timeout` parameter.

1. `start_driver` no longer calls `enable_timeout`; implicit wait stays 0.
2. Remove `enable_timeout`/`disable_timeout` from `@EXPORT` and from the 12
   call sites in tests.
3. Presence helpers gain an explicit, scaled `timeout` and are implemented on
   top of `wait_for_element` (which already toggles the implicit wait
   internally):
   - `element_visible($selector, $like, $unlike, $desc, %opts)` — `%opts` =
     `timeout` (default `scale_timeout(2)`, same budget as today's implicit
     wait), `check_interval`.
   - `element_hidden($selector, $desc, %opts)` — via
     `wait_for_element(selector, is_displayed => 0, timeout)`.
   - `element_not_present($selector, $desc)` — unchanged semantics, now free
     (implicit wait 0).
4. New `wait_for_element_count($selector, $expected_count, %opts)` for the
   list assertions (`#results tbody tr`, `h2`, table rows) that today rely on
   the implicit wait: poll until the count matches, then assert once.
   `wait_for_data_table` is folded into it.
5. Lower `wait_until`'s default timeout from 100 s to `scale_timeout(10)` so
   failing waits report fast; call sites that genuinely need longer pass an
   explicit `timeout`.
6. Keep `set_timeout(script => 2000)` — that bounds stuck JS, not element
   lookup.

No scoped-guard helper is needed once the implicit wait is gone; if a
call site truly needs the implicit wait, it uses `wait_for_element` with an
explicit timeout instead.

## Migration steps (atomic commits)

1. `feat(test): Explicit timeout on Selenium presence helpers` — add
   `timeout`/`check_interval` options to `element_visible`/`element_hidden`,
   add `wait_for_element_count`, implement them via `wait_for_element`.
   Behavior unchanged (implicit wait still 2 s).
2. `refactor(test): Drop global Selenium implicit wait` — remove
   `enable_timeout` from `start_driver`, drop the exports, delete the 12
   toggle call sites. Convert raw `find_element` presence assertions that
   follow async triggers (click, AJAX, page load) to `wait_for_element` /
   `wait_for_element_count`. Do it file by file, 25 Selenium-based UI tests,
   measuring runtime per file.
3. `perf(test): Lower default wait_until timeout` — 100 s → 10 s scaled,
   with explicit timeouts at the sites that need more.

## Test adaptations

- New subtest in `t/ui/15-admin-workers.t` exercising
  `wait_for_element_count` (worker table rows) and the `timeout` option of
  `element_visible` on a selector that appears asynchronously (popover).
- New subtest asserting `element_not_present` returns immediately (measure
  elapsed time with `clock_gettime`, assert < 0.5 s) — this locks in the
  performance goal as a regression test.
- `t/ui/10-tests_overview.t`, `t/ui/01-list.t`: convert the absence checks to
  the new helpers so the 2 s cost cannot return.
- Coverage: run
  `COVERAGE=1 make test-unit-and-integration TESTS="t/ui/15-admin-workers.t t/ui/10-tests_overview.t t/ui/01-list.t t/ui/14-dashboard.t t/ui/21-admin-needles.t"`
  then `make check-line-coverage` for `t/lib/OpenQA/SeleniumTest.pm`; the new
  branches (timeout option, count polling) must be covered.
- `make tidy`, `make test-checkstyle`, `make test-gitlint` must pass.
- Runtime gate: record per-file runtime before/after; the suite must not
  regress in runtime, target ≥30 % reduction for the 6 files with toggles.

## Risks

- Flakiness in CI (scale ×2, parallel ×5): explicit timeouts go through
  `scale_timeout`, so CI budgets grow with the harness; presence helpers keep
  the same 2 s budget as today, so no assertion becomes stricter.
- `find_element` (singular) dies through the driver `error_handler` when the
  element is missing; with implicit wait 0 this happens immediately. The
  migration in step 2 is the bulk of the work and must be done per file, not
  as a global flip.
