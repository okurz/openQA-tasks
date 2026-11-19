# 140 openqa-bootstrap: configurable openQA repositories

Ticket: https://progress.opensuse.org/issues/206340
Branch: `feature/140_openqa_bootstrap_configurable_repos` (base `origin/master`
7ce265bc6)
Numbering: 138 and 139 are taken by `tasks/review/138_poo167749_no_global_selenium_implicit_wait.md`
and `tasks/review/139_obs_pr_recovery_script.md`, so this plan continues with
140 (max prefix in `tasks/` + 1, see `tasks/Readme.md`).
Status: implemented, 5 commits, all checks green. See "Implemented commits".

## Problem

`openQA-bootstrap` is the documented quick way to set up openQA
(`docs/Installing.md` "Quick bootstrapping under openSUSE") and is the
installation method of the `openqa_from_bootstrap` scenario in the
openQA-in-openQA test distribution
(`os-autoinst-distri-openQA/main.pm:26`,
`tests/install/openqa_webui.pm:90-93`). Testing a fork of openQA — e.g. a
fixed snapshot in a project like `devel:openQA:GitHub` or a personal home
project — was not possible with that script because the repository setup is
hardcoded:

1. `script/openqa-bootstrap` added repos only for openSUSE Leap and only for
   the official project. The `grep` in the old code compared against the
   hardcoded URL base, so a repository the caller pre-added for a fork project
   never suppressed these additions. On Leap the official
   `devel:openQA:Leap:$version` repository (prio 90) outranks a caller's
   repository (prio 95), so packages of a fork are effectively overridden.
2. Everything the script installs afterwards (`retry`,
   `openQA-single-instance[-nginx]`, `qemu-*`,
   `os-autoinst-distri-opensuse-deps`) resolves from all enabled repositories,
   so packages missing from a fork project silently come from the
   distribution. openQA is published in openSUSE:Factory
   (`https://api.opensuse.org/public/build/openSUSE:Factory/standard/x86_64/openQA`
   lists `openQA-bootstrap-*.rpm`, `openQA-single-instance-*.rpm`), so the
   fallback also applies on Tumbleweed.
