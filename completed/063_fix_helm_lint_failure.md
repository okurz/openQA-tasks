# Plan: Fix helm lint failure

The `make test-helm-lint` fails because `ct` (Chart Testing tool) cannot find the default schema files `chart_schema.yaml` and `lintconf.yaml`.
On this system, they are located in `/usr/share/doc/packages/chart-testing/` instead of the default search paths (`.`, `~/.ct/`, `/etc/ct/`).

## Proposed Changes

1. Update `container/helm/ct.yaml` to explicitly specify the schema paths.
   We will use the paths found on this system, but ideally we should make it robust.
   However, since this is for the current environment, pointing to them is a good first step.
   Actually, a better way might be to provide them in the repository to ensure portability across different CI environments.

2. I will copy `chart_schema.yaml` and `lintconf.yaml` from `/usr/share/doc/packages/chart-testing/` to `container/helm/` to make the linting process self-contained and portable.

## Verification

1. Run `make test-helm-lint` and ensure it passes.
2. Verify that no new errors are introduced.

## Steps

1. Copy `chart_schema.yaml` from `/usr/share/doc/packages/chart-testing/` to `container/helm/`.
2. Copy `lintconf.yaml` from `/usr/share/doc/packages/chart-testing/` to `container/helm/`.
3. Run `make test-helm-lint`.
