# Local TaskENV deployment

Updated 2026-09-24. TaskENV 0.1.0 retains the AgentENV API, state store,
`aenv` entry point and configuration names. One server runs through the
`taskenv.service` / `aenv.service` aliases.

## Agent installation

Tools release **0.1.2-taskenv.3** contains both agents:

| Component | Location | Supervisor |
| --- | --- | --- |
| envd 0.5.15 | `/agentenv/envd` | `taskenv-envd.service` |
| deskd 0.1.2 | `/agentenv/deskd` | user `taskenv-deskd.service` |
| Persistent desktop | `/agentenv/desktop-session` | user `taskenv-display.service` |
| Service units | `/agentenv/systemd/` | Standard systemd enablement symlinks |

The regular upstream `tools-image/Makefile` builds the drive. The server imports
it through upstream `[tools].version` and `[tools].drive_path`; Firecracker
attaches it as `/dev/vda`, and upstream `/init` bind-mounts `/agentenv` into the
rootfs. The mount is read-only. No separate agent Debian packages, duplicate
rootfs binaries, forced command aliases, or alternate drive injector remain in
the new templates. Headless templates leave desktop services disabled and omit
GUI dependencies. Arbitrary images retain upstream runsv supervision for envd.

Every guest is named `taskenv`. The upstream network `ip=` boot field carries
that hostname, `pivot-init` writes `/etc/hostname` and sets the kernel UTS
hostname before the user init starts, and the host lifecycle applies the same
fix after envd initialization. The lifecycle step covers old tools drives,
paused/resumed snapshots, and arbitrary images whose distribution init would
otherwise restore `localhost.localdomain`.

The envd source is `e2b-dev/infra@2026.17` (commit `9c3b7c5`). Its existing,
independent execution-context patch preserves user/workdir/environment after
crashes; it has no GUI code and does not serialize the API access token.

Tools SHA256:
`5a22704d55745d49ecceff080c84985d60ac942f790000f0f98b666fe020e38e`.

## Templates

All four use Ubuntu 24.04, full systemd, `ubuntu` with passwordless sudo,
16 vCPU, 32768 MiB RAM and 131072 MiB disk. The host default and cold starts
use tools release `0.1.2-taskenv.3`. Existing published template snapshots
retain their immutable `0.1.2-taskenv.2` tools pin; the post-ready lifecycle
step applies the hostname fix to those snapshots as well.

| Template | ID |
| --- | --- |
| `taskenv-ubuntu-24-04-base` | `01a0ad59-b02f-7113-8070-99a57334afec` |
| `taskenv-ubuntu-24-04-dev` | `01a0ad59-b473-7ff2-8f91-f7497a456719` |
| `taskenv-ubuntu-24-04-desktop` | `01a0ad59-c082-70d3-92f6-5695f65a9757` |
| `taskenv-ubuntu-24-04-dev-desktop` | `01a0ad59-cc90-79b1-bf15-ba0e48909304` |

## Permanent GUI instances

These three instances are long-lived (`timeout` and `expiresAt` are `null`) and
are resumed by the enabled `taskenv-gui-instances.service` unit at host boot:

| Instance | Sandbox ID | EasyTier network |
| --- | --- | --- |
| `zzs_cclab` | `01a0cf25-ddab-7d22-bc4d-7e7059b46bae` | `cclab_pku` (DHCP) |
| `zzs_ccops` | `01a0cf25-df65-7e32-8788-53a17482b77a` | `ccops_pku` (DHCP) |
| `ytj_ccops` | `01a0cf25-dfd5-7eb1-bcdb-b1101016e790` | `ccops_pku` (DHCP) |

Each guest has `sshd` enabled and uses an independent EasyTier secure-mode key
generated inside that guest. The host-side boot hook is installed with:

```bash
sudo bash taskenv/bin/install-gui-instances.sh
```

The hook explicitly applies `timeout: 0` after each resume, so a stale client
cannot leave one of these instances with a short expiration.

Development tools: nvm 0.40.3, Node 24.21.0, Rust 1.98.1, Go 1.27.1, uv 0.12.14,
Git, Docker 29.8.1, Compose 5.5.1 and Buildx 0.37.1. GUI dependencies include
Selkies 2.0.0rc0, Xfce/Xvfb and Chromium 153.0.8010.36 (official stable snap).

## Access and lifecycle

```bash
taskenv start taskenv-ubuntu-24-04-dev-desktop --timeout 14400 -d
taskenv connect <sandbox-id> --gui
```

The CLI gets the connection descriptor from `/agentenv/deskd connect-info`
through envd's unchanged authenticated process API. It supplies browser
credentials privately and forwards through a temporary loopback port. Closing
the forward leaves the desktop running and releases the port. No nginx,
FileBrowser, or permanent host GUI listener is installed.

Existing sandboxes and snapshots retain their immutable tools version. The CLI
also accepts the previous `/usr/bin/deskd` location for those old snapshots;
it does not hot-patch their tools disk or move their running processes. The two
previously running user sandboxes were resumed after the host service update.
Credential borrowing remains deferred.

## Verification

| Check | Result |
| --- | --- |
| Rust formatting and workspace clippy, all targets/features | PASS |
| CLI / runtime-version / deskd unit tests | PASS: 64 / 8 / 4 |
| envd context tests in tools build | PASS |
| Cold boot, shared read-only tools mount, unit symlinks, one envd supervisor | PASS |
| Stock envd/deskd commands preserved; arbitrary rootfs runsv and snapshot version probe | PASS |
| envd SIGKILL recovery: user, workdir and environment; desktop PID unchanged | PASS |
| Unattended desktop input/screenshots and Chromium opening a local web app | PASS |
| deskd stop/start/SIGKILL recovery with persistent Xvfb | PASS |
| New and old desktop automatic login; native upload/download; bidirectional clipboard | PASS |
| GUI forward cleanup; desktop pause/resume | PASS |
| Docker CPU throttling, memory OOM, PID limits, Compose DNS/storage and daemon restart | PASS |
| KVM_RUN directly and inside Docker | PASS |
| Nested QEMU capture guard, source recovery, cloned desktop and pause/resume | PASS |
| Existing user sandbox automatic GUI authentication | PASS |
| All four public aliases launched after removing the build registry | PASS |
| Published development desktop automatic login and native file transfer | PASS |

Evidence is in ignored `taskenv/artifacts/tools-unified/`, including build/test
logs, desktop screenshots, file-transfer hashes and lifecycle results. Recipes
are in [templates/README.md](templates/README.md); agent build details are in
[tools-image/README.md](../tools-image/README.md).
