# TaskENV 0.1.0 — local deployment

Deployed on 2026-09-16 to the existing Fedora host. Repository: https://github.com/thezzisu/TaskENV. The complete AgentENV history is preserved, with `upstream` configured for the original repository and upstream pushes disabled.

## Installed components

- `taskenv` 0.1.0: branded entry point to the compatible `aenv` 0.2.1 CLI.
- `taskenv.service`: alias of the existing `aenv.service`, now described as TaskENV. There is one server, one state store, and the same API/configuration format.
- Tools drive `0.1.2-taskenv.1`: upstream envd fallback plus opt-in handoff to systemd on TaskENV bases.
- `taskenv-envd` `0.5.15+taskenv.1`: upstream `e2b-dev/infra@2026.17` (`9c3b7c5`) with process-default persistence. Wire/API version remains 0.5.15.
- `deskd` 0.1.0: independently packaged desktop integration, running Selkies `2.0.0rc0`, Xfce and Xvfb through systemd user services.
- Chromium 153.0.8010.36 from Canonical's stable Snap channel.
- Development: nvm 0.40.3, Node 24.21.0 LTS, Rust 1.98.1, Go 1.27.1, uv 0.12.14, Git 2.43, official Docker 29.8.1, Compose 5.5.1 and Buildx 0.37.1.

## Templates

All four use Ubuntu 24.04, systemd PID 1, user `ubuntu` with passwordless sudo, 16 vCPU, 32768 MiB RAM and 131072 MiB disk.

| Name | Template ID |
| --- | --- |
| `taskenv-ubuntu-24-04-base` | `01a0aabb-a6c4-7a93-b076-c55112495f4e` |
| `taskenv-ubuntu-24-04-desktop` | `01a0aabb-d2ac-7171-98f0-8781c1157e22` |
| `taskenv-ubuntu-24-04-dev` | `01a0aabb-baed-7bd1-a9f9-ebb14644e6d7` |
| `taskenv-ubuntu-24-04-dev-desktop` | `01a0aac3-d560-7422-b686-15f965f04128` |

The earlier `ubuntu-24-04-base` and `ubuntu-24-04-dev` templates remain available for compatibility/rollback. Existing user sandboxes were preserved. Temporary TaskENV staging templates and test/build sandboxes are removed after verification.

A ready development desktop is kept running as `01a0aac3-e524-7ed1-97a1-f05d027ecee5` with a 24-hour timeout. Connect with:

```bash
taskenv connect 01a0aac3-e524-7ed1-97a1-f05d027ecee5 --gui
```

The CLI handles desktop authentication automatically through envd; no password prompt or host credential file is needed. The guest keeps deskd's credential file at `~/.config/deskd/credentials.json`. Credential borrowing, SSH-agent brokering, Git/OAuth/API-key sharing and new credential policy are explicitly deferred.

## Verification

| Check | Result |
| --- | --- |
| CLI tests / formatting / workspace clippy / release build | PASS; 63 CLI tests, clippy with all targets/features and warnings denied |
| envd persistence unit tests | PASS; user/workdir/environment survive replacement; corrupt state is rejected; file mode 0600 |
| Fresh headless base | PASS; systemd PID 1; one envd under systemd; D-Bus, udev and lingering user manager active; KVM device access; DNS and HTTP/HTTPS |
| envd SIGKILL and automatic restart | PASS; `ubuntu`, workdir and initialized environment survive; runtime context file is root-owned 0600 |
| Final desktop envd restart | PASS; DISPLAY/Xauthority and Node/Rust/Go/uv remain available; deskd and Docker unaffected |
| Unattended desktop before viewer attach | PASS; real terminal keyboard input, PyAutoGUI and MSS screenshots, Chromium GUI opening a local web app |
| deskd stream stop/restart/crash | PASS; same Xvfb PID remains; display and envd stay usable; systemd restarts Selkies |
| Native Selkies upload/download and clipboard | PASS through temporary CLI forward; file bytes match; clipboard transfers in both directions |
| Automatic GUI login | PASS on the ready sandbox with a fresh browser and no credentials configured in it; HTTP/WebSocket, files and clipboard work without a login prompt; direct guest access still requires authentication |
| Base / desktop / development pause-resume | PASS |
| Desktop fork | PASS; child has working persistent display, agent input and screenshot capture |
| Final development desktop pause-resume with nested QEMU | PASS; capture guard stops the nested VM, outer envd/deskd/Docker recover, new KVM_RUN succeeds |
| Docker resource enforcement | PASS; CPU throttling, memory OOM, PID limit, cpuset, cgroup v2/systemd |
| Compose network, DNS and Docker service restart | PASS |
| Build registry removed | PASS; new base sandbox still starts after registry shutdown/removal |
| Temporary GUI listener cleanup | PASS; Ctrl-C releases the random loopback port |

Stopping envd intentionally closes its active terminal/RPC streams; callers reconnect after systemd restarts it. Default identity/environment are restored before it serves requests. The upstream envd API access token is not serialized into the new runtime context file.

The guest kernel remains the verified 6.1.175-aenv-nested build. No host networking/firewall/sing-box/EasyTier policy was changed. Runtime state stays under the compatible `/var/lib/aenv` paths. No extra nginx, FileBrowser, credential service, or permanent host desktop listener is installed.

AppArmor/GPU features absent from the current guest kernel are not supplied merely by using systemd. Chromium's own namespace/Seccomp sandbox remains enabled. Running nested VM RAM state is still intentionally discarded before outer capture by the previously verified guard.

## Artifacts and provenance

Build/provisioning recipes and tests are tracked under `taskenv/`. Local packages, tools images, detailed logs and screenshots are excluded from Git under `taskenv/artifacts/`.

- Tools image SHA256: `dd446b5004227cdd297459056a578f16a93dc83046c7a9631e5ceb8d2969180e`.
- Deployed envd binary SHA256: `4307d1eecb7212f9ad5dbc60c287ef63d1a6745d45b82aa001197788bec748dc`.
- `sha256.json`: generated package/image checksums.
- `envd-build.log`, `aenv-tests.log`, `clippy.log`: build/check evidence.
- `envd-recovery.log`, `final-envd-recovery.log`: daemon recovery evidence.
- `profile-checks.log`, `dev-check.log`, `final-profile-check.log`: fresh template checks. One transient external HTTPS reset in the first aggregate run was retried successfully in `dev-check.log`.
- `desktop-fork-check.log`, `desktop-after-resume.log`, `final-after-pause.log`: lifecycle evidence.
- `base-desktop-browser.*`, `dev-desktop-browser.*`, `final-chromium.png`: real browser and file-transfer evidence.
- `final-docker-browser.log`, `nested-before-pause.log`: Docker and nested-KVM checks.

The original AgentENV implementation is changed only at the CLI branding hook and root README for this distribution. The envd customization is an explicit, checked patch applied to a temporary upstream source tree; deskd and template recipes are independent distribution files. This keeps future AgentENV merges and selective cherry-picks small.
