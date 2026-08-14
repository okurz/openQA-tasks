# 065_poo199427_ignore_job_groups

Ignore job groups of openQA dashboard evaluation based on configuration.

## Motivation

Ticket #199427: o3 yields 502's due to the "Investigation" job group. We should be able to ignore job groups for the openQA dashboard evaluation based on configuration.

## Acceptance Criteria

- AC1: If configured (in openqa.ini or job group properties), job groups are excluded from evaluation for the main dashboard page.

## Implementation Details

### Configuration

Add a new setting `ignored_job_groups` to the `[global]` section of `openqa.ini`.
This will be a space-separated list of job group names.

### Database Schema Change

Add a new boolean column `ignore_on_dashboard` to both `job_groups` and `job_group_parents` tables.

- Update `lib/OpenQA/Schema/Result/JobGroups.pm`.
- Update `lib/OpenQA/Schema/Result/JobGroupParents.pm`.
- Bump schema version in `lib/OpenQA/Schema.pm`.
- Generate migration scripts with `./script/upgradedb --prepare_upgrade`.

### Backend Implementation

Modify `OpenQA::WebAPI::Controller::Main::dashboard_build_results` to filter out job groups that are:

1. Listed in `ignored_job_groups` config.
2. Have `ignore_on_dashboard` set to true.
3. Belong to a parent group that has `ignore_on_dashboard` set to true.

### Admin UI Implementation

Update the job group and parent group editor pages to include a checkbox for `ignore_on_dashboard`.

- `lib/OpenQA/WebAPI/Controller/API/V1/JobGroup.pm` (validation).
- `templates/webapi/admin/group/group_property_editor.html.ep`.
- `templates/webapi/admin/group/parent_group_property_editor.html.ep`.

## Verification Plan

### Test Cases

- **Case 1**: Add a job group name to `openqa.ini`'s `ignored_job_groups` and verify it's not shown on the dashboard.
- **Case 2**: Set `ignore_on_dashboard` for a job group via the API/UI and verify it's hidden.
- **Case 3**: Set `ignore_on_dashboard` for a parent group and verify all its subgroups are hidden.

### Test Files

I'll check for existing dashboard tests. `t/ui/01-list.t` or similar.
Actually, `t/api/v1/job_group.t` for API tests.
And maybe `t/01-main.t` for dashboard.

## Task Breakdown

- [ ] Load perl-dev skill
- [ ] Implement openqa.ini setting
- [ ] Implement database column and migrations
- [ ] Update backend logic for filtering
- [ ] Update Admin UI
- [ ] Verify with tests
- [ ] Commit changes
