# Plan: Apply localhost instead of 127.0.0.1 in startup message

Apply changes consistent with https://github.com/openSUSE/qem-dashboard/commit/c4d679fd5c65dacb84a99b9b7c86e55da02a7db4 to openQA.

## Changes

### 1. lib/OpenQA/Utils.pm
- Update `set_listen_address` to set `$ENV{MOJO_LISTEN}` to `http://localhost:$port?reuse=1` if not already set.
- Remove explicit IPv4/IPv6 loopback handling as `localhost` handles both.

### 2. t/16-utils.t
- Update the 'set listen address' subtest to expect `localhost` instead of `127.0.0.1`.

## Verification
- Run `make tidy` to ensure code style is maintained.
- Run `make test-unit-and-integration TESTS=t/16-utils.t` to verify the changes.
- (Optional) Run a full `make test` if time permits.
