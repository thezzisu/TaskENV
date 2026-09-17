# Ubuntu 24.04 recipes

Build the tools drive with the commands in the parent guide. Build and publish `Dockerfile.base` to an OCI registry available to the server:

```bash
docker build -f taskenv/templates/Dockerfile.base -t REGISTRY/taskenv/ubuntu-base:0.1.0 .
docker push REGISTRY/taskenv/ubuntu-base:0.1.0
taskenv start --cold REGISTRY/taskenv/ubuntu-base:0.1.0 --cpu 16 --memory 32768 --disk-size-mb 131072 --timeout 28800 -d
```

Capture that cold instance with `taskenv snapshot create <id> --name base-stage` and publish it:

```bash
python3 taskenv/bin/publish-template.py taskenv-ubuntu-24-04-base base-stage
taskenv template watch taskenv-ubuntu-24-04-base
```

Start two instances of the headless base. In an interactive `ubuntu` tmux shell, run `install-dev.sh` on one and `install-desktop.sh` on the other. The desktop script expects the verified upstream `selkies.deb` under `~/taskenv-install/`. Upload the scripts/packages with `taskenv upload`. Both scripts install from Ubuntu or the project's official repository/installer; Go uses its official archive with a SHA256 check.

For the deployment KVM smoke helper, upload `taskenv/tests/kvm-smoke.c` to `/tmp/kvm-smoke.c` in the development instance, compile it with `gcc -O2`, and install it at `/usr/local/bin/kvm-smoke`. It is a small diagnostic, not a service.

After testing and cleaning with `clean.sh`, snapshot each instance and publish with `--dev` or `--desktop`, respectively. To build `taskenv-ubuntu-24-04-dev-desktop`, start an instance of `taskenv-ubuntu-24-04-dev`, install the same desktop suite, and publish with **both** `--dev --desktop`.

No GUI is installed into a headless template. Browser and toolchain state stay in the sandbox rootfs and are captured normally. `envd`, `deskd`, their session helper and systemd units come exclusively from the tools drive mounted at `/agentenv`. The rootfs holds only dependencies and standard service enablement links. Every snapshot pins the complete tools release.

New template aliases must be unused. The upstream repository rejects alias collisions. Build and verify a staging template before replacing an existing production name. Do not modify catalog files by hand.

`install-dev.sh` pins Node 24.21.0, nvm 0.40.3, Rust 1.98.1, Go 1.27.1 and uv 0.12.14. Docker and Chromium are installed from their official stable channels; record the resolved package versions at publication. Updating the tools drive requires a new immutable tools version.
