# 137 poo45671: Developer mode using indirect connections

Ticket: https://progress.opensuse.org/issues/45671
Branch: feature/137_poo45671_developer_mode_using_indirect_connections
Depends on: feature/136_poo45671_improve_developer_mode_hint (commit ceb90002e,
not merged yet). Rebase onto it or merge it first.

## Problem

Developer mode lets an operator interactively control the os-autoinst qemu
instance of a running job. Today the browser connects directly to the worker:

- `Developer.pm` `ws_console` defaults to a direct connection to the
  os-autoinst command server (`ws://<worker>:<port>/<token>/ws`), and only
  `?proxy=1` goes through the web UI.
- The VNC hint (`vnc_argument`, `WORKER_HOSTNAME:5900+instance`) is only usable
  if the user can reach the worker directly.

Workers that are not reachable for users (only the openQA web UI host can
reach them) therefore cannot be controlled. The web UI (LiveHandler) already
reaches the worker for the developer WebSocket and status WebSocket and for the
livestream, so it can act as the relay.

## Current state (verified in code)

- `lib/OpenQA/LiveHandler/Controller/LiveViewHandler.pm`: `ws_proxy` and
  `connect_to_cmd_srv` relay developer commands via the web UI.
- `lib/OpenQA/LiveHandler.pm`: routes `developer/ws-proxy` and
  `developer/ws-proxy/status`.
- `assets/javascripts/running.js`: live page uses the proxied developer route
  for sessions and the status route; livestream goes via LiveHandler port.
- No VNC proxy and no noVNC client exist in the repository.

## Design

- Reachability is a property of the worker host, not of an instance. A host
  runs several worker instances (one `workers` row each, keyed by
  `host` + `instance`, VNC port `5900 + instance`). The flag is therefore set
  per host in `workers.ini`, read by every instance on that host, and sent
  with each instance's registration. The web UI never hands out a direct
  worker URL for such a host.
- The VNC address stays per instance (derived from `vnc_argument`). Only the
  reachability flag is host-wide.
- Command channel: `ws_console` and the live page always use the web UI relay.
- VNC: new WebSocket route in LiveHandler that bridges binary frames to the
  worker's VNC TCP port. Target host/port are taken only from the job's worker
  (never from client input). Access: operator and owner of the developer
  session, same as `developer/ws-proxy`.
- Client access to VNC: in-browser noVNC (the RFB client of the noVNC project,
  MIT licensed, used by Proxmox VE and OpenStack consoles) connects to the
  relay over `wss://`. The browser never talks to the worker. A CLI relay for
  `vncviewer` is an optional follow-up, not part of this plan.
- Relay security baseline: TLS only, Origin check on the WebSocket handshake,
  single-use short-lived ticket in the WebSocket URL (no API key in URLs),
  one VNC client per developer session, idle timeout, audit event
  (`AuditLog` plugin) on connect and disconnect.
- Frontend packaging: `@novnc/novnc` is an npm ES module. Assets are currently
  bundled by assetpack (`assets/assetpack.def`), which handles classic scripts.
  The noVNC console waits for the Vite migration (todo 44).
- Hint: when `DEVELOPER_INDIRECT` is set and no `DEVELOPER_CONNECTION_HINT`
  is configured, show the CLI command instead of the direct VNC address.

Decisions:

1. Flag is per host. The web UI reads it from the worker that runs the job.
2. noVNC is bundled after the Vite migration (todo 44). Task 5 is blocked until
   then. No assetpack workaround.
3. Direct connections stay for reachable hosts. `DEVELOPER_INDIRECT` defaults
   to unset, so existing setups do not change.

## Atomic tasks

Each task is one commit. Keep them in this order.

### 1. Worker property `DEVELOPER_INDIRECT` (per host)

- `lib/OpenQA/Worker.pm` `capabilities`: pass the flag like
  `DEVELOPER_CONNECTION_HINT`, from the instance's merged config so every
  instance on the host reports the same value.
- `lib/OpenQA/WebAPI/Controller/API/V1/Worker.pm` `create`: accept the param.
- `lib/OpenQA/Schema/Result/Workers.pm`: accessor `developer_is_indirect`
  (true only for `1`/`yes`/`true`).
- `etc/openqa/workers.ini`: document the key.
- Tests: `t/38-workers-table.t` (accessor set/unset/invalid),
  `t/api/01-workers.t` (registration stores property), `t/24-worker-overall.t`
  (capabilities).

