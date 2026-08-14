# 101 — Proxy VNC and SSH access to SUTs through the openQA webUI

## Problem statement

Test developers want to reach the remote VNC port and/or SSH of openQA SUTs.
Today the webUI interactive/live mode only shows a _hint_ (e.g.
`vncviewer host:port -Shared`) that requires direct network access to the
worker host. Such direct access is frequently blocked by network/firewall
separation and is a security concern. Operators and admins should instead be
able to remote-control VNC and SSH of running SUTs **from within the webUI**,
which proxies the traffic reliably, conveniently, and securely.

## Confirmed design decisions

- **In-browser clients only.** VNC is rendered in the browser via noVNC; SSH via
  a web terminal (xterm.js). No "connect with your own local client" tunnel
  variant.
- **VNC path:** browser <-ws-> webUI-host proxy <-TCP-> SUT VNC on the worker
  host (port from existing `vnc_argument` math). Reuses worker-host VNC data.
- **SSH path (phase 1):** browser <-ws-> webUI-host proxy <-SSH-> **directly to
  the SUT** (SUT IP/port resolved from job/worker data). Independent of
  os-autoinst. Phase 2 (later extension): SSH via the worker host that forwards
  to the SUT, for environments where the SUT is not directly reachable from the
  webUI host.
- **Proxy process model:** a **dedicated, per-connection ephemeral process**
  spawned by the livehandler on user action (button click), torn down on
  disconnect or job end.
- **Authorization:** `operator` role, mirroring existing live/developer routes.
- **Frontend dependencies (noVNC, xterm.js):** added **through vite**, sequenced
  **after** the assetpack->vite migration (tasks 100 / 044). This plan's
  frontend tasks depend on that migration landing.
- **Security envelope:** the proxy may only reach the specific host:port of the
  worker/SUT for the specific `RUNNING` job the operator is authorized for;
  connections use job-scoped, time-limited tokens and are force-closed on job
  end.

## Current state (references)

- VNC hint UI: `templates/webapi/test/live.html.ep:48-50`
  (`#developer-vnc-notice`), driven by `assets/javascripts/running.js:1223-1233`
  and `updateDeveloperPanel()` at `running.js:639`.
- VNC target computation: `lib/OpenQA/Schema/Result/Workers.pm:253-257`
  (`vnc_argument` = `host:(instance+VNC_PORT)`), `VNC_PORT` from
  `lib/OpenQA/Constants.pm:115-116` (`VNCPORT_OFFSET=90`, base 5900).
- Existing websocket proxy pattern (JSON command relay; structural template
  only, it is NOT a byte-stream proxy):
  `lib/OpenQA/LiveHandler/Controller/LiveViewHandler.pm`
  (`ws_proxy` 439-511, `connect_to_cmd_srv` 328-373, allowlist 19-28).
- Livehandler daemon + routing: `lib/OpenQA/LiveHandler.pm:44-63`
  (routes guarded by `Session#ensure_operator` / `Auth#auth_operator`).
- Job/worker connection params: `lib/OpenQA/Shared/Plugin/SharedHelpers.pm:29-45`
  (`_determine_connection_params_for_job`); worker properties
  `JOBTOKEN` / `WORKER_HOSTNAME` in
  `lib/OpenQA/Schema/Result/Workers.pm:84-115`.
- Authorization helpers/guards: `SharedHelpers.pm:21-22,73-81`,
  `lib/OpenQA/Shared/Controller/Session.pm:27-45`,
  `lib/OpenQA/Shared/Controller/Auth.pm:119-133`.
- Tests: `t/34-developer_mode-unit.t` (proxy unit),
  `t/33-developer_mode.t` (full stack), `t/ui/25-developer_mode.t` (JS UI),
  `t/38-workers-table.t:125-130` (`vnc_argument`).

## Open items to resolve during Task 0

- SSH target resolution: how the SUT IP/port is derived from job/worker data for
  the phase-1 "direct to SUT" path, and how that is recorded/available in the
  webUI DB.
- SSH authentication toward the SUT (credentials/keys the proxy uses) and how
  that is provisioned securely without exposing secrets to the browser.
- Process spawn/teardown mechanism from the livehandler (Minion job vs. direct
  fork/exec of a dedicated proxy binary) and port allocation for the spawned
  process.

## Atomic tasks

Each task is independently implementable, testable, and committable.

### Task 0 — Design decision record (docs only)

- Short design doc under `docs/` capturing: the two data paths (VNC, SSH
  phase 1), the ephemeral-per-connection process model and its spawn/teardown
  from the livehandler, port allocation, the security model (operator-gated,
  job-scoped, time-limited tokens), SSH-to-SUT resolution and credential
  handling, and the planned phase-2 worker-host SSH forwarding extension.
- Tests: none (documentation). Doc build + `make tidy` must pass.
- Depends on: nothing. Blocks all following tasks.

### Task 1 — Backend: job-scoped SUT connection target resolver

