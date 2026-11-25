# Execution Plan: Proposal 5 - PR Gating via Mergify with Opt-out Labels

## Overview

Shift the safety gate to the PR phase. Run `openqa-in-openQA` tests on every PR automatically (with `_OBSOLETE=1` to cancel stale runs). Gate merges on both OBS and openQA checks, but provide self-explanatory Mergify labels to bypass checks in emergency situations.

## Tasks

### 1. Configure GitHub Actions for openQA PR Tests (DONE)

**Description**: Automate `openqa-in-openQA` on PRs.
**Implementation details**:

- Create/update `.github/workflows/openqa-pr-check.yml` to trigger tests on `openqa.opensuse.org`.
- Ensure the API call to openQA passes `_OBSOLETE=1` and `_ONLY_OBSOLETE_SAME_BUILD=1` to auto-cancel older runs for the same PR.
- Point custom repositories to the OBS PR build repository (`OPENQA_REPO_URL`).
- The workflow reports check `openqa-in-openqa-tests` back to GitHub.

### 2. Update Mergify Configuration with Opt-out Labels (DONE)

**Description**: Redefine `.mergify.yml` to support explicit opt-out labels.
**Implementation details**:

- Implement the standard merge rule: Requires 2 approvals, `OBS` check, and `openqa-in-openqa-tests` check.
- Define self-explanatory labels and their corresponding Mergify rules:
  - `merge-skip-oqa-in-oqa-tests`: Merges when `OBS` check passes (skips openQA-in-openQA tests).
  - `merge-skip-obs-tests`: Merges when `openqa-in-openqa-tests` pass (skips OBS build tests).
  - `merge-skip-extended-tests`: Merges immediately without waiting for `OBS` or `openqa-in-openqa-tests`.
- Ensure rules are mutually exclusive to prevent Mergify conflicts.

### 3. Documentation & Policy Update (DONE)

**Description**: Document the new labels and the PR workflow.
**Implementation details**:

- Update `docs/Contributing.md` to document the new `openqa-in-openqa` CI check and Mergify auto-merge conditions.
- Explicitly define the `merge-fast`, `merge-skip-oqa-in-oqa-tests`, `merge-skip-obs-tests`, and `merge-skip-extended-tests` labels.
- Add a strict warning about label abuse and clarify that skipping extended tests should only be used for hotfixes (e.g., `Revert` commits) where MTTR is critical.
