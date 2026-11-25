# Execution Plan: Proposal 3 - Pre-Merge Gate (GitHub PR CI)

## Overview
Prevent regressions from ever merging into `master` by running UI tests via openQA on every Pull Request.

## Tasks

### 1. Create GitHub Action for Ephemeral OBS Builds
**Description**: Automate the creation of a test RPM for each PR.
**Implementation details**:
- Add `.github/workflows/openqa-pr-test.yml`.
- The workflow uses the `osc` CLI or an OBS GitHub Action to create a scratch build in a temporary OBS project (e.g., `home:openqa_bot:PR_XXX`) based on the PR's merge commit.
- Wait for the OBS build to publish.

### 2. Trigger and Poll openQA Tests
**Description**: Trigger the `openqa-in-openqa` test suite against the ephemeral package.
**Implementation details**:
- Extend `.github/workflows/openqa-pr-test.yml` to call `openqa-cli api -X POST jobs ...` to schedule a test on `openqa.opensuse.org` (or a dedicated staging instance).
- Pass the repository URL of the scratch build to the test parameters.
- Poll the API until the job completes.
- Report the job status (pass/fail) back to the GitHub PR as a required status check.

### 3. Documentation & Policy Update
**Description**: Make the Pre-Merge CI official.
**Implementation details**:
- Update `CONTRIBUTING.md` to explain the new PR check, how long it takes, and how developers can view the openQA test artifacts (screenshots, videos) when a PR check fails.
- (Requires admin action, not code) Set the new GitHub Action check as "Required" in the `master` branch protection rules.
