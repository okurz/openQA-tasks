# Plan: Enable HEAVY and FULLSTACK tests by default locally

## Problem

Currently, `make test` excludes "heavy" and "fullstack" tests unless `HEAVY=1` or `FULLSTACK=1` is explicitly set. In local development, we want these to be enabled by default to ensure better coverage before pushing, while CircleCI should continue running them separately in parallel jobs.

## Proposed Changes

1. Modify `Makefile` to set default values for `HEAVY` and `FULLSTACK` based on whether the environment variable `CI` is set.
2. Ensure `HEAVY` and `FULLSTACK` are passed to the test execution environment in `test-unit-and-integration`.

### Makefile changes

```makefile
# Default HEAVY and FULLSTACK to 1 if not in CI
ifeq ($(CI),)
HEAVY ?= 1
FULLSTACK ?= 1
else
HEAVY ?= 0
FULLSTACK ?= 0
endif
```

And in `test-unit-and-integration`:

```makefile
RETRY=${RETRY} HEAVY=${HEAVY} FULLSTACK=${FULLSTACK} HOOK=./tools/delete-coverdb-folder ...
```

## Verification

1. Run `make -n test` locally and verify that `HEAVY=1` and `FULLSTACK=1` are passed to the `prove` command.
2. Run `CI=1 make -n test` and verify that `HEAVY=0` and `FULLSTACK=0` are passed.
3. Verify that `make -n test-heavy` still correctly passes `HEAVY=1`.
