# Fix podman cache directory creation for os-autoinst worker engine

## Motivation
The feature introduced in `d14bdddd9` and later refactored in `d584d95a6` removed the shell `mkdir -p` command that ensured the podman cache directory existed. This leads to failures when using `OS_AUTOINST_GIT_REPO` on systems where `/var/lib/openqa/cache/podman` does not exist:
`cannot resolve /var/lib/openqa/cache/podman: lstat /var/lib/openqa/cache/podman: no such file or directory`

## Design Choices
1. **Code:** Add `path($podman_dir)->make_path;` in `lib/OpenQA/Worker/Engines/isotovideo.pm` before running podman. This ensures the directory is created for local checkouts and developments.
2. **Packaging:** Add `%dir %{_localstatedir}/lib/openqa/cache/podman` to `dist/rpm/openQA.spec` to ensure the directory is created by the RPM package natively, which also sidesteps any potential AppArmor limitations if `w` on the parent dir was strictly necessary.
3. **Tests:** Ensure `t/24-worker-engine.t` verifies the directory creation or simply doesn't fail when the code is executed.

## Steps
1. Modify `lib/OpenQA/Worker/Engines/isotovideo.pm` to use `Mojo::File::path($podman_dir)->make_path;`.
2. Modify `dist/rpm/openQA.spec` to list `%dir %{_localstatedir}/lib/openqa/cache/podman`.
3. Run `make tidy`, `make test-checkstyle`, and `make test-unit-and-integration TESTS=t/24-worker-engine.t`.
