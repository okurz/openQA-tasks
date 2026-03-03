# Move author tests to xt/

Within the Perl ecosystem it is a common practice to split tests into dynamic tests in the "t/" folder and author tests in the "xt/" folder. The author tests can be excluded from any build environment test calls and focus on dynamic tests.

This plan describes moving static analysis and style checks to the `xt/` directory and updating the `Makefile` and CI configuration accordingly.

## Research

- [x] Identify author tests in `t/`:
    - `t/00-tidy.t`
    - `t/01-compile-check-all.t`
    - `t/01-style.t`
    - `t/02-pod.t`
    - `t/45-make-update-deps.t`
- [x] Check `Makefile` targets:
    - `test-tidy-compile-style` currently runs `t/*{tidy,compile,style}*.t`.
    - `test-t`, `test-ui`, `test-api` use `GLOBIGNORE` to skip these tests.
- [x] Check CircleCI: `checkstyle` job calls `make test-checkstyle`, which calls `test-tidy-compile-style`.
- [x] Check `dist/rpm/openQA.spec`: it explicitly uses `t/` for tests, so it will naturally skip `xt/`.

## Strategy

1. Move identified tests from `t/` to `xt/`.
2. Update `Makefile` to:
    - Introduce `test-author` target running `prove xt/`.
    - Update `test-tidy-compile-style` (or replace it) to use `xt/`.
    - Simplify `test-t` and other targets by removing `GLOBIGNORE` for moved files.
3. Update moved tests to ensure they check `xt/` as well (especially compile check and style check).
4. Verify that `make test-checkstyle` still runs all necessary checks.
5. Verify that `make test-t` no longer runs author tests but still passes.

## Execution Plan

### 1. Preparation
- Create the `xt/` directory.
- Move the following files:
    - `t/00-tidy.t` -> `xt/00-tidy.t`
    - `t/01-compile-check-all.t` -> `xt/01-compile-check-all.t`
    - `t/01-style.t` -> `xt/01-style.t`
    - `t/02-pod.t` -> `xt/02-pod.t`
    - `t/45-make-update-deps.t` -> `xt/45-make-update-deps.t`

### 2. Update Tests
- Update `xt/01-compile-check-all.t`:
    - Add `xt` to the list of directories to check: `all_perl_files_ok(qw(lib script t xt));`
- Update `xt/01-style.t`:
    - Update `git grep` patterns to include `xt/` where appropriate.
    - e.g. `git grep -I -L '^use Test::Most' t/**.t xt/**.t`
    - Ensure it doesn't fail on itself (if it excludes itself by path).

### 3. Update Makefile
- Rename `test-tidy-compile-style` to `test-author`.
- Update `test-checkstyle` to call `test-author` instead of `test-tidy-compile-style`.
- Update the `test-author` target:
    ```make
    .PHONY: test-author
    test-author: ## Run author tests (tidy, compile, style, pod, etc.)
        $(MAKE) test-unit-and-integration TIMEOUT_M=20 PROVE_ARGS="$$HARNESS xt/*.t" GLOBIGNORE="$(unstables)"
    ```
- Update `test-t`, `test-ui`, `test-api`:
    - Remove `t/*tidy*:t/*compile*:t/*style*` from `GLOBIGNORE`.
- (Optional) Provide `test-tidy-compile-style` as a deprecated alias for backward compatibility if needed, but given the "YOLO" mode and project size, a direct rename is preferred.

### 4. Update Other Configuration
- Update `t/testrules.yml`:
    - Update paths for moved tests (e.g., `./t/00-tidy.t` -> `./xt/00-tidy.t`).

### 5. Verification
- Run `make test-checkstyle` and ensure it passes.
- Run `make test-t` and ensure it doesn't run tests from `xt/`.
- Run `make test` to ensure everything is still correct.
- Check `t/` and `xt/` contents to ensure no files were left behind or misplaced.

## Verification Strategy

- **Automated Tests:**
    - `make test-checkstyle`: Should now include `xt/02-pod.t` and `xt/45-make-update-deps.t` if they are moved there and matched by `xt/*.t`.
    - `make test-t`: Should run fewer tests than before.
- **Manual Check:**
    - Verify that `xt/01-compile-check-all.t` actually checks files in `xt/`.
    - Verify that `xt/01-style.t` actually checks files in `xt/`.
