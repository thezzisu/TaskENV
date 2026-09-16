# TaskENV

TaskENV is a soft fork of [AgentENV](https://github.com/kvcache-ai/AgentENV) for everyday tasks. Release 0.1.0 adds an Ubuntu 24.04 systemd foundation and an independent desktop package. Credential borrowing is deferred.

## Compatibility and upstream updates

The Rust packages, API, configuration keys (`AENV_*`), state paths (`/var/lib/aenv`), service account, and existing `aenv` command remain compatible. `taskenv` is another entry point to the same CLI, with TaskENV help branding. `taskenv.service` names the same service as `aenv.service`, not a second server. Host networking and storage remain unchanged.

Original upstream code is retained. Distribution recipes, deskd, units and deployment scripts live under `taskenv/`. `origin` is `thezzisu/TaskENV`; `upstream` is `kvcache-ai/AgentENV` with its push URL disabled. Use a review branch for upstream updates:

```bash
git fetch upstream
git switch -c merge/agentenv-YYYY-MM-DD
git merge upstream/main
```

The envd integration is applied only to a temporary tools-image build context. It asserts the expected upstream bootstrap block before replacing it, so an upstream change fails the build rather than silently producing a bad init. Tools releases are immutable and snapshots retain their recorded tools version.

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

`envd` remains the process, terminal and filesystem agent. TaskENV bases run `/usr/lib/taskenv/envd`; `/agentenv/envd` remains the upstream tools-drive fallback. TaskENV's tools drive pins upstream source `e2b-dev/infra@2026.17` (envd 0.5.15) and hands supervision to the packaged `envd.service` on opted-in Ubuntu bases. The separate `taskenv-envd` package contains the upstream binary with a small execution-context persistence patch. The patch preserves default user, workdir and environment across daemon restarts in a root-only `/run` file; it never serializes the envd API access token. Generic images retain the upstream runsv fallback. There is only one envd supervisor per guest.

`deskd` is an independently versioned Debian package. It provides:

- `deskd-display.service`: persistent Xvfb + Xfce under the systemd user manager;
- `deskd.service`: Selkies streaming, clipboard and file transfer, launched by `deskd serve`;
- `deskd status` / `deskd check`: JSON capability and readiness reporting;
- `deskd start|stop|restart`: service-manager controls for the stream;
- `/usr/share/taskenv/desktop.json`: installed capability/version declaration.

It reuses Selkies and systemd rather than implementing a remote-display protocol or process supervisor. Stopping/restarting deskd leaves the display intact. `systemctl --user restart deskd-display` explicitly restarts the graphical session and may close applications. A GUI failure does not stop envd.

```bash
taskenv start taskenv-ubuntu-24-04-dev-desktop --timeout 14400 -d
taskenv connect <sandbox-id> --gui
```

The CLI opens a random loopback port for the duration of the connection. Ctrl-C removes it. Guest port 6900 serves Selkies directly; there is no nginx, FileBrowser, extra GUI landing service, or permanent host GUI listener. Existing `cn` is unchanged.

`taskenv connect --gui` handles the desktop login automatically. It reads `~/.config/deskd/credentials.json` through authenticated envd access and adds authentication only inside the temporary forwarder. No password entry or local credential file is needed. Credentials remain in CLI memory and are not placed in the browser URL. An alternate `--gui-port` retains the application's own login, without receiving deskd credentials.

The guest credential file remains mode 0600 and is used by deskd's own authentication. A template captures these credentials, so clones share them until rotated; TaskENV's existing sandbox access controls also apply. Credential borrowing and per-fork grants remain deferred.

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
cargo build --release -p aenv
python3 taskenv/deskd/build.py  # requires dpkg-deb: dpkg package on Ubuntu/Fedora
sudo bash taskenv/tools/build.sh
sudo bash taskenv/guest/build-envd.sh
python3 taskenv/guest/package-envd.py
bash taskenv/templates/fetch-desktop.sh
sudo bash taskenv/bin/install-host.sh
```

The host deployment script is for the existing installation at `/var/lib/aenv`. It backs up configuration, imports the new versioned tools drive, adds compatibility entry points, and restarts the one existing server. It does not migrate or delete state.

`taskenv/templates/Dockerfile.base` builds the headless rootfs. Start it cold at the required resources, then publish via `taskenv/bin/publish-template.py`. Provision development tools with `install-dev.sh`; provision GUI with `install-desktop.sh` after placing verified `selkies.deb` and `deskd.deb` in `~/taskenv-install/`. Capture and publish the two derived families only after validation. See [the full build sequence](templates/README.md) and `DEPLOYMENT.md` for installed IDs and evidence.
