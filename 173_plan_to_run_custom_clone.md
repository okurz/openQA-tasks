# Plan: Run a custom clone on openqa.suse.de using a PR

## Overview
To run a custom clone of `https://openqa.suse.de/tests/23920815` using the `osado-dev-container` and the changes from `os-autoinst` PR #3081, you can now leverage the improved worker engine containerization (which auto-mounts the host's `share` directory so internal tests and needles resolve successfully without configuring any Git URLs).

## Command
Use `openqa-clone-job` to clone the job directly onto the `openqa.suse.de` instance (`--within-instance`), pointing to the source fork and branch of PR 3081:

```sh
openqa-clone-job --skip-chained-deps --within-instance https://openqa.suse.de/tests/23920815 \
  _GROUP=0 \
  OS_AUTOINST_GIT_REPO=https://github.com/okurz/os-autoinst.git \
  OS_AUTOINST_GIT_BRANCH=feature/013_pretty_typing_fixes_10_user_feedback \
  OS_AUTOINST_CONTAINER_IMAGE=registry.opensuse.org/devel/openqa/containers/osado-dev-container:latest
```

## Why this works
1. **`OS_AUTOINST_CONTAINER_IMAGE`**: Specifies the `osado-dev-container` which contains all the necessary openSUSE distribution test dependencies (like `os-autoinst-distri-opensuse-deps`).
2. **`OS_AUTOINST_GIT_REPO` & `OS_AUTOINST_GIT_BRANCH`**: Directs the worker to use your fork and feature branch (where PR #3081 originates from) instead of the default `master` branch.
3. **Internal `CASEDIR` and `NEEDLES_DIR`**: Thanks to our latest codebase adjustments, the podman container seamlessly mounts the openQA worker's `/var/lib/openqa/share` directory. Therefore, you do not need to explicitly provide Git URLs to override `CASEDIR` and `NEEDLES_DIR` as previously recommended in the documentation. The internal needles required on `openqa.suse.de` will natively resolve from the worker's shared volume just like they do for non-containerized jobs.

## Note
Ensure the target openQA workers on `openqa.suse.de` are updated with the latest codebase containing the volume mount patch for `isotovideo.pm` before running the clone job.
