# Execution Plan for PR 5038 Follow-up (uc_params)

## Context

The previous commit (`3e936801c`) on branch `feature/uc_params` attempted to support lower-case test arguments in the CLI by unconditionally running `$arg = uc $arg;` in `OpenQA::Command::parse_params`.

**Reviewer Feedback from PR 5038:**

1. "Wouldn't this upper-case any kind of parameter (and not only ones ending up job settings)? Then it would be very wrong." (Since `openqa-cli api` handles arbitrary parameters like `email=foo`).
2. "Yeah, and it would also uppercase the value of the setting, e.g. distri=Tumbleweed => DISTRI=TUMBLEWEED"

## Goals

- Allow lowercase parameter names (keys) to be automatically upcased when they are meant to be job settings (specifically for `openqa-cli schedule`).
- Preserve casing for parameter values.
- Preserve casing for parameter names when using `openqa-cli api` since it handles generic API parameters.
- Provide test coverage for the changes.

## Implementation Steps

### 1. Fix the Overly Broad Change in `lib/OpenQA/Command.pm`

- Update the signature of `parse_params` to accept a new `$uc_keys` parameter (defaulting to 0/false).
  ```perl
  sub parse_params ($self, $args, $param_file, $uc_keys = 0) { ... }
  ```
- Change the hash population logic to selectively upcase the key (`$1`) without touching the value (`$2`):
  ```perl
  my $key = $uc_keys ? uc $1 : $1;
  push @{$params{$key}}, $2;
  ```
- Make sure to apply this to both direct `$args` and `$param_file` entries.

### 2. Update `openqa-cli schedule` in `lib/OpenQA/CLI/schedule.pm`

- Update the call to `parse_params` to explicitly enable key upcasing, as `schedule` exclusively handles job settings:
  ```perl
  my $params = $self->parse_params($args, $options->{'param-file'}, 1);
  ```

### 3. Maintain `openqa-cli api` Behavior in `lib/OpenQA/CLI/api.pm`

- Ensure the call to `parse_params` does not pass `1` for `$uc_keys`, keeping the default `0` behavior. This ensures `openqa-cli api` retains lowercase/mixed-case parameter keys by default.

### 4. Update and Add Tests

**In `t/43-cli-schedule.t`:**

- Add a test case passing a setting like `distri=opensuse` (instead of `DISTRI=opensuse`) to `openqa-cli schedule`.
- Assert that the resulting API request contains `DISTRI => 'opensuse'` and that the value casing is preserved.

**In `t/43-cli-api.t`:**

- Ensure there is test coverage invoking an arbitrary API endpoint using `openqa-cli api` with a lowercase parameter key and a mixed-case value. Verify the key and value are not modified.

## Quality Assurance

- Run `make tidy` and `make test-checkstyle` before considering changes complete.
- Execute `make test-unit-and-integration TESTS="t/43-cli-schedule.t t/43-cli-api.t t/32-openqa_client.t"` to verify local fixes.
