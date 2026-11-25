# 218 Recover o3: docker.service fails to start, anubis down

Ticket: https://progress.opensuse.org/issues/209244 (o3 yields 502, docker
service failed so anubis can't start)
Machine: ariel (o3, openSUSE Leap 16.0, kernel 6.12.0-160000.40)
Status: recovered 2026-10-25; sysctl file, forward drop chain and docker
After= applied; `StartLimitIntervalSec=0` pending. Theory verified 2026-10-26
against upstream sources without logging in to ariel, see ## Verification.

## Symptom and impact

https://openqa.opensuse.org/ returned 502 from nginx. `nginx
vhosts.d/frontend.conf` proxies `location /` to `upstream anubis =
[::1]:8049`, which is the anubis container defined in
`/etc/nginx/anubis/docker-compose.yml` (`BIND: ":8049"`, `TARGET:
http://localhost:8042`). With `docker.service` in `failed` the container was
not running, so every browser request got 502. API v1 and the worker
websocket/livehandler paths (`location /api/` -> `upstream backend =
[::1]:8042`) kept working: 627 workers stayed connected, so scheduling and
test execution were not blocked. `docker.socket` and `docker.service` were both
in `failed`; `docker0` was DOWN.

## Root cause

Chain of three independent facts, none of them visible from the log line alone:

1. `net.ipv4.ip_forward` is not set by anything on ariel. `grep` over
   `/etc/sysctl.d`, `/usr/lib/sysctl.d`, `/run/sysctl.d`, `/etc/sysctl.conf`,
   `/boot/sysctl.conf-*`, `/etc/sysconfig/network/` and `rc.local` finds no
   such key. SuSEfirewall2 set forwarding as a side effect of `FW_ROUTE`
   (`switch_on_ip_forwarding()` in the script, gated on `FW_ROUTE_V4`, warning
   "this option has been implicitly enabled now"), not of its FORWARD rules;
   its FORWARD policy was DROP (`reset_rules` called as
   `reset_rules "$DROP_JUMP" ACCEPT "$DROP_JUMP"`). SuSEfirewall2 was removed
   on 2026-04-27
   (`/var/log/zypp/history`: `SuSEfirewall2-3.6.378-1.33.noarch removed ok`,
   `nftables` installed the same day). `docker.service.d/override.conf` still
   carries the dangling `After=SuSEfirewall2.service`, which is why forwarding
   and docker start were ordered together; the shipped Factory `docker.service`
   has `After=network.target lvm2-monitor.service firewalld.service` and no
   SuSEfirewall2, so that line is ariel-local.
2. Forwarding was kept alive by dockerd itself, not by the host. In moby
   `daemon/libnetwork/drivers/bridge/bridge_linux.go:881-893` the forwarding
   step runs `setupIPv4Forwarding()` only if the firewaller implements
   `filterForwardDropper` (type assertion at 885, `checkIPv4Forwarding()` at
   889, `setupIPv4Forwarding()` at 892); that interface is implemented by
   `iptabler` (`daemon/libnetwork/drivers/bridge/internal/iptabler/iptabler.go:93`)
   and never by `nftabler`, whose only methods are `Close`, `init`,
   `SetFirewallCleaner` and `NewNetwork`. With the
   iptables backend dockerd writes `ip_forward=1` and sets the FORWARD policy
   to DROP; with the nftables backend it only *checks* the sysctl and aborts,
   see `setup_ip_forwarding.go:24-36` (comment at 33-34, error at 35) and
   upstream commit 67ffa47090d4, authored 2025-08-05, "nftables: don't enable
   IP forwarding".
