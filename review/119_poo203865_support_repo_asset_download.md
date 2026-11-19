# Implementation Plan - Support repo asset download (poo203865)

## Problem Description & Motivation

openQA supports downloading assets prior to job execution when `_URL` job settings are specified (e.g. `ISO_URL`, `HDD_1_URL`, `ASSET_1_URL`). However, repository assets (`REPO_n_URL`, `REPO_URL`) are not yet automatically downloaded/synced. Tests relying on transient OBS/IBS repos suffer from reproducibility issues. Supporting repository downloads via `wget` (for HTTP/HTTPS/FTP) and `rsync` (for `rsync://` URLs) allows openQA to automatically mirror repository assets to `/var/lib/openqa/share/factory/repo`.

## Acceptance Criteria

- **AC1:** Assets specified by `REPO_URL` or `REPO_n_URL` are automatically downloaded/synced by openQA into `/var/lib/openqa/share/factory/repo`.
- **AC2:** `docs/UsersGuide.md` (section "Specifying assets required by a job") clearly documents repository asset download features.

## Proposed Changes

### 1. Asset Type & Download List Recognition (`lib/OpenQA/Utils.pm`)

- Update `asset_type_from_setting` so `REPO` (in addition to `REPO_\d+`) is recognized as a repo asset type.
- In `create_downloads_list`, ensure existence check handles directories (`-d $fullpath` or `-e $fullpath` for `repo` asset type) so existing repos are not unnecessarily re-downloaded, while missing repos are enqueued for download.

### 2. Downloader Implementation (`lib/OpenQA/Downloader.pm`)

- Add repository download support (`_download_repo`) when the asset type is `repo` or the target is a repo directory:
  - For `rsync://` URLs: invoke `rsync -avH --delete "$url/" "$tmp_dir/"`.
  - For `http://`, `https://`, or `ftp://` URLs: calculate `--cut-dirs` from URL path parts and invoke `wget -m -np -nH --cut-dirs=$cut_dirs --reject "index.html*" -P "$tmp_dir" "$url"`.
  - Perform download into a temporary directory inside the asset directory (e.g. `.tmp_<name>_<pid>`) and atomically rename to `$target` on success.
  - On failure, clean up temporary directory and return descriptive error message.

### 3. Task Permissions & Symlink Handling (`lib/OpenQA/Task/Asset/Download.pm`)

- Ensure that for downloaded repo directories, permissions are set to `0755` instead of `0644` (which would strip execution/search bit from directories).

### 4. Documentation (`docs/UsersGuide.md`)

- Update section "Specifying assets required by a job" to document `REPO` / `REPO_n` and `REPO_URL` / `REPO_n_URL` behavior, including HTTP/HTTPS mirroring with `wget` and rsync mirroring with `rsync`.

### 5. Test Suite Adaptations & New Tests

- `t/16-utils.t`: Test `asset_type_from_setting`, `parse_assets_from_settings`, and `create_downloads_list` with `REPO` and `REPO_1_URL`.
- `t/25-downloader.t`: Add tests for repo download via `_download_repo` / `download` covering HTTP mirroring and error conditions.
- `t/api/02-iso-download.t`: Add integration tests for scheduling jobs with `REPO_1_URL` and `REPO_URL`.

## Verification Steps

1. `make tidy`
2. `make test-checkstyle`
3. `make test-unit-and-integration TESTS="t/16-utils.t t/25-downloader.t t/api/02-iso-download.t"`
4. `COVERAGE=1 make test-unit-and-integration TESTS="t/16-utils.t t/25-downloader.t t/api/02-iso-download.t"`
5. `make check-line-coverage`
6. `cover -report text -select_re 'lib/OpenQA/(Utils|Downloader|Task/Asset/Download)\.pm'`
7. Commit following Commit Discipline and run `make test-gitlint`.
