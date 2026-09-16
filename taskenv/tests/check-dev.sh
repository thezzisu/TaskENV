#!/bin/bash
set -euo pipefail
test "$(id -un)" = ubuntu
node --version; rustc --version; go version; uv --version; git --version
sudo systemctl is-active docker containerd envd
docker info --format 'CGROUP={{.CgroupVersion}} DRIVER={{.CgroupDriver}}'
docker compose version; docker buildx version
/usr/local/bin/kvm-smoke
docker run --rm --device=/dev/kvm -v /usr/local/bin/kvm-smoke:/kvm-smoke:ro ubuntu:24.04 /kvm-smoke
printf 'TASKENV_DEV_CHECK_PASS\n'
