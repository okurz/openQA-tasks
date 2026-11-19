# 135 — Run custom os-autoinst engine on already-containerized o3 IPMI worker

Refs: progress.opensuse.org/issues/204510 (SSH serial disconnect on bare-metal
reboot, os-autoinst fork commits `cbd305d73`, `5cc73a4e2`). Docs:
`docs/WritingTests.md` "Running a custom worker engine".

## 1. Problem analysis — why nested podman fails

- `lib/OpenQA/Worker/Engines/isotovideo.pm` `_construct_isotovideo_cmd` (~line 535)
  wraps the custom engine in `env ... podman ... run ... <image> sh -c 'git clone
  && make -C os-autoinst && os-autoinst/isotovideo -d'` when `OS_AUTOINST_GIT_REPO`
  is set (~line 545-598). Otherwise it runs `perl isotovideo -d` (~line 601).
- Call site: `_engine_workit_step_2` `exec _construct_isotovideo_cmd(...)` (~line 491),
  wrapped in `container(... process => $child ...)` (~line 505) for cgroup cleanup.
- o3 IPMI worker `openqaworker23_container_201:201` is itself a podman container.
  No `podman` binary exists inside it.
- `env` cannot find `podman` → `env: 'podman': No such file or directory` →
  child exits 127 → `$job->stop(WORKER_SR_DIED)` (~line 497). The `die "exec failed"`
  at ~line 492 is not reached, because `env` itself starts fine.
- Nothing in `lib/`, `container/worker/`, or `dist/` detects "worker runs in a
  container". No knob exists for it. The official worker image
  (`container/worker/Dockerfile`) has no podman either, so this is not o3-only.

## 2. Options

Existing levers, no new code:

- **Option 0 — `ISOTOVIDEO` job setting** (`_construct_isotovideo_cmd` first branch,
  ~line 536). Pass `sh -c 'git clone ... && make -C os-autoinst && os-autoinst/isotovideo -d'`
  directly. Works today if the worker has the toolchain. Cons: duplicates the
  clone/build script in every job; bypasses the `OS_AUTOINST_*` contract. Use as a
  bridge only.
- **Option B — prebuilt engine path**. Worker CLI `--isotovideo <path>` already exists
  (`set_engine_exec`, `lib/OpenQA/Worker.pm:98`). Build the fork outside, make the
  tree visible inside the worker container, point the worker at it. Cons: static per
  worker, not per job; manual rebuilds; the version check in `set_engine_exec` only
  covers that path, not later job-specific builds.

New code:

- **Option A — native runtime knob (recommended)**. Worker setting
  `CUSTOM_ENGINE_RUNTIME=podman|native` (default `podman`, unchanged behavior).
  With `native`, `_construct_isotovideo_cmd` returns the same
  `git clone && make && isotovideo -d` script as `('sh', '-c', $script)` and skips
  podman. The job-level feature UX stays. Cons: the worker image needs `git`, `make`,
  cmake/gcc (not in `container/worker/Dockerfile` today); `OS_AUTOINST_CONTAINER_IMAGE`
  is ignored, so it must die when set together with `native`.
- **Option C — auto-detect container** (`/run/.containerenv` or `/.dockerenv`) and
  default to native. Cons: silent behavior change for every containerized worker;
  image setting silently ignored; brittle detection. Defer until A is proven.
- **Option D — spawn sibling container via host podman socket**. Rejected:
  exposes the host container runtime to the worker container (privilege escalation).

**Recommendation: Option A.** Explicit, auditable, default-off, keeps the job
interface. The toolchain cost is the main trade-off; check it on the reserved
instance first (§5, step 1). Use Option 0 only to bridge verification if A is not
ready.

## 3. Code change sketch (Option A)

Function-level only:

- `lib/OpenQA/Worker/Engines/isotovideo.pm`
  - Extract `_custom_engine_script($repo, $branch)` returning the
    `git clone --branch=... --depth=1 ... && make -C os-autoinst && os-autoinst/isotovideo -d`
    string. Used by both runtimes (removes the inline string at ~line 596).
  - `_construct_isotovideo_cmd($job_settings, $isotovideo, $worker_settings = {})`:
    - keep branch (a) `ISOTOVIDEO` and the `OS_AUTOINST_CONTAINER_IMAGE` check as-is;
    - if `native` and `OS_AUTOINST_CONTAINER_IMAGE` set: die with a clear message;
    - if `native`: return `('sh', '-c', _custom_engine_script(...))`;
    - else: existing podman branch, unchanged.
  - `_engine_workit_step_2`: pass `$worker->settings->global_settings` as third
    argument (same access pattern as `lib/OpenQA/Worker.pm:474`). No global state.
- `lib/OpenQA/Worker/Settings.pm`: default `CUSTOM_ENGINE_RUNTIME = 'podman'`.
- `etc/openqa/workers.ini`: commented key. `docs/Installing.md` and
  `docs/WritingTests.md`: one paragraph each.

Cgroup and container handling stay untouched. `container(clean_cgroup => 1, process => $child)`
still wraps the `sh` process group (`kill_whole_group => 1`). Native mode skips the
podman boot-ID runroot logic (~line 553-563) and the podman cache dirs.

