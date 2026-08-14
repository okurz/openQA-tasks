# 105: Always show version configuration option

## Motivation

Currently, on the job group overview page (`/group_overview`), the version of a build is only displayed if there are multiple versions associated with a single build number. When testing single versions, the version label is omitted, making it confusing to differentiate builds that come from different sources but share the same build number. Providing a configuration option per job group (and parent job group) to always display the version label will resolve this.

## Design Choices

1. **Schema Update:**
   - Add a new boolean column `always_show_version` (nullable) to both `JobGroups` (`lib/OpenQA/Schema/Result/JobGroups.pm`) and `JobGroupParents` (`lib/OpenQA/Schema/Result/JobGroupParents.pm`).
   - In `lib/OpenQA/JobGroupDefaults.pm`, add `ALWAYS_SHOW_VERSION => 0`.
   - Increment `$VERSION` in `lib/OpenQA/Schema.pm` to 106.
   - Generate database migrations using `./script/upgradedb --prepare_upgrade`.

2. **Backend Logic & API:**
   - In `JobGroups.pm`, add an `around` modifier for `always_show_version` so it falls back to the parent group's value, similar to `carry_over_bugrefs`.
   - Update `OpenQA::WebAPI::Controller::API::V1::JobGroup` to allow `always_show_version` in `_validate_common_properties`.
   - In `OpenQA::WebAPI::Controller::Main`, when constructing the `$group_hash` for the overview templates, include the `always_show_version` attribute.

3. **Frontend Templates (Admin UI):**
   - Update `templates/webapi/admin/group/group_property_editor.html.ep` and `templates/webapi/admin/group/parent_group_property_editor.html.ep` to include a checkbox for "Always show version".

4. **Frontend Templates (Group Overview):**
   - Update `templates/webapi/main/group_builds.html.ep` to check if `!$group->{always_show_version}` before defaulting to omit the version string when `version_count <= 1`.

5. **Tests:**
   - Add test coverage in `t/api/job_groups.t` to verify the setting can be retrieved and updated via the API.
   - Add test coverage in `t/ui/03-group_overview.t` to ensure the version is visible when the setting is enabled for a group with single-version builds.

## Benefits

- Improves readability on `/group_overview` pages for single-version builds.
- Preserves the existing compact formatting as the default behavior.
- Configurable per-group or per-parent-group, allowing flexible management across different products.
