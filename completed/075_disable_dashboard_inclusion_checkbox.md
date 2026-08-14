# Task 075: Disable dashboard inclusion checkbox if ignored by config

## Motivation

The last commit ignores "Investigations" job groups from evaluation for dashboard inclusion by default. It is possible to control this exclusion by ini file config as well as job group properties configurable over web UI. We want to disable the checkbox on the job group and parent job group properties if a group is disabled by .ini file configuration with a hover text explaining why.

## Design Choices

- Check `app->ignored_groups` in the `group_property_editor.html.ep` template.
- Inherit the ignored state from the parent group if applicable.
- Use `disabled="disabled"` to gray out the checkbox.
- Use `checked="checked"` if ignored by config to reflect reality.
- Use `data-bs-toggle="tooltip"` and `title` to provide the explanation as hover text.

## Test Plan

- Create a new integration test `t/ui/group_properties_config_ignored.t` using `Test::Mojo`.
- Verify that the checkbox is disabled and checked when the group or its parent is in `ignored_job_groups`.
- Verify the hover text content.