3. Ariel moved to the check-only path on 2026-10-15:
   `/etc/docker/daemon.json` (mtime 14:07) contains
   `"firewall-backend": "nftables"`, dockerd restarted 14:08,
   `/etc/nftables/rules/main.nft` was created 14:14; the same switch is
   committed in the config repo as `6346bd5 Add nftables rules and enable
   nftables.service` (poo#208518, 2026-10-15 14:21 UTC), and that ruleset is
   input-only with no forward hook. The last iptables-era
   trace is in the previous boot's journal, Oct 15 14:08:05: `Network traffic
   for published ports may be dropped, iptables chain FORWARD has policy DROP.`
   — that string exists only in `iptabler/cleaner.go`. The switch happened on a
   running daemon whose kernel `ip_forward` was already 1, so no symptom
   appeared. Boots on 2026-08-16 and 2026-09-27 with docker 29.4.0 succeeded
   for the same reason.

The 2026-10-25 04:30 reboot (patch 1973, kernel 6.12.0-160000.40, docker
29.7.2 installed 2026-10-24) was the first boot with `ip_forward=0` and a
check-only daemon. `journalctl -b -u docker` shows warnings for
`br-6c5af94aa34e` and `docker0` "while booting up from persistent state", then
the fatal `failed to start daemon: Error initializing network controller:
error creating default "bridge" network`. Three start attempts within
`StartLimitInterval=60s` exhausted `StartLimitBurst=3`, so
`docker.service` (NRestarts=3) and `docker.socket`
(`service-start-limit-hit`) wedged into `failed`.

`systemctl start docker.service` after setting the sysctl reproduced the same
message because the start request was answered by the cached start-limit
failure, not by dockerd: `service_start()` calls `unit_test_start_limit()`,
which returns `-ECANCELED` while `start_limit_hit` is set. The flag is
self-healing — `unit_test_start_limit()` clears it once the
`StartLimitIntervalSec=60` ratelimit window has recovered, so a plain start
succeeds again after >60 s.

The socket did not do what the recovery sequence looks like it did. The Factory
`docker.socket` has `BindsTo=docker.service`, `docker.service` has
`Wants=docker.socket` and no `TriggersPath` (`ExecStart` has no `-H fd://`), so
there is no `TriggeredBy` link and starting the socket never triggers dockerd.
`BindsTo` maps to `UNIT_ATOM_PULL_IN_START`, so `systemctl start docker.socket`
puts `docker.service` in the same transaction: a successful socket start means
the service started inside that transaction, and a start-limit refusal of the
service fails the socket too (`PROPAGATE_START_FAILURE` via `BoundBy`). What
worked is the ratelimit window having recovered between the refused start and
the socket start; the trailing `systemctl start docker.service` was then a
no-op. The socket's own `failed` state is the mirror image of the same
mechanism: `socket_service_state_change()` propagates the service's
`start_limit_hit` to the socket as `SOCKET_FAILURE_SERVICE_START_LIMIT_HIT`.
Canonical form is `systemctl reset-failed docker.service docker.socket` before
starting (`unit_reset_failed()` resets the ratelimit and clears the flag).

Downgrading docker is not warranted: 29.7.2 carries CVE fixes (bsc#1262346,
bsc#1265782, CVE-2026-31431 mitigation) and the check is upstream behaviour,
not a SUSE patch. The `fsverity` and SELinux warnings in the log are unrelated
noise on this host.

## Work done

1. Recovery, by okurz on ariel: `sudo sysctl net.ipv4.ip_forward=1`,
   `systemctl start docker.socket && systemctl start docker.service`.
   Verified from outside: `docker`/`docker.socket` active, `*:8049` listening,
   https://openqa.opensuse.org/ -> 200.
2. Permanent fix: dedicated file `/etc/sysctl.d/99-docker-ip-forward.conf`
   (comment references poo#209244), config commit `0ab4543 Enable IPv4
   forwarding for docker` in the ariel config repo (`config` alias = `git
   --git-dir=/etc/.cfg --work-tree=/etc`). `/etc/sysctl.conf` was reverted to
   its pre-append content; the interim append survives in
   `/root/99-sysctl.conf.bak-20261025`. Verified through the real boot actor,
   not the uninstalled `sysctl` package: cleared
   `/proc/sys/net/ipv4/ip_forward` to 0, ran `/usr/lib/systemd/systemd-sysctl`,
   the value returned to 1.
3. Forward drop chain: added to `/etc/nftables/rules/main.nft` inside
   `table inet filter`, config commit `4378ede Drop forwarded traffic that
   docker does not accept`, applied live with `systemctl reload nftables`;
   `nft -c -f` validated the syntax before the reload. `nftables.service` does
   `flush ruleset; include main.nft` and dockerd has no nftables reload socket
   (`/run/nftables-socket` absent, no matching fd in dockerd), so docker's
   `filter-forward-in/out__docker0` chains get flushed and are recreated only
   when the daemon starts. The flush is not inert: `watchtower` is on the
   `anubis_default` bridge, so every live `systemctl reload nftables` leaves
   only the priority-300 drop chain at the forward hook and drops watchtower's
   forwarded traffic (registry pulls, container DNS) until dockerd restarts.
4. Docker drop-in: `/etc/systemd/system/docker.service.d/override.conf` is now
   `After=nftables.service` instead of the dangling `After=SuSEfirewall2.service`,
   `systemctl daemon-reload`, config commit `874242e Order docker after the
   nftables ruleset`; `systemctl show docker -p After` lists
   `nftables.service`.
5. Commits are authored `Oliver Kurz <okurz@suse.de>` with committer
   `o3-admins <o3-admins@<internal>>`, the convention in the config repo. The
   first authoring (`-c user.name=o3-admins`) was reworked with
   `git reset --soft HEAD~2` plus `commit --author`; nothing is pushed.
6. Verified after all changes: drop chain live, `ip_forward` = 1, `nftables`
   and `docker` enabled, `docker`/`docker.socket` active, `*:8049` listening,
   https://openqa.opensuse.org/ and `/api/v1/jobs?limit=1` -> 200.

The forward chain closes the gap enabling forwarding opens: the ruleset had no
forward chain, so forwarding between eth0 (<internal-ip-2>) and eth1
(<internal-ip-1>) was accepted; SuSEfirewall2 covered that with FORWARD DROP.
Docker chains its forward rules at the filter priority, so priority 300 is
evaluated after them and bridge traffic stays allowed.

## Follow-ups pending approval

Not applied, small config edits on ariel (salt does not manage these;
`/srv/salt` and `/srv/pillar` on ariel are not git checkouts):

1. Add `StartLimitIntervalSec=0` to
   `/etc/systemd/system/docker.service.d/override.conf` so a transient failure
   cannot wedge the unit against manual restart the way it did this morning
   (`start_limit_hit` can never be set once the rate limit is disabled).
   Trade-off: `Restart=on-failure` would then restart a crash-looping dockerd
   forever, so the gentler form is `StartLimitIntervalSec=600` with
   `StartLimitBurst=3`, which keeps the crash-loop guard and gives a 10-minute
   manual window. The 3/60 numbers come from Factory's shipped `docker.service`
   (`Restart=on-failure`, `StartLimitBurst=3`, `StartLimitInterval=60s`), not
   from the ariel drop-in.
2. Rejected alternative to forwarding-on: `"ip-forward": false` in
   `/etc/docker/daemon.json` (json key verified as `ip-forward`, CLI flag
   `--ip-forward` default true) skips the check and stops dockerd writing the
   sysctl, but leaves docker's NAT rules in place. Not viable: anubis is
   `network_mode: host`, `watchtower` is on the `anubis_default` bridge, and
   traffic from a bridge container to a registry is forwarded through the
   bridge out of eth0, which dies with `ip_forward=0`. Check
   `docker ps --format '{{.Name}} {{.NetworkMode}}'` before ever approving
   this.

## Verification (2026-10-26, no remote login to o3)

Checked against upstream sources cloned under `/tmp/moby-check/` (moby
`docker-29.x` @ 0367cbeb49b9 of 2026-10-20, moby `master` @ b711d21792d,
systemd 263~devel, openSUSE/susefirewall2), OBS `openSUSE:Factory` sources, the
local `o3-config` checkout and openQA's public API. Every claim that can be
checked without ariel holds; the three defects found are the FORWARD/ip_forward
attribution, the `TriggeredBy` mechanism, and follow-up 2.

- moby `docker-29.x` contains the check: `bridge_linux.go` option block 881-893
  (`filterForwardDropper` assertion 885, `checkIPv4Forwarding()` 889,
  `setupIPv4Forwarding()` 892), `setup_ip_forwarding.go` 24-36, `FilterForwardDrop`
  implemented only in `drivers/bridge/internal/iptabler/iptabler.go:93`,
  `Nftabler` has no such method (`Close`, `init`, `SetFirewallCleaner`,
  `NewNetwork`), `newFirewaller` (bridge_linux.go:554-572) picks nftabler when
  `nftables.Enabled()`. The fatal line in the ticket is `daemon_unix.go:1015`
  wrapped by `daemon.go:620`; the iptables-only warning is
  `iptabler/cleaner.go:54`. Commit 67ffa47090d4 exists, authored 2025-08-05,
  "nftables: don't enable IP forwarding". Per-bridge chain names are
  `filter-forward-in__<ifname>`/`filter-forward-out__<ifname>`
  (nftabler/network.go:290,294) plus the base chain `filter-FORWARD` in table
  `ip docker-bridges` at priority 0 (`BaseChainPriorityFilter = 0`,
  nftables_linux.go:117), so a chain at 300 is evaluated after docker's rules.
- Factory `docker` is 29.7.2 (`docker-29.7.2_ce_6a43e3d5af.tar.xz`); the top
  `docker.changes` entry lists bsc#1262346, bsc#1265782, bsc#1266625, bsc#1267827
  and the `docker-af-alg-deny.cil` CVE-2026-31431 mitigation, and 29.4.0 is an
  earlier entry — the no-downgrade argument holds. Factory's `docker.service`
  ships `Restart=on-failure`, `StartLimitBurst=3`, `StartLimitInterval=60s` and
  `After=network.target lvm2-monitor.service firewalld.service`, so the start-limit
  numbers are shipped defaults and `After=SuSEfirewall2.service` is ariel-local.
  `docker.socket` ships `BindsTo=docker.service`.
- systemd: `unit_test_start_limit()` (unit.c:1884) sets and clears
  `start_limit_hit` against the ratelimit window, `unit_reset_failed()`
  (unit.c:3934) resets it, `socket_service_state_change()` (socket.c:3495)
  propagates `start_limit_hit` into the socket as
  `SOCKET_FAILURE_SERVICE_START_LIMIT_HIT`, `BindsTo` = `UNIT_ATOM_PULL_IN_START`
  (unit-dependency-atom.c:31) which transaction.c:1145 turns into a start job
  for the bound unit. `CONF_PATHS` for sysctl.d covers `/etc`, `/run`,
  `/usr/lib` (src/sysctl/sysctl.c:322), files sorted by name, so
  `99-sysctl.conf` is applied last.
- Local Tumbleweed sample: the `99-sysctl.conf` symlink to `/etc/sysctl.conf` is
  in `/usr/lib/sysctl.d` (systemd package), not `/etc/sysctl.d`, and YaST writes
  `/etc/sysctl.d/70-yast.conf` with `net.ipv4.ip_forward = 0`. A
  `99-docker-ip-forward.conf` at the end of the sort order wins over a `70-yast`
  drop of 0; confirm the real paths on ariel.
- `o3-config` @ `6346bd5` (2026-10-15 14:21:18 UTC, o3-admins, poo#208518)
  added `nftables/rules/main.nft` (input only: `policy accept`, one reject) *and*
  `systemd/system/sysinit.target.wants/nftables.service` — the nftables switch is
  committed on the day the plan gives for the `daemon.json` mtime and the
  `main.nft` creation.
- `frontend.conf`: `location /` (both vhosts) -> `upstream anubis` `[::1]:8049`;
  `/api/`, `/api/v1/ws/`, `/liveviewhandler/`, `/tests/…/livelog|liveterminal`
  and image extensions -> `upstream backend` `[::1]:8042` directly. The
  502-for-browsers / API-and-workers-unaffected split is right. `anubis` is
  `network_mode: host` with `BIND: ":8049"`, `TARGET: http://localhost:8042`;
  `watchtower` has no `network_mode`, so it gets the project's bridge.
- API now: https://openqa.opensuse.org/ -> 200; `api/v1/workers` -> 714 records,
  627 with `alive=1`/`connected=1`/`websocket=1` — exactly the 627 in the plan.

Not checkable without ariel: zypp history dates, `daemon.json` mtime, the
journal lines, the docker drop-in, `nft list chains` output, `NRestarts=3`, and
the live state of `watchtower`.

## Gates

After the Sunday 04:30 reboot, and after any live `systemctl reload nftables`:
`nft list chains` must show docker's `filter-FORWARD`,
`filter-forward-in__<bridge>` and `filter-forward-out__<bridge>` chains, and
`docker exec watchtower wget -qO- https://registry-1.docker.io/v2/` must answer.
`curl -s -o /dev/null -w '%{http_code}\n'
https://openqa.opensuse.org/` -> 200, `ssh o3 'systemctl is-active docker
docker.socket; ss -ltn | grep 8049'` -> active/active + LISTEN, `ssh o3 'cat
/proc/sys/net/ipv4/ip_forward'` -> 1, `ssh o3 'sudo nft list chain inet filter
forward'` -> drop chain at priority 300, `ssh o3 'sudo nft list chains | grep
docker-bridges'` -> docker recreated its chains, `ssh o3 'systemctl show docker
-p After | grep nftables.service'` -> present, `ssh o3 'sudo git --git-dir=/etc/.cfg
--work-tree=/etc log --oneline -3'` -> `874242e` + `4378ede` + `0ab4543`.

## Session starter

Read this file, run the gates after the reboot. If a follow-up is approved,
apply it on ariel and commit as:

```
sudo git --git-dir=/etc/.cfg --work-tree=/etc add -f <path>
sudo env GIT_COMMITTER_NAME=o3-admins GIT_COMMITTER_EMAIL=o3-admins@<internal> \
  git --git-dir=/etc/.cfg --work-tree=/etc commit -F <msg> \
  --author="Oliver Kurz <okurz@suse.de>" -- <path>
```

then re-run the gates and record approvals below.

## Approvals

- `net.ipv4.ip_forward = 1` as a dedicated sysctl.d file, config commit
  `0ab4543` — okurz, 2026-10-25, applied.
- forward drop chain in `/etc/nftables/rules/main.nft`, config commit `4378ede`
  — okurz, 2026-10-25, applied.
- `After=nftables.service` in `docker.service.d/override.conf`, config commit
  `874242e` — okurz, 2026-10-25, applied.
- commits authored `Oliver Kurz <okurz@suse.de>` with committer `o3-admins` —
  okurz, 2026-10-25, applied.
- sudo on ariel for read-only research, the changes and the config commits —
  okurz, 2026-10-25.
- `StartLimitIntervalSec=0` in the docker drop-in — not approved yet;
  `ip-forward: false` is rejected, see follow-up 2.

## Ticket comment (ready to paste)

TL;DR: not a docker upgrade problem, a missing host sysctl that docker used to
set for itself. `net.ipv4.ip_forward` is set by nothing on ariel; SuSEfirewall2
did it as a side effect of `FW_ROUTE` (`switch_on_ip_forwarding()`, warning "you
should configure this in /etc/sysctl.conf") and covered the forward hook with
FORWARD DROP; it was removed 2026-04-27
(`nftables` installed the same day, `docker.service.d/override.conf` ordered
`After=SuSEfirewall2.service` afterwards). For months forwarding stayed 1
because dockerd set it: in moby
`daemon/libnetwork/drivers/bridge/bridge_linux.go:881-893` the forwarding step
runs `setupIPv4Forwarding()` only when the firewaller implements
`filterForwardDropper`, which `iptabler` does and `nftabler` never does. With
`firewall-backend: nftables` dockerd only *checks* the sysctl and aborts
("IPv4 forwarding is disabled", `setup_ip_forwarding.go:24-36`, upstream commit
67ffa47090d4, 2025-08-05, "nftables: don't enable IP forwarding"). Ariel switched
to nftables on 2026-10-15 (`/etc/docker/daemon.json` mtime 14:07, dockerd
restarted 14:08, `/etc/nftables/rules/main.nft` created 14:14; the last
iptables-only warning `iptables chain FORWARD has policy DROP` is in the
journal of Oct 15 14:08:05) on a running daemon, so the kernel value stayed 1
and the boots of 2026-08-16 and 2026-09-27 passed. Ariel got docker 29.7.2 with
the Leap 16.0 dup on 2026-10-24, and the 2026-10-25 04:30 reboot was the first
boot with forwarding 0 and a check-only daemon; three start attempts inside
`StartLimitInterval=60s` exhausted `StartLimitBurst=3`, so `docker.service` and
`docker.socket` wedged in `failed` and the anubis container (BIND `:8049`,
target `localhost:8042`, the `upstream anubis` that `frontend.conf` proxies
`location /` to) never started → 502 for browsers. API v1, websocket and
livehandler were unaffected; 627 workers stayed connected, so scheduling and
testing kept running.

`systemctl start docker.service` after `sysctl net.ipv4.ip_forward=1` reproduced
the same message because systemd answered the cached start-limit failure
(`unit_test_start_limit()` refuses while `start_limit_hit` is set, and clears it
once the 60 s window has recovered). `systemctl start docker.socket && systemctl
start docker.service` worked for a different reason than it looks: docker.socket
has `BindsTo=docker.service` and docker.service has no `TriggersPath`, so
starting the socket pulls docker.service into the same transaction — the service
started inside that transaction, the socket did not trigger it — and the
ratelimit window had recovered in between. Canonical form is `systemctl
reset-failed docker.service docker.socket` before start.

Permanent fix, committed in the ariel config repo (`config` alias = `git
--git-dir=/etc/.cfg --work-tree=/etc`, author `Oliver Kurz <okurz@suse.de>`,
committer `o3-admins <o3-admins@<internal>>`):

- `0ab4543 Enable IPv4 forwarding for docker` adds
  `/etc/sysctl.d/99-docker-ip-forward.conf` with a comment naming this ticket.
- `4378ede Drop forwarded traffic that docker does not accept` adds
  `chain forward { type filter hook forward priority 300; policy drop; }` to
  `/etc/nftables/rules/main.nft`. Enabling forwarding opened the gap SuSEfirewall2
  had covered with FORWARD DROP: the ruleset had no forward chain, so forwarding
  between eth0 (<internal-ip-2>) and eth1 (<internal-ip-1>) was accepted. Docker chains
  its forward rules at the filter priority, so priority 300 evaluates after them
  and bridge traffic stays allowed.
- `874242e Order docker after the nftables ruleset` replaces the dangling
  `After=SuSEfirewall2.service` in `docker.service.d/override.conf` with
  `After=nftables.service`; `systemctl show docker -p After` lists it.

Live verification: drop chain present, `ip_forward` = 1, `*:8049` listening,
https://openqa.opensuse.org/ and `/api/v1/jobs?limit=1` → 200. The sysctl was
verified through the actor that applies it at boot,
`/usr/lib/systemd/systemd-sysctl`, because the `sysctl` package is not
installed on ariel. `nftables.service` runs `flush ruleset; include main.nft`
and dockerd has no nftables reload socket, so docker's own forward chains are
flushed on a reload and return only at daemon start; `watchtower` runs on a
bridge, so a live reload leaves only the drop chain at the forward hook and
blocks its registry traffic until dockerd restarts — the gate is `nft list
chains` plus a registry check from the container. The nftables switch is
corroborated in the config repo: `6346bd5 Add nftables rules and enable
nftables.service` (poo#208518, 2026-10-15 14:21 UTC) adds `main.nft`, whose
rules are input-only, plus the enablement symlink. The remaining step is the
Sunday 04:30 reboot: site 200, `ip_forward` = 1, drop chain present, docker's
`filter-forward-in/out__docker0` chains recreated.

Downgrading docker is not warranted: 29.7.2 brings CVE fixes (bsc#1262346,
bsc#1265782, CVE-2026-31431 mitigation) and the check is upstream behaviour.
Open decision: add `StartLimitIntervalSec=0` to `docker.service.d/override.conf`
so a transient failure cannot wedge the unit against manual restart. The
alternative `"ip-forward": false` in `daemon.json` is rejected: anubis is
host-networked but `watchtower` runs on the `anubis_default` bridge, and
forwarding from a bridge container to a registry dies with `ip_forward=0`.

Reusable outcome: the `openqa-o3-infra` skill (ssh batching, root-only paths,
the nginx → anubis → webui port map for triage, the moby `filterForwardDropper`
rule, the start-limit behaviour, `/etc/.cfg` commit conventions) plus a Remote
Investigation bullet in the global `AGENTS.md`, commits `f7c1c52` and `799b179`
in `~/.config/opencode`. The moby mechanism is verified against
moby `docker-29.x` @ 0367cbeb49b9 (2026-10-20, contains the nftables commit)
and the 627 connected workers against `api/v1/workers`.
