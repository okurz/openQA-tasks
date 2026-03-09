# Implementation Plan - Task 38: Mojolicious style function signatures

This plan outlines the steps to convert traditional Perl function signatures to Mojolicious-style signatures across the openQA codebase.

## Objective

Replace traditional parameter handling:

```perl
sub my_method {
    my ($self, $arg1, $arg2) = @_;
    ...
}
```

With Mojolicious-style signatures:

```perl
sub my_method ($self, $arg1, $arg2) {
    ...
}
```

## Proposed Changes

### 1. Identification

Identify all files still using the traditional style. Based on initial research, files like the following (and many others) need updates:

- `lib/OpenQA/Schema/Result/Users.pm`
- `lib/OpenQA/Task/Needle/Save.pm`
- `lib/OpenQA/Schema/Result/Workers.pm`
- ... (approx 92 matches for `my ($self, ...) = @_`)

### 2. Enabling Signatures

Ensure each file being modified has signatures enabled.

- If it uses `Mojo::Base`, ensure `-signatures` is present:
  `use Mojo::Base 'Some::Parent', -signatures;`
- If it doesn't use `Mojo::Base`, add:
  `use Mojo::Base -strict, -signatures;`
  (Never use `use feature 'signatures';`).

### 3. Systematic Conversion

Convert files one by one or in small logical groups (e.g., by package prefix).

#### Conversion steps for a single file:

1.  **Read** the file to identify all subroutines using traditional signatures.
2.  **Update** the `use Mojo::Base` line to include `-signatures` if missing.
3.  **Replace** the subroutine definitions and the initial assignment from `@_`.
    - Handle `my ($self, $arg) = @_;` -> `sub name ($self, $arg)`
    - Handle `my $self = shift;` -> `sub name ($self)`
    - Handle optional arguments: `my $arg = shift // 'default';` -> `sub name ($self, $arg = 'default')`
4.  **Run `make tidy`** to ensure the formatting matches the project's standards (this will also fix indentation/spacing for the new signatures).
5.  **Verify** with `make test-checkstyle`.
6.  **Run tests** relevant to the modified file.

### 4. Verification Plan

For each modified file:

1.  **Syntax check**: `perl -Ilib -c path/to/file.pm`
2.  **Style check**: `make tidy` and `make test-checkstyle`
3.  **Unit tests**: Identify relevant tests using `grep` or by naming convention (e.g., `t/schema/result/users.t` for `lib/OpenQA/Schema/Result/Users.pm`).
    - Run: `make test-unit-and-integration TESTS=t/relevant_test.t`
4.  **Integration tests**: If a major controller or service is changed, run a broader set of tests.

## Risks and Mitigations

- **Arity Enforcement**: Perl signatures enforce the number of arguments. If a caller passes too few/many arguments, it will throw an error.
  - _Mitigation_: Check callsites if unsure, or use optional parameters with defaults (`$arg = undef`) if the previous code handled missing args.
- **`@_` usage**: If the code relies on `@_` for something other than initial assignment (e.g., passing it to another function via `goto &sub` or `SUPER::method(@_)`), signatures might interfere.
  - _Mitigation_: Carefully inspect subroutine bodies for `@_` usage. Mojolicious signatures still allow `@_` but it's better to be explicit.
- **Performance**: Signatures used to be slightly slower than manual unpacking, but in modern Perl versions (especially 5.36+ where they are stable) this is negligible.

## Execution Order

1.  Start with smaller, isolated modules (e.g., `OpenQA::Task::*`).
2.  Move to Schema Result/ResultSet classes.
3.  Move to Controllers and Plugins.
4.  Finally, update any remaining scripts or auxiliary modules.
