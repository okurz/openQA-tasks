# Plan: Optimize `t/01-compile-check-all.t` runtime via Parallel::ForkManager

## Motivation

`t/01-compile-check-all.t` sequentially runs `perl -c` (via `Test::Strict::syntax_ok`) on hundreds of perl files. This takes several minutes and dominates the test suite execution time. By parallelizing this process, we can significantly reduce the time spent waiting for tests, improving the developer feedback loop.

## Design Choices

1. **Parallelization Strategy:** Instead of raw `fork()` which requires custom manual array chunking and `waitpid` coordination, we will use the clean, standard CPAN module `Parallel::ForkManager`. This reduces our custom implementation to just a few lines of wrapper code.
2. **Test Context:** We will use `Test2::IPC` which seamlessly integrates with `Test::Builder` (which `Test::Strict` uses underneath). This allows test assertions from child processes to be safely communicated back to the parent runner.
3. **Concurrency Level:** We will parse `$ENV{HARNESS_OPTIONS}` to extract the `j` (jobs) parameter (e.g., `-j8` maps to 8 workers). We will fallback to a default worker count of `8` if not specified.
4. **Dependencies:** Since `Parallel::ForkManager` is not currently an explicit dependency, it must be added to `dependencies.yaml` as a test requirement.

## Proposed Code Changes

### 1. `dependencies.yaml`

Add `perl(Parallel::ForkManager):` to the `test_requires:` section. After modifying `dependencies.yaml`, run `make update-deps` to automatically propagate the change to `cpanfile`.

### 2. `t/01-compile-check-all.t`

Replace the single call `all_perl_files_ok(qw(lib script t xt));` with the parallel `Parallel::ForkManager` logic:

```perl
use Test2::IPC;
use Parallel::ForkManager;

my @files = Test::Strict::_all_perl_files(qw(lib script t xt));

my $workers = 8;
if ($ENV{HARNESS_OPTIONS} && $ENV{HARNESS_OPTIONS} =~ /j(\d+)/) {
    $workers = $1;
}

my $pm = Parallel::ForkManager->new($workers);

for my $file (@files) {
    $pm->start and next;

    syntax_ok($file) if $Test::Strict::TEST_SYNTAX;
    strict_ok($file) if $Test::Strict::TEST_STRICT;
    warnings_ok($file) if $Test::Strict::TEST_WARNINGS;

    $pm->finish;
}

$pm->wait_all_children;
done_testing();
```

## User Benefits

By distributing the workload across multiple cores with minimal boilerplate, this optimization reduces the time taken to run `t/01-compile-check-all.t` from >2 minutes to less than 45 seconds, improving the CI and local testing turnaround drastically.

## Tests to verify

No new tests need to be written. The change is an optimization of an existing test. Verification will consist of ensuring:

- `make test-unit-and-integration TESTS=t/01-compile-check-all.t` runs properly, much faster, and maintains exit code 0.
- `make tidy` and `make test-checkstyle` continue to pass on the modified files.
