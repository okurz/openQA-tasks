# 066 Auth None Implementation

Implement a "None" authentication provider that automatically treats all users as admin without requiring explicit login.

## Motivation

Support openQA instances without any authentication requirements, specifically for simplified local setups or private instances.

## Design Choices

1.  **Create `lib/OpenQA/WebAPI/Auth/None.pm`**: This module will provide the necessary interface for the authentication system, even if most logic is handled automatically.
2.  **Hook into `_current_user` in `lib/OpenQA/Shared/Plugin/SharedHelpers.pm`**: This is the central point for user identification. If the auth method is "None", it will automatically identify as a default 'admin' user.
3.  **Ensure 'admin' user exists**: The 'admin' user will be created in the database with administrative privileges if it doesn't already exist.

## Plan

1.  Create `lib/OpenQA/WebAPI/Auth/None.pm` with basic `auth_login` and `auth_logout` methods.
2.  Modify `lib/OpenQA/Shared/Plugin/SharedHelpers.pm` to automatically return an admin user when the "None" authentication method is active.
3.  Update `t/03-auth.t` to verify that:
    - The app starts correctly with `method = None`.
    - A user is automatically logged in as admin without calling `/login`.
    - Administrative actions (like accessing `/admin/users`) are allowed.
4.  Run `make tidy` and tests to verify.
