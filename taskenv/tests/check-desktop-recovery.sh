#!/bin/bash
set -euo pipefail
export DISPLAY=:1 XAUTHORITY=/home/ubuntu/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
before=$(pgrep -x Xvfb)
/agentenv/deskd check
/agentenv/deskd stop
if /agentenv/deskd check; then echo 'stopped stream reported ready' >&2; exit 1; fi
xdpyinfo >/dev/null
systemctl is-active taskenv-envd
test "$(pgrep -x Xvfb)" = "$before"
/agentenv/deskd start
for i in {1..30}; do if /agentenv/deskd check; then break; fi; sleep 1; done
test "$(pgrep -x Xvfb)" = "$before"
/agentenv/deskd check
systemctl --user kill --kill-whom=main --signal=KILL taskenv-deskd
for i in {1..30}; do sleep 1; if /agentenv/deskd check; then break; fi; done
/agentenv/deskd check
test "$(pgrep -x Xvfb)" = "$before"
systemctl is-active taskenv-envd
echo TASKENV_DESKTOP_RECOVERY_PASS