3. The repository URL used the redirector `download.opensuse.org`. The test
   distribution switched to `downloadcontent.opensuse.org` in
   os-autoinst-distri-openQA commit 7562421 (poo#178642) because transient
   repository content breaks package fetches; the bootstrap script reintroduced
   the redirector on Leap.
4. `script/openqa-continuous-update` defaulted `DEVEL_OPENQA_REPOSITORY` to the
   alias `devel_openQA` while `openqa-bootstrap` added the alias
   `devel:openQA`, so `zypper ref -r "$repo_name"` fails on a system installed
   with `openqa-bootstrap`.
5. `script/openqa-bootstrap-container` hardcoded the Tumbleweed OSS repository
   (`DEFAULT_REPO`) and installed `openQA-single-instance` and
   `openQA-bootstrap` from it, so the container path had no repository
   configuration at all.

Precedent for configurable repositories exists in the same repository:
`script/openqa-check-devel-repo` (`REPO_URL`) and
`script/openqa-continuous-update` (`DEVEL_OPENQA_REPOSITORY`).

## Design

Repository configuration is passed to `openqa-bootstrap` as environment
variables, in the style of the existing `OPENQA_DIR`, `skip_suse_specifics`,
`setup_web_proxy`, `dbname`, `dbuser` knobs. The names match the test
variables of `os-autoinst-distri-openQA` (documented in its `README.md`) so the
test can forward them.

| Variable                        | Default                                             | Purpose                                                           |
| ------------------------------- | --------------------------------------------------- | ----------------------------------------------------------------- |
| `OPENQA_OBS_PROJECT`            | `devel:openQA`                                      | OBS project to install from                                       |
| `OPENQA_REPO_URL`               | computed from project + distro repository           | full repository URL, overrides the computed URL                   |
| `OPENQA_LEAP_REPO_URL`          | computed, official project only                     | companion repository with Leap packages; empty string disables it |
| `OPENQA_REPO_BASE`              | `https://downloadcontent.opensuse.org/repositories` | base URL for the computed URL                                     |
| `OPENQA_ADD_REPOS`              | `1`                                                 | `0` skips all repository additions                                |
| `OS_RELEASE`                    | `/etc/os-release`                                   | hook for the sourced os-release file (test)                       |
| `OPENQA_ADD_REPOS_ONLY`         | unset                                               | hook to exit after the repository setup (test)                    |
| `CONTAINER_PATH`, `SYSTEMD_DIR` | real paths                                          | hooks so the container test writes to a temporary directory       |

Decisions and their rationale:

- **`script/openqa-repo-url` helper** prints `URL alias` for the configured
  project and the current distribution. Both bootstrap scripts consume it, so
  the URL, project, alias and distribution repository name are computed in one
  place. A sourced shell library was rejected: `t/44-scripts.t` runs every
  shell script in `script/` with `--help` and an invalid command, which a
  library cannot satisfy, and packaging is explicit per script file. The helper
  satisfies both contracts and is packaged in the `openQA-bootstrap`
  subpackage.
- **Defaults do not change behaviour** for existing users: on Leap the same
  repositories, aliases and priorities as before, on Tumbleweed nothing
  (openQA ships in the Tumbleweed main repository, so a repository is opt-in
  via `OPENQA_REPO_URL`/`OPENQA_OBS_PROJECT`).
- **Repo alias = project name** so a fork is not labelled `devel:openQA`; for an
  explicit `OPENQA_REPO_URL` the project is taken from the URL path. The
  companion repository is only added for the official project.
- **Idempotency** via `zypper lr -d | grep -qF "$url"` so a pre-configured URL
  is not added twice.
- **Retries** around `addrepo` + `ref` with `-f`, matching
  `docs/Installing.md` and the `retry` wrapper the test distribution uses.
  `retry` is installed before the repository setup so the wrapper is available.
- **Aliases pinned for `openqa-continuous-update`** which now defaults to the
  alias the bootstrap script adds. `openqa-auto-update`'s cache glob
  (`OPENQA_PACKAGE_CACHE_REPO_GLOB`) matches URL path components, not aliases,
  so it is unaffected.
- **Tests** use stub `zypper`, `retry`, `curl`, `systemd-run`, `systemctl` and
  `timeout` recording their arguments, os-release fixtures for Leap 16.0,
  Tumbleweed and Fedora, and `unshare -r -n` to block network access, in the
  spirit of `t/40-script_openqa-clone-custom-git-refspec.t`. The stub log
  records calls that are swallowed by command substitution, and the test
  redirects command output to `/dev/null` so `tools/prove_wrapper` sees no
  unhandled output.
- **Coverage**: `Devel::Cover` does not instrument shell code, so coverage of
  the shell changes comes from the new test files. `COVERAGE=1
COVERDB_SUFFIX=_140 make test-unit-and-integration TESTS="…new tests"` passes
  and `cover … -report codecovbash` reports no uncovered line in the new test
  files.

Out of scope, follow-up plans:

- Parameterising `container/{webui,worker}/Dockerfile` (hardcoded
  `devel:openQA/16.0`). `container/single-instance` needs no change, it already
  runs `openqa-bootstrap` as entrypoint and accepts the variables via `ENV`.
- Consumer-side changes in `os-autoinst-distri-openQA`, see "Cross-repo
  hand-off".
- Repository setup for SLE (SUSE:CA logic in `openqa-bootstrap`).

## Implemented commits

Order matters; each commit passes `make test-shellcheck`, `make test-shfmt`,
`make test-markdown`, `make test-gitlint`, `xt/00-tidy.t`, `xt/01-style.t`,
`xt/02-perlcritic.t` and `xt/02-pod.t` and its tests.

1. `6d4c82948 refactor(bootstrap): extract repo setup into add-repos`
   `script/openqa-bootstrap`: repository block as a function, `OS_RELEASE` and
   `OPENQA_ADD_REPOS_ONLY` hooks, `downloadcontent.opensuse.org`, knobs in
   `--help`.
2. `26f22e4c1 feat(bootstrap): compute repo URL in openqa-repo-url helper`
   new `script/openqa-repo-url`, opt-in repository in
   `script/openqa-bootstrap-container`, `t/44-scripts-openqa-repo-url.t`,
   `t/44-scripts-openqa-bootstrap.t`, `t/44-scripts-openqa-bootstrap-container.t`
   and the stubs `zypper`, `retry`, `curl`, `systemd-run`, `systemctl`,
   `timeout`, `uname` plus the os-release fixtures.
3. `3600467da docs(bootstrap): document configurable openQA repositories`
   `docs/Installing.md`, `downloadcontent.opensuse.org` in the Dockerfiles,
   `dist/rpm/openQA.spec` `%files bootstrap`.
4. `3502af0df fix(continuous-update): make the OBS project configurable`
   `script/openqa-continuous-update` derives the refreshed alias from
   `OPENQA_OBS_PROJECT`, `script/openqa-check-devel-repo` reads the same
   setting, `t/44-scripts-continuous-update.t` pins alias and project.
5. `421c25eba refactor(bootstrap): reuse openqa-repo-url in add-repos`
   `add-repos` consumes the helper, long zypper options, test-only hooks
   dropped from `--help`, test expectations adapted.

## Verification

- `make test-shellcheck`, `make test-shfmt`, `make test-markdown`,
  `make test-yaml`, `make test-gitlint`: pass.
- `prove t/44-scripts-openqa-bootstrap.t t/44-scripts-openqa-bootstrap-container.t
t/44-scripts-openqa-repo-url.t t/44-scripts-continuous-update.t`: 44
  assertions pass.
- `HEAVY=1 prove t/44-scripts.t`: 94 assertions pass, covering the `--help`
  and invalid-argument contract of the new helper script.
- `xt/00-tidy.t`, `xt/01-style.t`, `xt/02-perlcritic.t`, `xt/02-pod.t`: pass.
- `COVERAGE=1 COVERDB_SUFFIX=_140 make test-unit-and-integration TESTS="…"`:
  pass, `tools/prove_wrapper` reports no unhandled output; the codecov report
  for that cover_db lists no uncovered line in the new test files.

## Cross-repo hand-off (`os-autoinst-distri-openQA`)

Consumer change in `os-autoinst-distri-openQA/tests/install/openqa_webui.pm`,
depends on commits 3-4 being merged:

1. `install_from_bootstrap` (line 90-93) passes the configuration:
   `OPENQA_OBS_PROJECT`/`OPENQA_REPO_URL` and `setup_web_proxy` from
   `OPENQA_WEB_PROXY`, and returns the URL added by `add_repo`.
2. `add_repo` (line 6-20) drops the Tumbleweed-only `die`; for Leap it can
   delegate the repository addition to `openqa-bootstrap` via the new
   variables, which is the smaller change.
3. Provenance assertion so a silent fallback to the distribution repository
   fails the test:

   ```perl
   my $expected = script_output "zypper -n -i info -t package -r $repo_alias openQA-bootstrap | awk -F ': ' '/^Version/{print \$2}'";
   assert_script_run "test \$(rpm -q --qf '%{VERSION}' openQA-bootstrap) = '$expected'",
       fail_message => 'openQA-bootstrap must come from the configured repo';
   ```

4. `get_log 'zypper lr -d' => 'zypper-lr.txt'` in `post_fail_hook`
   (line 116-123) for repository diagnosis from job logs.
5. Acceptance check for the whole plan: clone the existing
   `openqa_from_bootstrap` job with `OPENQA_OBS_PROJECT=<fork project>` and
   confirm the installed `openQA-bootstrap` version matches the project build,
   i.e. the assertion in point 3 passes.

Ordering: the openQA side is merged first. Extra environment variables are
ignored by an older `openqa-bootstrap`, so the test-side change is safe
afterwards; the reverse order would leave forks on Leap installing from
`devel:openQA`.
