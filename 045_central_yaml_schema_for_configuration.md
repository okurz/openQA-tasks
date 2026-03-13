# Central YAML Schema for openQA Configuration

## Motivation

Currently, openQA configuration settings are defined across multiple locations:

1.  Default values are hardcoded in `lib/OpenQA/Setup.pm`.
2.  Template configuration and documentation exist in `etc/openqa/openqa.ini`.
3.  Verification logic for these defaults exists in `t/config.t`.

While recent refactoring (introducing `default_config()`) reduced code duplication, a disconnect remains between the code-defined defaults and the human-readable documentation in the `.ini` template. This leads to several maintenance burdens:

- New features require manual updates to both code and the template.
- Descriptions in `openqa.ini` can easily become outdated.
- Manual validation logic (type checking, range checking) is duplicated in Perl code.

By moving to a central YAML schema, we establish a single source of truth for every configuration setting in the application.

## Proposed Architecture

### 1. The Schema (`etc/openqa/config_schema.yaml`)

Define all configuration variables in a structured YAML file. This schema will include:

- **Section Name**: (e.g., `global`, `webui`, `misc_limits`)
- **Key Name**: (e.g., `render_batch_size`)
- **Description**: Detailed multi-line documentation for the setting.
- **Type**: Data type (e.g., `integer`, `string`, `list`, `boolean`) for automated validation.
- **Default**: The hardcoded fallback value.
- **Constraints**: Optional validation rules (e.g., `min: 50`, `regex: '...'`).

### 2. Implementation Steps

#### Phase 1: Core Refactoring

- **schema.yaml**: Create the initial schema by migrating the current `%defaults` from `OpenQA::Setup::default_config()`.
- **OpenQA::Setup**: Update `default_config()` to load and parse `etc/openqa/config_schema.yaml` at runtime (or generate a static cache during build).
- **Validation Engine**: Implement a generic validation layer in `OpenQA::Setup` that uses the `type` and `constraints` fields from the schema to validate user-provided `.ini` files on startup.

#### Phase 2: Documentation Automation

- **Generator Tool**: Create `tools/generate-config-template`. This script will read the YAML schema and output a perfectly formatted `etc/openqa/openqa.ini`.
- **Build Integration**: Add a pre-commit hook or a `make` target (`make update-config`) to ensure the `.ini` template is always in sync with the schema.

#### Phase 3: Enhanced UX

- **API Exposure**: Add a REST endpoint `GET /api/v1/config/schema` that returns the schema in JSON format.
- **Admin UI**: Use the schema to dynamically generate a configuration validator or even an experimental "Config Editor" in the web interface that provides instant feedback on invalid settings.

## Verification Plan

- **Unit Tests**: Update `t/config.t` to verify that `default_config()` correctly loads and translates the YAML schema.
- **Consistency Check**: Add a test that runs the generation tool and asserts that the version-controlled `etc/openqa/openqa.ini` matches the generated output exactly.
- **Validation Tests**: Write tests that provide invalid `.ini` files (wrong types, out of range) and assert that openQA logs appropriate warnings or errors based on the schema constraints.

## User Benefits

- **Administrators**: Always have accurate, up-to-date documentation in their configuration files.
- **Developers**: Can add new configuration settings by touching only one file (`config_schema.yaml`).
- **Stability**: Automated type-checking reduces the risk of runtime crashes caused by misconfiguration.
