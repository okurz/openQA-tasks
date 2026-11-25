# 139: Project-Agnostic OBS PR Diagnostics & Recovery Tool

## Motivation

OBS SCM/CI workflow integration (`.obs/workflows.yml`) used across repositories
(openQA, os-autoinst, os-autoinst-scripts) frequently leaves PR staging projects
in broken, unbranched, or unconfigured states when concurrent webhooks clash or
step operations fail. Recovering from these failures currently requires manual,
ad-hoc inspection with `osc` commands, XML parsing, and manual PR re-triggering.

A project-agnostic CLI tool `~/bin/obs-pr-repair` will automate diagnosis,
health checks, and safe recovery across any repository using OBS SCM workflows.

## Requirements & Architecture

- **Location**: `~/bin/obs-pr-repair` (in the user's `~/bin` dotfiles repository).
- **Implementation Language**: Python 3 (consistent with `~/bin` tools, `ruff`,
  and `pytest` in `~/bin/Makefile`).
- **Context Resolution**:
  - Auto-detects GitHub repository (`<owner>/<repo>`) from `git remote` or `gh repo view`.
  - Parses `.obs/workflows.yml` in current repository to resolve:
    - Target project base (`%{target_project}`)
    - Source project & package (`%{source_project}/%{source_package}`)
    - Configured repositories and architectures
    - Full OBS PR project path: `<target_project>:<owner>:<repo>:PR-<number>`
  - Supports explicit overrides (`--project <PROJ>`, `--pr <PR>`, `--repo <OWNER/REPO>`)
    when run outside of a repository directory.
- **Diagnostics**:
  - Project existence (`osc meta prj <project>`)
  - Repository presence (`<repository>` tags in project meta)
  - Package branching state (checks whether `openQA` or source package has files,
    `_link`, `_service`, or is an empty/unbranched directory)
  - Build status summary (`osc results <project>`)
- **Recovery Actions**:
  - `--check` (default): Read-only diagnosis reporting health status.
  - `--recreate`: Deletes broken project (`osc rdelete -r`) and cycles PR
    (`gh pr close <PR> && gh pr reopen <PR>`) with confirmation prompt.
  - `--repair-branch`: Force-branches package (`osc branch -f`) and updates
    `_branch_request` if project exists but package is unbranched.
  - `--rebuild`: Triggers `osc rebuild <project>` if project is healthy.
  - `--yes` / `-y`: Bypasses confirmation prompts for scripted workflows.

---

## Atomic Implementation Tasks

### Task 1: Context Detection & Workflow Configuration Parsing

- Implement CLI argument parsing using `argparse`.
- Implement automatic git/GitHub context detection (`git remote get-url`, `gh pr view`).
- Implement parser for `.obs/workflows.yml` to extract workflow steps, target project,
  source project, and target repository configuration.
- Implement OBS PR project name generator matching OBS SCM workflow rules.
- **Verification**: Unit tests with sample `.obs/workflows.yml` files (openQA,
  os-autoinst) and mocked git repository configurations.

### Task 2: OBS Health Diagnostics Engine

- Implement read-only OBS inspection via `osc` wrappers:
  - Query project metadata (`osc meta prj`) and extract repository count.
  - Query package listing (`osc ls <project>`) and file listing (`osc ls <project> <pkg>`).
  - Query build results (`osc results <project>`).
- Implement health classifier returning status enum:
  - `HEALTHY`: Repositories configured, package branched, builds scheduled/done.
  - `BROKEN_EMPTY_PROJECT`: Project exists, but 0 repositories and empty package.
  - `BROKEN_UNBRANCHED_PACKAGE`: Project and repositories exist, but package has no sources.
  - `NOT_FOUND`: OBS project does not exist yet.
- Implement structured terminal output showing diagnostic table and suggested action.
- **Verification**: Unit tests mocking `osc` CLI responses for each failure mode.

### Task 3: Recovery Operations & Safe Execution

- Implement `--recreate` handler:
  - Verify user confirmation (unless `--yes` specified).
  - Execute `osc rdelete -r <project>`.
  - Execute `gh pr close <PR> && gh pr reopen <PR>`.
- Implement `--repair-branch` handler:
  - Execute `osc branch -f <source_prj> <source_pkg> <target_prj> <target_pkg>`.
  - Synchronize `_branch_request` with PR commit SHA.
- Implement `--rebuild` handler (`osc rebuild <project>`).
- Add safety pre-flight checks: verify `osc whois` and `gh auth status` succeed.
- **Verification**: Unit tests mocking subprocess calls and verifying command arguments.

### Task 4: Integration in `~/bin`, Linters & Documentation

- Place executable script in `~/bin/obs-pr-repair`.
- Add test file in `~/bin/test/test_obs_pr_repair.py`.
- Run `ruff check` and `pytest` in `~/bin/` to ensure clean integration with `~/bin/Makefile`.
- Document usage examples in tool `--help` and in `~/bin/README`.
- **Verification**: Run `make checkstyle` and `make test-unit` in `~/bin/`.
