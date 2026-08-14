# 067 Auth None No Expiration

Modify the "None" authentication provider to set no expiration for the API key+secret instead of the current 10 years.

## Motivation

The "None" authentication provider is intended for simplified local setups where security constraints like API key expiration are not necessary and can be confusing.

## Design Choices

1.  **Modify `lib/OpenQA/WebAPI/Auth/None.pm`**: Explicitly set `t_expiration` to `undef` when updating the API key. This ensures that even if a key already existed with an expiration date, it will be cleared.
2.  **Update `t/03-auth.t`**: Add an assertion to verify that the API key's expiration is indeed `undef`.

## Plan

1.  Read `lib/OpenQA/WebAPI/Auth/None.pm` and `t/03-auth.t` to ensure context.
2.  Modify `lib/OpenQA/WebAPI/Auth/None.pm` to set `t_expiration => undef`.
3.  Modify `t/03-auth.t` to check for `is $key->t_expiration, undef`.
4.  Run `make tidy` to ensure code style.
5.  Run `make test-unit-and-integration TESTS=t/03-auth.t` to verify the change.
6.  Run `make test-checkstyle` to ensure no style regressions.
