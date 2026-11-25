# Execution Plan: Proposal 2 - Publish Gate (OBS Staging / Tested Repository)

## Overview
Decouple deployment from raw OBS builds by introducing a `devel:openQA:tested` staging repository. Packages are only promoted to this repository *after* passing `openqa-in-openqa` tests.

## Tasks

### 1. Create Promotion Script `script/openqa-promote-package`
**Description**: Write a script (or bot logic) that copies packages between OBS projects upon test success.
**Implementation details**:
- Use `osc copypac` or the OBS API to copy `openQA`, `os-autoinst`, and related packages from `devel:openQA` to `devel:openQA:tested`.
- The script should accept a build number and verify via the openQA API that tests have passed for that build before issuing the OBS promotion command.

### 2. Automate Promotion via openQA Hook / Systemd Timer
**Description**: Run the promotion script automatically.
**Implementation details**:
- Provide documentation or a systemd timer (e.g., `openqa-promote-package.timer`) to poll openQA for successful builds.
- Alternatively, design it to be triggered by an openQA job post-hook (similar to how openqa-review works).

### 3. Update Client Scripts for Staging Repository
**Description**: Adjust the update scripts to monitor the new repository.
**Implementation details**:
- Edit `script/openqa-continuous-update` and `script/openqa-check-devel-repo` to change the default `DEVEL_OPENQA_REPOSITORY` to `devel:openQA:tested` (or make it a configurable environment variable with the new repository as the recommended default).

### 4. Update Documentation
**Description**: Document the new staging architecture.
**Implementation details**:
- Update `docs/Installing.md` to instruct users deploying production instances to add the `devel:openQA:tested` repository instead of `devel:openQA`.
- Explain the promotion lifecycle.
