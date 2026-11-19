# Developer Test Environment with Pre-loaded Fixtures

## 1. Context and Motivation

Currently, `make run-webui-test-env` starts a local openQA Web UI instance backed by an empty test PostgreSQL database. While useful for bare service testing, it requires developers to manually construct jobs, job groups, workers, and test results to inspect or verify UI behavior.

Developers often resort to stepping through full UI test suites in the debugger (`perl -Ilib -d t/ui/01-list.t`) to reach an initialized state with fixture data. Providing a dedicated script and concise Makefile targets allows developers to effortlessly start an interactive local openQA instance pre-loaded with rich mock data from `t/fixtures/` (`01-jobs.pl` to `07-needles.pl`), active asset flags, and frictionless authentication.

## 2. Architecture & Design Choices

1. **Standalone Helper Script (`tools/init-test-fixtures`)**:
   - Encapsulates database initialization, schema deployment, fixture population, and mock asset activation.
   - Keeps Makefile targets concise (1-2 lines).
   - Supports CLI flags:
     - `--fixtures=GLOB`: Specify fixture files (default: `*.pl` to load all fixtures).
     - `--reset`: Reset/drop schema before populating fixtures for a clean slate.
     - `--silent`: Suppress verbose fixture loading output.
   - Activates mock assets (`assume_all_assets_exist`) so UI asset links, logs, and downloads do not 404.
   - Prints helpful developer URLs (`http://localhost:9526/`, `/tests/overview`, `/tests/99981`, `/admin/workers`) and login details (`Demo` user with operator/admin rights).

2. **Makefile Targets**:
   - `load-test-fixtures`: Runs `setup-database` and executes `tools/init-test-fixtures`.
   - `run-webui-mock-env`: Runs `load-test-fixtures` and launches `script/openqa-webui-daemon`.
   - `run-mock-env`: Runs `load-test-fixtures` and launches all test daemons (`webui`, `websockets`, `scheduler`, `worker`, `gru`).

## 3. Execution Plan

### Task 1: Create Helper Script `tools/init-test-fixtures`

- **Path:** `tools/init-test-fixtures`
- **Implementation:**
  - Connect to `TEST_PG` using `OpenQA::Schema::connect_db(mode => 'test', deploy => 0)`.
  - Handle schema reset when `--reset` is requested.
  - Call `OpenQA::Test::Database->new->create(skip_schema => 1, fixtures_glob => $fixtures)`.
  - Call `OpenQA::Test::Utils::assume_all_assets_exist()`.
  - Output summary banner with quick-access links.

### Task 2: Makefile Targets Integration

- **Path:** `Makefile`
- **Implementation:**
  - Add `.PHONY: load-test-fixtures` calling `tools/init-test-fixtures`.
  - Add `.PHONY: run-webui-mock-env` chaining `load-test-fixtures` and `run-webui-test-env`.
  - Add `.PHONY: run-mock-env` chaining `load-test-fixtures` and `run-test-env`.

### Task 3: Automated Tests & Verification

- **Path:** `t/44-init-test-fixtures.t`
- **Implementation:**
  - Run `tools/init-test-fixtures` against a temporary schema.
  - Verify exit code is 0 and tables contain populated rows (e.g. jobs, users, job groups).
  - Verify `assume_all_assets_exist` set `size => 0` on assets.
- **Verification:**
  - `make test-unit-and-integration TESTS=t/44-init-test-fixtures.t`
  - `make tidy` and `make test-checkstyle`