### 2. Web UI command console uses the relay for indirect workers

- `lib/OpenQA/WebAPI/Controller/Developer.pm` `ws_console`: force `use_proxy`
  when the job's worker is indirect; hide the "connect directly" link in
  `templates/webapi/developer/ws_console.html.ep` in that case.
- Tests: `t/33-developer_mode.t` (indirect forces proxy URL, direct link absent;
  direct worker unchanged).

### 3. Live page never uses direct worker URLs for indirect workers

- `lib/OpenQA/WebAPI/Controller/Test.pm` `live`: stash `developer_is_indirect`.
- `templates/webapi/test/live.html.ep`: `data-developer-indirect` attribute.
- `assets/javascripts/running.js` `setupWebsocketConnection` and
  `initLivestream`: use the web UI relay URL when indirect (no
  `servicePortDelta` based direct URL to the worker).
- Tests: `t/ui/25-developer_mode.t` (attribute rendered; no direct worker URL).

### 4. VNC relay route in LiveHandler (server side)

- `lib/OpenQA/LiveHandler.pm`: websocket route
  `developer/vnc-proxy` under the developer auth chain.
- `lib/OpenQA/LiveHandler/Controller/LiveViewHandler.pm`: new action
  `vnc_proxy`. Resolve host/port from `Workers::vnc_argument` of the job's
  worker; open TCP with `Mojo::IOLoop->client`; relay binary frames both ways;
  close both on either side closing. Reject when no developer session is owned
  by the current user.
- Tests: new `t/35-developer_vnc_proxy.t` with a fake VNC TCP server (RFB
  banner round-trip, forbidden user rejected, worker without VNC rejected).

### 5. In-browser noVNC console (blocked by Vite migration, todo 44)

- Add `@novnc/novnc` to `package.json` and bundle it with Vite. Do not start
  before the Vite migration is merged.
- New `assets/javascripts/developer_vnc.js` (ES6+): creates `RFB` on a
  container in the developer panel, connects to the relay URL, shows a
  connection state, disconnects on session end. No inline script in templates.
- `lib/OpenQA/WebAPI/Controller/Test.pm` / `live.html.ep`: render the VNC panel
  only for accessible indirect workers, with the ticket URL.
- Tests: `t/ui/25-developer_mode.t` (panel rendered only when allowed, no
  direct worker address). JS unit coverage follows the existing ESLint/Prettier
  setup in `make tidy`.

### 6. Hint for indirect workers

- `lib/OpenQA/Shared/Plugin/SharedHelpers.pm`: when indirect and no custom
  hint, the default hint says the console is available in the web UI instead
  of the direct VNC address.
- `running.js` / `live.html.ep`: no change beyond the existing hint path from 136.
- Tests: `t/34-developer_mode-unit.t` (default hint for indirect worker),
  `t/ui/25-developer_mode.t` (rendered text).

### 7. Documentation

- `docs/UsersGuide.md`: developer mode via indirect workers, relay usage.
- `docs/Pitfalls.md`: developer mode checklist entry for indirect workers.
- `etc/openqa/workers.ini`: final wording of `DEVELOPER_INDIRECT`.

## Test adaptations

- Each task above lists its own tests. No task is complete without them.

## Verification (per commit)

```
make tidy
make test-checkstyle
COVERAGE=1 make test-unit-and-integration TESTS="<touched tests>"
make check-line-coverage
make test-gitlint   # when committing
```

Run `cover -report text -select_re '<modified file>'` for each modified Perl
file.

## Security notes

- VNC and command relay must check the developer session owner and operator
  role on every new route.
- Target host and port come only from the job's worker, never from request
  parameters.
- VNC carries full console access to the SUT. Limit to one relay client per
  developer session if feasible (decide in task 4).

## Risks

- The web UI host must reach every indirect worker on the VNC port. Verify
  firewall rules in deployment, same assumption as the existing command relay.
- Relay bandwidth: VNC traffic now passes through the web UI.
- Relay is a plain WebSocket. Use TLS on the web UI for remote users.

## Progress

- [x] Plan saved
- [ ] Task 1: worker property `DEVELOPER_INDIRECT`
- [ ] Task 2: command console uses relay
- [ ] Task 3: live page without direct worker URLs
- [ ] Task 4: VNC relay route in LiveHandler
- [ ] Task 5: in-browser noVNC console (blocked by todo 44)
- [ ] Task 6: hint for indirect workers
- [ ] Task 7: documentation
