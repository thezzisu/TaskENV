# TaskENV

TaskENV is a soft fork of [AgentENV](https://github.com/kvcache-ai/AgentENV) for everyday tasks. Release 0.1.0 adds an Ubuntu 24.04 systemd foundation and an independent desktop agent. Credential borrowing is deferred.

## Compatibility and upstream updates

The Rust packages, API, configuration keys (`AENV_*`), state paths (`/var/lib/aenv`), service account, and existing `aenv` command remain compatible. `taskenv` is another entry point to the same CLI, with TaskENV help branding. `taskenv.service` names the same service as `aenv.service`, not a second server. Host networking and storage remain unchanged.

The upstream tools-drive lifecycle is retained. Agent sources and units live in `tools-image/`; distribution recipes and deployment scripts live under `taskenv/`. Keep your TaskENV fork as `origin` and the AgentENV repository as `upstream` with its push URL disabled. Use a review branch for upstream updates:

```bash
git fetch upstream
git switch -c merge/agentenv-YYYY-MM-DD
git merge upstream/main
```

Both agents are built by the upstream `tools-image/Makefile` and injected by its existing `/dev/vda` → `/agentenv` bind mount. The only bootstrap changes remove the command alias that could overwrite stock binaries and defer to systemd when the bundled envd unit is enabled. Other images retain upstream runsv. Tools releases are immutable and snapshots retain their recorded tools version.

## Template family

All four templates use Ubuntu 24.04, systemd as PID 1, the `ubuntu` user with passwordless sudo, and 16 vCPU / 32768 MiB RAM / 131072 MiB disk.

| Template | Contents |
| --- | --- |
| `taskenv-ubuntu-24-04-base` | systemd, D-Bus, udev, envd, basic OS tools |
| `taskenv-ubuntu-24-04-desktop` | base + deskd, Xfce/Xvfb, Selkies, Chromium |
| `taskenv-ubuntu-24-04-dev` | base + Git, Node LTS/nvm, Rust/rustup, official Go, uv, Docker/Compose/Buildx, QEMU |
| `taskenv-ubuntu-24-04-dev-desktop` | development + the same deskd desktop suite |

Two recipes share one OS foundation. Desktop packages never get installed automatically into arbitrary custom images. The base has no browser or GUI dependencies. Applications requiring optional kernel facilities remain limited by the deployed kernel; systemd alone does not supply AppArmor or GPU support.

## envd and deskd

Both agents and their service units come from one versioned tools drive:

| Component | Guest path | Supervision |
| --- | --- | --- |
| envd | `/agentenv/envd` | `taskenv-envd.service` (system manager) |
| deskd | `/agentenv/deskd` | `taskenv-deskd.service` (user manager) |
| Desktop session | `/agentenv/desktop-session` | `taskenv-display.service` (user manager) |
| All units | `/agentenv/systemd/` | Standard systemd enablement links |

The rootfs contains OS/GUI dependencies and service enablement links, with no separate envd/deskd packages or duplicate agent binaries. No agent command is installed into `/usr/bin` or `/usr/local/bin`. Headless templates carry the same small tools drive but do not enable the desktop units or install their dependencies.

`envd` is compiled from `e2b-dev/infra@2026.17` (0.5.15). Its small, explicit execution-context persistence patch preserves user/workdir/environment across systemd restarts in a root-only `/run` file. It contains no desktop logic and never serializes the envd API access token. The patch is applied and tested in the regular tools-image build; there is no generated Dockerfile or bootstrap rewrite.

`/agentenv/deskd status|check` reports readiness; `connect-info` supplies the private versioned endpoint/authentication response. `start|stop|restart` controls the stream through systemd. Stopping the stream leaves the display available to agents. `systemctl --user restart taskenv-display` explicitly restarts the graphical session and may close applications. GUI failure does not stop envd.

```bash
taskenv start taskenv-ubuntu-24-04-dev-desktop \
  --name web-test --hostname web-test --timeout 14400 -d
taskenv connect web-test --gui
taskenv exec web-test -- hostname
```

Sandbox names are unique human-readable selectors stored by the control plane;
every command that accepts a sandbox ID also accepts its name. `taskenv list`
shows both values. `--hostname` sets the guest hostname during startup and is
returned in sandbox metadata; a process inside the VM may change its hostname
later, and TaskENV does not reset that change during the running session.

The CLI opens a random loopback port for the duration of the connection. It prints an OSC 8 clickable localhost URL with a plain-text fallback and never opens a browser. Ctrl-C removes the forward. Guest port 6900 serves Selkies directly; there is no nginx, FileBrowser, extra GUI landing service, or permanent host GUI listener. Existing `cn` is unchanged.

`taskenv connect --gui` handles the desktop login automatically. It invokes `/agentenv/deskd connect-info` through envd's existing authenticated `Process.Start` interface. deskd owns its readiness, endpoint and authentication; the CLI does not read or know its credential-file format or path. No password entry or local credential file is needed. The connection response remains in CLI memory and is not printed or placed in the browser URL. An alternate `--gui-port` retains the application's own login, without receiving deskd credentials.

The guest credential file remains mode 0600 and is used by deskd's own authentication. A template captures these credentials, so clones share them until rotated; TaskENV's existing sandbox access controls also apply. Credential borrowing and per-fork grants remain deferred.

The version 1 connection response contains `version`, `port` and `authentication`
(`scheme`, `username`, `password`). This is a private command interface, not an
unauthenticated HTTP endpoint. It refuses terminal output, an unready desktop or
unavailable credentials. The CLI requires a successful exit and rejects unknown
protocol versions/authentication schemes without printing the response. Existing
desktops need deskd 0.1.1 or newer. A fixed command selector also supports the old `/usr/bin/deskd` path in snapshots that pin the previous tools release; it receives no user-supplied shell text. The independent envd restart-context fix has no
GUI logic; neither upstream envd APIs nor protobufs change for desktop attachment.

## Unattended desktop

The persistent display starts with the sandbox and does not depend on a human viewer. It is fixed at 1600×900, with blanking disabled. GUI templates declare DISPLAY=:1, XAUTHORITY=/home/ubuntu/.Xauthority and the user D-Bus environment for noninteractive agents. PyAutoGUI/MSS live in `~/.local/share/desktop-agent`.

```bash
~/.local/share/desktop-agent/bin/python - <<'PY'
import pyautogui
pyautogui.screenshot().save('/tmp/screen.png')
pyautogui.click(500, 300)
PY
```

Native file drag-and-drop/upload/download are provided by Selkies in `~/Shared`. Clipboard works with a compatible browser on the forwarded localhost origin. No viewer is needed for screenshots, input or Chromium startup. Sandbox pause and timeout still govern the VM lifetime.

## Reproduce and deploy

Run Rust builds/tests as the normal user. Docker image builds use the Docker daemon; guest provisioning scripts run from an interactive `ubuntu` shell in tmux.

```bash
cargo build --release -p agentenv --bin server -p aenv --bin aenv
make -C tools-image TOOLS_VERSION=0.1.2-taskenv.3
bash taskenv/templates/fetch-desktop.sh
sudo bash taskenv/bin/install-host.sh
```

The host deployment script is for the existing installation at `/var/lib/aenv`. It backs up configuration, imports the new versioned tools drive, adds compatibility entry points, and restarts the one existing server. It does not migrate or delete state.

`taskenv/templates/Dockerfile.base` builds the headless rootfs. Start it cold at the required resources, then publish via `taskenv/bin/publish-template.py`. Provision development tools with `install-dev.sh`; provision GUI with `install-desktop.sh` after placing verified upstream `selkies.deb` in `~/taskenv-install/`. Capture and publish the two derived families only after validation. See [the full build sequence](templates/README.md) and `DEPLOYMENT.md` for installed IDs and evidence.

Updating the default tools version only affects cold starts. To migrate an existing template, export its prepared rootfs with upstream `aenv-snapshot-image`, cold-start that OCI image with the new tools release, validate, then capture/publish it through the normal template API. Never replace a tools image in place or edit a snapshot's pinned version. Older tools releases remain available for existing sandboxes.
