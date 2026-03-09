# Implementation Plan - Ticket #197591: Allow filtering by result in `/tests/latest`

## Goal

Modify the `/tests/latest` and `/tests/latest/badge` routes to support filtering by job `result` (e.g., `passed`, `failed`, `incomplete`) and `state` (e.g., `done`, `running`). This allows users to create persistent links to the latest _successful_ job for a specific scenario.

## Proposed Changes

### 1. `lib/OpenQA/WebAPI/Controller/Test.pm`

Modify the `_get_latest_job` helper method to extract more query parameters.

**Current logic:**

- Iterates over `SCENARIO_WITH_MACHINE_KEYS` (distri, version, flavor, arch, test, machine).
- Collects these from request params.

**Target logic:**

- Add `result` and `state` to the whitelist of parameters extracted from the request.
- Pass these parameters to the `Jobs` resultset's `complex_query` method.

```perl
# lib/OpenQA/WebAPI/Controller/Test.pm

sub _get_latest_job ($self) {
    my %search_args = (limit => 1);
    # Whitelist scenario keys plus result and state filters
    for my $arg (OpenQA::Schema::Result::Jobs::SCENARIO_WITH_MACHINE_KEYS, qw(result state)) {
        my $key = lc $arg;
        next unless defined $self->param($key);
        $search_args{$key} = $self->param($key);
    }
    return $self->schema->resultset('Jobs')->complex_query(%search_args)->first;
}
```

### 2. Verification (Manual/Automated)

#### Automated Tests

Add test cases to `t/ui/18-tests-details.t` to verify the functionality.

- **Test 1:** Verify `/tests/latest?test=kde&machine=64bit&result=failed` returns the latest failed job.
- **Test 2:** Verify `/tests/latest?test=kde&machine=64bit&result=passed` returns the latest passed job.
- **Test 3:** Verify that a non-existent combination (e.g., `?result=parallel_failed` if none exist) returns a 404.

Add test case to `t/10-overview_badge.t` for the badge route.

- **Test 4:** Verify `/tests/latest/badge?test=kde&machine=32bit&result=passed` returns a badge for a passed job even if a newer failed job exists.

## Verification Checklist

- [ ] Run `make tidy` to ensure code style compliance.
- [ ] Run `make test-checkstyle` for syntax validation.
- [ ] Run `make test-unit-and-integration TESTS=t/ui/18-tests-details.t`
- [ ] Run `make test-unit-and-integration TESTS=t/10-overview_badge.t`
- [ ] Manually verify behavior with different `result` values.
