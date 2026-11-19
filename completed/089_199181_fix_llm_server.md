# Plan: Fix and Improve `openqa-llm-server` Container

## Motivation
The `openqa-llm-server` Quadlet currently fails to start because it specifies `User=_openqa-worker` under the `[Container]` section. Podman interprets this as `--user _openqa-worker` and searches for the user inside the container image (`ghcr.io/ggml-org/llama.cpp:server`). Since the user does not exist in the image, Podman exits with an error. Additionally, the container caches Hugging Face model downloads in its ephemeral root filesystem instead of the mounted persistent volume `/opt/llm/models`.

## Proposed Fixes & Improvements

1. **Fix Startup Crash:**
   - **Action:** Remove the `User=_openqa-worker` directive from `container/systemd/openqa-llm-server.container`.
   - **Reasoning:** Since the Quadlet is installed in `/usr/share/containers/systemd/`, it generates a system service that runs Podman as `root` (rootful). Dropping `User=_openqa-worker` prevents the startup failure by running the container internal process as the image's default user (root).

2. **Enhance Security via User Namespaces (Fulfilling intent of `_openqa-worker`):**
   - **Action:** Since the original intent was "rootless container management", but system Quadlets run rootful Podman, we can achieve strong isolation by adding `UserNS=auto` to the `[Container]` section, and updating the volume mount to `Volume=/opt/llm/models:/models:U`.
   - **Reasoning:** `UserNS=auto` maps the container's internal root user to a unique, unprivileged dynamic UID on the host. The `:U` flag in the volume mount automatically adjusts `/opt/llm/models` permissions on the host so the isolated namespace can read and write to it. This provides the desired security without needing a dedicated system user session.

3. **Fix Persistent Model Caching:**
   - **Action:** Add `Environment=HF_HOME=/models` and `Environment=LLAMA_CACHE=/models` under the `[Container]` section.
   - **Reasoning:** The `llama.cpp` server downloads Hugging Face models dynamically using `-hf`. By default, it downloads to `~/.cache/huggingface/` inside the container's ephemeral storage, bypassing the `/opt/llm/models` mount. Setting these variables redirects the download and cache to the persistent volume.

4. **RPM Packaging Polish:**
   - **Action:** Add `%dir /opt/llm` and `%dir /opt/llm/models` to the `%files llm-server` section in `dist/rpm/openQA.spec`.
   - **Reasoning:** Ensures the mount point path is officially owned by the RPM and avoids leaving untracked directories upon uninstallation.

## Execution Steps (To be approved by user)
1. Edit `container/systemd/openqa-llm-server.container`.
2. Edit `dist/rpm/openQA.spec`.
