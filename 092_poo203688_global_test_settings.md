# Execution Plan: 092_poo203688_global_test_settings

Implement global instance-wide test settings defined in the openQA configuration file (`openqa.ini` or files in `openqa.ini.d/*`).

## Scope & Requirements
1. **AC1:** Define `test_settings` section in `default_config` in `lib/OpenQA/Setup.pm`.
2. **AC2:** Ensure global instance-wide test settings have the lowest precedence, and are loaded prior to any entity-specific settings.
3. **AC3:** Support the `+` prefix to override precedence, even for instance-wide test settings.
4. **AC4:** Document the feature under `docs/UsersGuide.md`.
5. **AC5:** Extend commented examples in `etc/openqa/openqa.ini`.
6. **AC6:** Implement tests in `t/40-job_settings.t` or a dedicated test to verify implementation.

## Design Choices
* **Config definition:** We'll add `test_settings => {}` to `default_config()` in `lib/OpenQA/Setup.pm`. This allows arbitrary key-value pairs from `[test_settings]` section of `openqa.ini` to be populated automatically.
* **Precedence:** In `OpenQA::JobSettings::generate_settings()`, we'll load global `test_settings` using `OpenQA::App->singleton` at the very beginning, before processing entity-specific settings.
* **Case mapping:** Since config parameters can be specified in any case in INI, we will uppercase the keys when copying them to job settings.
* **WORKER_CLASS merging:** If `WORKER_CLASS` is specified, it will be added to the `@worker_class` list and combined with others, rather than overwritten.
