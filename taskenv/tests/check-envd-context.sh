#!/bin/bash
set -euo pipefail
test "$(id -un)" = ubuntu
test "$PWD" = /home/ubuntu
test "$TASKENV_RESTART_SENTINEL" = preserved-by-envd
sudo systemctl is-active envd
test "$(readlink /proc/$(systemctl show envd -p MainPID --value)/exe 2>/dev/null || sudo readlink /proc/$(systemctl show envd -p MainPID --value)/exe)" = /usr/lib/taskenv/envd
sudo stat -c '%a %U' /run/taskenv-envd/context.json
systemctl show envd -p MainPID -p NRestarts
echo TASKENV_ENVD_RESTART_PRESERVES_CONTEXT
