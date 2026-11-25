# Plan - Optimize cache service tests and fix review issues

## Motivation

The recent optimization changes on `t/25-cache-service.t` introduced several regressions and style/structural issues.
Specifically:

1. Globally disabling `Devel::Cover` subprocess reporting violates the project's strict statement coverage requirements.
2. Exact SQLite busy timeout assertions were weakened or removed, reducing regression detection.
3. Hoisting the `OpenQA::CacheService` import to file scope in `t/lib/OpenQA/Test/Utils.pm` slows down all 48 tests importing it.
4. Several styling violations, such as extra blank lines and line length limits, were introduced.

We need to fix these issues while maintaining the actual optimization benefits (such as decreased wait intervals and polling delays).

## Design Choices

1. **Revert Devel::Cover monkey-patching**: Remove the `*Devel::Cover::can = sub { 0 }` override and the `$Devel::Cover::CAN_REPORT = 0` line.
2. **Restore SQLite assertions**: Revert the `Increased SQLite busy timeout` subtest to exactly assert `600000` for both the cache app and the minion backend databases.
3. **Lazy load CacheService**: Move the `require OpenQA::CacheService` back inside the worker subroutine in `t/lib/OpenQA/Test/Utils.pm`, removing the file-level import.
4. **Remove extra blank lines**: Clean up consecutive blank lines.
5. **Adjust environment variables**: Ensure that we retain the performance wins from reducing polling delays and sync iterations, but keep the test codebase correct, robust, and clean.

## Verification Plan

1. Run `make tidy` and `make test-checkstyle` to verify code format.
2. Run `make test-unit-and-integration TESTS=t/25-cache-service.t` to ensure the test passes.
3. Run `COVERAGE=1 make test-unit-and-integration TESTS=t/25-cache-service.t` and check coverage with `cover -report text` to ensure the coverage stays high and the test behaves correctly.
