# Task: Fix Cache Service Non-Zero Exit Codes on Clean Stop

This task resolves the issue where `openqa-workercache-daemon` and `openqa-worker-cacheservice-minion` exit with non-zero codes (such as `80`, `136`, `152`, `232`) upon clean deactivation, causing systemd to flag them as failed.

## Analysis
- In `/home/okurz/local/os-autoinst/openQA/script/openqa-workercache`, the script invokes:
  ```perl
  exit OpenQA::CacheService::run(@ARGV);
  ```
- In `lib/OpenQA/CacheService.pm`:
  ```perl
  sub run (@args) {
      ...
      my $cmd_return_code = $app->start(@args);
      return $app->exit_code // $cmd_return_code // 0;
  }
  ```
- On a clean stop, `$app->exit_code` is undefined, so `run` returns `$cmd_return_code`, which is the return value of `$app->start`.
- In `prefork` mode, `$app->start` returns a blessed `Mojo::Log` object. In `run` (Minion) mode, it returns a blessed `Minion::Worker` object.
- Passing a blessed object to `exit` causes Perl to convert the reference to its numeric heap memory address.
- Since exit status is modulo 256, this pointer value results in erratic non-zero exit codes (like 80, 136, 152, 232) that systematic alignment rules (e.g. 16-byte alignment) produce.

## Proposed Steps

### Phase 1: Implementation
1. Modify `lib/OpenQA/CacheService.pm`'s `run` method to sanitize `$cmd_return_code`:
   ```perl
   my $cmd_return_code = $app->start(@args);
   return $app->exit_code // (ref $cmd_return_code ? 0 : $cmd_return_code) // 0;
   ```
   This ensures that any returned reference/object is converted to `0` instead of letting Perl cast it to an arbitrary pointer-based exit code.

### Phase 2: Testing
1. Add a unit test to `t/25-cache-service.t` to verify:
   - `OpenQA::CacheService::run` returns `0` when `$app->start` returns a blessed object (e.g., `Mojo::Log` or `Minion::Worker`).
   - Explicit non-zero `$app->exit_code` values are still correctly respected.

### Phase 3: Review and Linting
1. Execute `make tidy` or style checks to ensure compliance with the repository style guide.
2. Verify all tests pass cleanly.

---
## Progress and Results

- **Planning Phase:** [COMPLETED] - Root cause identified and architectural fix designed.
- **Implementation & Testing Phase:** [COMPLETED] - Fix implemented in `lib/OpenQA/CacheService.pm`. Initial test structure added and verified with `prove -Ilib t/25-cache-service.t`.
- **Review & Fix-up Phase:** [COMPLETED] - Precision-fixer reviewed the changes. Branch and condition coverage for `ref $cmd_return_code ? 0 : $cmd_return_code` was expanded to 100% using a parametrized, data-driven test case array. Verified clean compliance with `tools/tidyall` formatting, `perlcritic` checks, and the full style suite (`xt/`). All 23 tests in `t/25-cache-service.t` pass cleanly with maximum statement, branch, and condition coverage. Amended commit message with concise explanation of the pointer-to-exit-code numeric casting.
