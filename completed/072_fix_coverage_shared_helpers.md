# Task 072: Fix code coverage in lib/OpenQA/Shared/Plugin/SharedHelpers.pm

Codecov reports line 61 in `lib/OpenQA/Shared/Plugin/SharedHelpers.pm` as uncovered. This line sets `$id = 'admin'` if the authentication method is 'None' and it's not an API request. Combining the condition into the `if` statement will simplify the logic and potentially solve the coverage issue by reducing the number of branches.

## Motivation

Improve code coverage and simplify authentication logic.

## Design Choices

Combine the `unless $c->is_api_request` check into the parent `if` condition.

```perl
<<<<
        if (!$id && $auth_method eq 'None') {
            # Avoid auto-login as admin for requests with API credentials.
            # Otherwise, the 'auth' method would reject the request due to a
            # missing CSRF token before it even checks the API credentials.
            $id = 'admin' unless $c->is_api_request;
        }
====
        if (!$id && $auth_method eq 'None' && !$c->is_api_request) {
            # Avoid auto-login as admin for requests with API credentials.
            # Otherwise, the 'auth' method would reject the request due to a
            # missing CSRF token before it even checks the API credentials.
            $id = 'admin';
        }
>>>>
```

## Verification

- Run `make test-unit-and-integration TESTS=t/03-auth.t` to ensure authentication still works as expected.
- Run `make tidy` and `make test-checkstyle`.
- If possible, verify coverage locally (though not strictly required if tests pass and logic is correct).