## 4. Atomic tasks (one commit each)

Commit style: `type(scope): Summary` (cf. repo history).

1. **Preflight, no commit** — §5 step 1 on `openqaworker23_container_201:201`.
2. **Refactor script builder** — extract `_custom_engine_script`; existing
   `t/24-worker-engine.t` `_construct_isotovideo_cmd` subtests must pass unchanged.
   `refactor(worker): Extract custom engine script from podman command`
3. **Native runtime** — knob, native branch, die on image, call-site argument.
   `feat(worker): Allow custom engine without nested podman`
4. **Tests** — data-driven subtests in `t/24-worker-engine.t`:
   - `native` returns `('sh', '-c', $script)` with the branch and repo in the script;
   - `native` plus `OS_AUTOINST_CONTAINER_IMAGE` dies;
   - default (`podman`) output identical to today (existing index-based assertions);
   - `ISOTOVIDEO` still wins over both.
   `test(worker): Cover native custom engine runtime`
5. **Docs** — `workers.ini`, `Installing.md`, `WritingTests.md` (native requires
   `git`, `make`, cmake/gcc in the worker environment).
   `docs(worker): Document CUSTOM_ENGINE_RUNTIME for containerized workers`
6. **Follow-up (separate, later)** — Option C detection, only after A is proven on
   production-like hardware.

## 5. Verification

Step 1 — preflight on `openqaworker23_container_201:201` (read-only):

- `command -v git make cmake g++ perl` inside the container. Missing tools → either
  install in this reserved instance only, or fall back to Option 0/B.
- Cgroup write permission for `_configure_cgroupv2`. Failure is a warning only
  (`Disabling cgroup usage ...`), not a job failure.
- `IPMI_AUTOSHUTDOWN_INTERVAL` / `IPMI_*` on this worker must not trigger shutdowns
  of the SUT during tests (`lib/OpenQA/Worker.pm:400-403`).
- The IPMI SUT behind 201 must be reserved so production workers do not touch it.

Step 2 — local engine run against the same remote IPMI host:

- Build the fork checkout (`/home/okurz/local/os-autoinst/os-autoinst`, commit
  `5cc73a4e2`) with `make`.
- Create a pool dir with `vars.json` for `BACKEND=ipmi` pointing at the reserved
  SUT (copy from a real o3 ipmi job's `vars.json`, do not hand-write).
- Run `perl <fork>/isotovideo -d` in the pool dir. Trigger a reboot in the test
  flow (e.g. `reboot` or `system_reset` via IPMI).

Expected result (bare-metal ipmi, fork `5cc73a4e2`):

- `autoinst-log.txt` shows the SSH serial disconnect and a graceful reconnect.
- No `check_ssh_serial` die. No `incomplete` result caused by the disconnect.
- Final result comes from the test modules, not from the backend.

Negative control: remote-hypervisor backends (svirt/s390x) keep the fatal path and
end as `incomplete`. Run only if a hypervisor is reachable; otherwise rely on the
os-autoinst unit tests for `check_ssh_serial` (verify they exist in the fork).

Step 3 — openQA end-to-end on the reserved worker only:

- Job settings: `OS_AUTOINST_GIT_REPO=<fork>`, `OS_AUTOINST_GIT_BRANCH=<branch>`,
  `CUSTOM_ENGINE_RUNTIME=native` (after task 3 lands). Target
  `WORKER_CLASS` of the reserved instance only.
- Expect: the job runs. No `env: 'podman': No such file or directory`, no exit 127.

Repo checks before claiming done (AGENTS.md):

- `make tidy-perl`
- `make test-perl-testsuite TESTS="xt/01-style.t xt/02-perlcritic.t"`
- `make test-perl-testsuite TESTS="t/24-worker-engine.t"`

## 6. Risks and caveats

- **Dependency skew**: the fork may need Perl modules or os-autoinst-common versions
  the worker image does not ship. Symptom: `Can't locate ...` → exit != 0 →
  `WORKER_SR_DIED`. Mitigation: check the fork's deps against the container
  (`os-autoinst-deps`), install only in the reserved instance.
- **Engine version not checked**: `set_engine_exec` checks only the path given to
  `--isotovideo` at worker start. A cloned fork's `interface v<N>` is never checked.
  Consider a check after `make` in native mode (follow-up).
- **Toolchain in prod image**: adding `git`/`make`/cmake/gcc to the worker image
  increases its size and attack surface. Prefer a separate test image or the
  reserved instance only.
- **Cgroup and process cleanup**: `sh -c` with `&&` leaves an extra shell process in
  the group. `kill_whole_group` should cover it. Verify no orphaned `qemu`/`isotovideo`
  after a stopped job.
- **Production safety**: the reserved instance and the IPMI SUT must not run
  production jobs during verification. Re-check the reservation before each run.
  The local run from §5 step 2 reboots hardware.
- **Scope**: this plan does not change the os-autoinst fork itself; it only enables
  running it. The fix PR stays blocked until §5 step 2 passes.
