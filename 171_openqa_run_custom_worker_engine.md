# Plan: Allow running custom worker engines with internal tests

## Motivation
Currently, using a custom worker engine inside a Podman container (`OS_AUTOINST_GIT_REPO`) requires setting `CASEDIR` and `NEEDLES_DIR` to Git URLs because the container starts in a clean environment and cannot resolve symlinks to `/var/lib/openqa/share/...`. This is problematic for testing internal distributions (like SLE on `openqa.suse.de`) where needles are in a private repository that the rootless container cannot clone without credentials. 

## Design Choices
By volume-mounting the openQA worker's share directory (`prjdir() . '/share'`) into the Podman container at the exact same path (read-only), symlinks within the pool directory (like `/pool/opensuse -> /var/lib/openqa/share/tests/opensuse`) will resolve correctly inside the container. This eliminates the need to specify `CASEDIR` and `NEEDLES_DIR` as Git URLs, allowing the container to transparently reuse the host worker's already synced test distribution and needles. We will update `_construct_isotovideo_cmd` in `lib/OpenQA/Worker/Engines/isotovideo.pm` to add `-v $share_dir:$share_dir:ro`. We will also update the documentation to reflect this simplified setup.

## Benefits
Users can run custom worker engines for internal jobs (e.g. `openqa.suse.de/tests/23920815`) simply by specifying `OS_AUTOINST_GIT_REPO` and `OS_AUTOINST_CONTAINER_IMAGE`, without needing complex credential passing for private git repositories or knowing the git URLs for internal tests and needles.
