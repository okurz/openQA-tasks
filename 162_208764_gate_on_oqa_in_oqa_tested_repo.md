# Execution Plan: Decoupled Staging via `devel:openQA:tested`

## Overview
Ensure `o3` and `osd` install tested packages without tying updates to the slower Factory submission cycle or blocking developer PRs. We will use `devel:openQA:tested`, expanding its build targets to include Leap 16.0 (and pulling in `devel:openQA:Leap:16.0` dependencies as needed). Packages will be promoted to `:tested` automatically upon passing `openqa-in-openqa` tests.

## Tasks

### 1. Configure OBS Targets for `devel:openQA:tested` (Infrastructure)
**Description**: Ensure `:tested` builds for Leap 16.0.
**Implementation details**:
- *Manual/Infra Step*: Add the `16.0` build target to the `devel:openQA:tested` project in OBS.
- *Manual/Infra Step*: Ensure `devel:openQA:Leap:16.0` is linked or configured as a repository path for the `16.0` target in `:tested` to resolve dependencies correctly, identical to the `devel:openQA` setup.

### 2. Automate Package Promotion to `:tested`
**Description**: Promote packages from `devel:openQA` to `devel:openQA:tested` the moment `openqa-in-openqa` tests pass.
**Implementation details**:
- Implement a script or bot (e.g., as part of an openQA job hook or a GitHub Action triggered by openQA webhook) that runs `osc copypac` or uses the OBS API to copy `openQA` and `os-autoinst` from `devel:openQA` to `devel:openQA:tested`.
- The trigger must be strictly tied to a successful `openqa-in-openqa` test run for the corresponding commit/build.

### 3. Point Deployment Scripts to `:tested`
**Description**: Update continuous update configurations to use the tested repository.
**Implementation details**:
- Update `docs/Installing.md` to document that `devel:openQA:tested` is the recommended repository for production deployments, rather than `devel:openQA`.
- (Optional) Modify `script/openqa-continuous-update` default `DEVEL_OPENQA_REPOSITORY` from `devel:openQA` to `devel:openQA:tested`, or just rely on the system administrator configuring the repository name locally.

### 4. Implement Auto-Rollback on Update Failure
**Description**: Add a fail-safe using `zypper --oldpackage` if the update results in local service failures.
**Implementation details**:
- In `script/openqa-continuous-update`, immediately following the `zypper dup`, implement a local systemd health check (e.g., `systemctl is-active openqa-webui openqa-scheduler`).
- If services fail to start, use `zypper -n in --oldpackage` to revert to the previously installed version (the script will need to cache/record the old version string prior to the `dup`).
- Add logic to restart services and log/alert the rollback event.
