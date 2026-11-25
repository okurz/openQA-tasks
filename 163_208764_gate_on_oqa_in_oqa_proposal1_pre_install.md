# Execution Plan: Proposal 1 - Pre-Install Gate via openQA API

## Overview
Prevent `openqa-continuous-update` from installing unstable openQA packages by directly verifying the `openqa-in-openqa` test results against the openQA API *before* running `zypper dup`.

## Tasks

### 1. Implement `openqa-check-openqa-in-openqa` Script
**Description**: Create a new bash (or Perl) script in `script/` that determines the candidate RPM version and queries the openQA API for test success.
**Implementation details**:
- Run `zypper --no-refresh info openQA` (or similar) to extract the candidate version/build number from the `devel:openQA` repository.
- Use `curl` or `openqa-cli` to query `https://openqa.opensuse.org/api/v1/jobs` matching the specific `BUILD` number or Git hash.
- Evaluate the test results (e.g., scenario `openqa-Tumbleweed-dev-x86_64-openqa_from_bootstrap@uefi-4G`).
- Exit `0` if passed, `1` if failed or running.
**Testing**: Create mock tests using dummy `zypper` output and mock API responses.

### 2. Integrate into `openqa-continuous-update`
**Description**: Call the new verification check within the existing continuous update loop.
**Implementation details**:
- Edit `script/openqa-continuous-update`.
- Before the final `zypper -n --no-refresh dup`, add a call to `$(dirname "${BASH_SOURCE[0]}")/openqa-check-openqa-in-openqa`.
- Ensure appropriate logging is added so administrators know *why* an update was skipped (e.g., "Skipping update: openqa-in-openqa tests failed for candidate build").

### 3. Documentation and Linting
**Description**: Ensure styles are met and update documentation.
**Implementation details**:
- Run `make test-checkstyle` (which runs `shellcheck`) on the new scripts.
- Update `docs/Installing.md` in the "Continuous Update" section to explain the new safeguard mechanism.
