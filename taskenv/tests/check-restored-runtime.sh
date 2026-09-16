#!/bin/bash
set -euo pipefail
test "$(id -un)" = ubuntu
test "$PWD" = /home/ubuntu
test "$DISPLAY" = :1
test "$XAUTHORITY" = /home/ubuntu/.Xauthority
node --version
rustc --version
go version
uv --version
deskd check
sudo systemctl is-active envd docker containerd
if systemctl is-active --quiet taskenv-nested-test; then echo 'nested VM survived capture unexpectedly'; exit 1; fi
/usr/local/bin/kvm-smoke
echo TASKENV_RESTORED_RUNTIME_PASS