- Add a shared helper returning validated targets for a job + authenticated
  operator: the VNC target (host, port; reuse `vnc_argument`
  `Workers.pm:253-257` and centralize port math from `Constants.pm:115-116`),
  and the SSH-to-SUT target (per Task 0). Extend
  `_determine_connection_params_for_job` (`SharedHelpers.pm:29-45`).
- Enforce: job `RUNNING`, worker assigned, caller authorized.
- Tests: unit tests (extend `t/38-workers-table.t` style + new resolver unit
  test) covering running/not-running, missing worker, missing data, and correct
  VNC/SSH endpoints.
- Depends on: Task 0.

### Task 2 — Backend: dedicated ephemeral proxy process (transport core)

- Implement the standalone per-connection proxy process: a websocket<->TCP
  bridge that connects outbound to a resolved target and relays binary frames.
  Structurally informed by `LiveViewHandler.pm:328-373` but for raw byte
  streams. Include port allocation and clean teardown on disconnect.
- No routing yet; this is the reusable transport building block plus its
  spawn/teardown contract.
- Tests: unit test using a fake TCP echo server asserting bidirectional binary
  relay, teardown on client/server close, and refusal of unresolved targets.
- Depends on: Task 1.

### Task 3 — Backend: livehandler spawn + VNC proxy route

- Add the livehandler route that, on operator action, resolves the VNC target
  (Task 1), spawns the ephemeral proxy (Task 2), and returns the browser-facing
  websocket endpoint. Force-close on job end (analogous to `running.js:438`).
- Gate with `ensure_operator` (mirror `LiveHandler.pm:52`); enforce the security
  envelope (target restricted to the resolved job/worker endpoint;
  job-scoped token).
- Tests: proxy unit test (spirit of `t/34-developer_mode-unit.t`) with a fake
  RFB server: end-to-end relay, auth rejection for non-operators, rejection of
  non-running/unauthorized jobs, teardown on job end.
- Depends on: Tasks 1, 2.

### Task 4 — Backend: SSH proxy route (phase 1, direct-to-SUT)

- Add the livehandler route spawning an ephemeral proxy that opens an SSH
  connection directly to the SUT (Task 0 resolution + credentials) and bridges
  it to a browser websocket for the web terminal. Reuse transport (Task 2) and
  spawn/security machinery (Task 3).
- Gate identically to Task 3.
- Tests: proxy unit test with a fake SSH-banner server: byte relay, auth,
  job-scope enforcement, credential handling not leaked to the browser.
- Depends on: Tasks 1, 2, 3.

### Task 5 — Frontend: in-browser VNC (noVNC) in live/developer view

- Replace/augment the static VNC hint
  (`live.html.ep:48-50`) with a control to open the proxied VNC session rendered
  in-browser via noVNC. Wire through `running.js` (panel setup 566-619,
  visibility 639-646, VNC-arg handling 1223-1233). noVNC added via vite.
- Tests: extend `t/ui/25-developer_mode.t` (JS/DOM) for the control + panel
  wiring; extend `t/33-developer_mode.t` (Selenium) for operator-gated
  visibility/behavior.
- Depends on: Task 3 **and** vite migration (tasks 100 / 044).

### Task 6 — Frontend: in-browser SSH terminal (xterm.js)

- Add a web SSH terminal (xterm.js) in the live/developer view wired to the SSH
  proxy endpoint (Task 4). xterm.js added via vite.
- Tests: extend `t/ui/25-developer_mode.t` for the terminal control/wiring;
  `t/33-developer_mode.t` for operator-gated behavior.
- Depends on: Task 4 **and** vite migration (tasks 100 / 044).

### Task 7 — Documentation and operator guidance

- Document how to use in-browser VNC/SSH access, the required role,
  network/firewall implications, the security model, and the SSH credential
  provisioning. Update interactive-mode hint references.
- Tests: doc build + `make tidy` / `make test-checkstyle` pass.
- Depends on: Tasks 1-6.

### Task 8 (later extension) — SSH phase 2: via worker host to SUT

- Extend the SSH proxy to connect to the worker host and forward to the SUT for
  environments where the SUT is not directly reachable from the webUI host
  (ProxyJump-style). Builds on Task 4 without changing the browser side.
- Tests: extend Task 4's proxy unit test with a two-hop fake path.
- Depends on: Task 4. Independent, deferrable.

## Cross-cutting verification (every code task)

- `make tidy` and `make test-checkstyle` must pass before each commit.
- Run affected tests with `COVERAGE=1 make test-unit-and-integration
TESTS=<file>` and `make check-line-coverage`; full statement coverage for
  new/modified lines is required.
- Conventional Commits; atomic per task; `make test-gitlint` passes.

## Out of scope / follow-ups

- Recording or multi-user sharing of proxied sessions.
- Non-operator (regular user) access.
- SSH via os-autoinst (explicitly not used; SSH is independent of os-autoinst).

Related issue: task 101 in tasks/todo.md
