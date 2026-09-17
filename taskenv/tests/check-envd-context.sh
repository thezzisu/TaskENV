#!/bin/bash
set -euo pipefail
test "$(id -un)" = ubuntu
test "$PWD" = /home/ubuntu
test "$TASKENV_RESTART_SENTINEL" = preserved-by-envd
sudo systemctl is-active taskenv-envd
test "$(readlink /proc/$(systemctl show taskenv-envd -p MainPID --value)/exe 2>/dev/null || sudo readlink /proc/$(systemctl show taskenv-envd -p MainPID --value)/exe)" = /agentenv/envd
sudo stat -c '%a %U' /run/taskenv-envd/context.json
systemctl show taskenv-envd -p MainPID -p NRestarts
echo TASKENV_ENVD_RESTART_PRESERVES_CONTEXT
