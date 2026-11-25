# Execution Plan: Proposal 4 - Post-Install Health Check and Rollback

## Overview
Allow `openqa-continuous-update` to install packages as usual, but immediately run local health checks. If the system is broken, automatically invoke `snapper rollback` (or package downgrade) to restore service.

## Tasks

### 1. Implement Local Health Check Script
**Description**: Create `script/openqa-health-check`.
**Implementation details**:
- Write a script that checks if `openqa-webui.service`, `openqa-scheduler.service`, and `openqa-worker.target` are running and not failing.
- Perform a basic HTTP GET request to `localhost:80` (or `443`) and ensure it returns a valid HTTP 200 response with expected HTML elements (e.g., checking for basic UI rendering without obvious server errors).
- Alternatively, ping a specialized `/api/v1/health` endpoint if one exists.
- Exit `0` for healthy, `1` for unhealthy.

### 2. Integrate Check into Continuous Update Hook
**Description**: Run the health check immediately following the package update.
**Implementation details**:
- Modify `script/openqa-continuous-update`.
- After `zypper -n --no-refresh dup` completes successfully, restart the systemd services (if not done automatically by the RPM `%post` macro).
- Execute `script/openqa-health-check` (possibly with a short polling loop to allow services to start).

### 3. Implement Automated Rollback
**Description**: Trigger system rollback on health check failure.
**Implementation details**:
- In `script/openqa-continuous-update`, catch the failure of the health check.
- If failed, execute `snapper rollback` (assuming a btrfs root filesystem with transactional-update or standard snapper setup).
- Reboot the machine, or if using `zypper`, find the previous package version in the cache/repos and `zypper install --oldpackage`.
- Send an alert (via `logger` for systemd journal, or external Matrix hook if configured) indicating a failed update and successful rollback.
