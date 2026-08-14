# Task 103: xterm-console Python 3 Dependency (poo205026)

## Motivation

The build of `openQA_container_worker` container fails on Leap 16.0 / Factory because the package `xterm-console` requires `/usr/bin/python3`, which is no longer implicitly installed or is part of a split package structure. The executable `/usr/bin/python3` is provided by `python3-base`. Specifying `Requires: python3-base` explicitly in the `xterm-console.spec` file ensures that the dependency solver can resolve and install it during minimal and container builds.

## Design Choices

1. Modify `xterm-console.spec` inside `../xterm-console/` to add `Requires: python3-base`.
2. This resolves the `nothing provides '/usr/bin/python3' needed by xterm-console` error directly inside the package that actually uses it, which is the cleanest upstream packaging approach.

## Execution Steps

1. Add `Requires: python3-base` to `../xterm-console/xterm-console.spec`.
2. Validate spec file formatting and run any available checks in `../xterm-console`.
3. Commit the change in the `../xterm-console` repository.
4. Verify openQA workspace files are still tidy and run openQA checks to ensure everything is fine.
