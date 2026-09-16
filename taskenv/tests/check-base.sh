#!/bin/bash
set -euo pipefail
test "$(cat /proc/1/comm)" = systemd
sudo systemctl is-active envd dbus systemd-udevd user@1000.service
pid=$(systemctl show envd --property=MainPID --value)
test "$pid" -gt 1
test "$(pgrep -x envd | wc -l)" -eq 1
test "$(awk '/PPid/{print $2}' /proc/$pid/status)" -eq 1
! pgrep -f '^/agentenv/bin/busybox runsv /run/sv/envd$'
test "$(cat /agentenv/tools-drive-version)" = 0.1.2-taskenv.1
sudo -n true
ip route get 1.1.1.1 >/dev/null
getent ahostsv4 github.com >/dev/null
curl --retry 3 --retry-all-errors -fsS --max-time 20 http://archive.ubuntu.com/ubuntu/ >/dev/null
curl --retry 3 --retry-all-errors -fsS --max-time 20 https://github.com >/dev/null
test -r /dev/kvm && test -w /dev/kvm
printf 'PID1=systemd ENVD_PID=%s TOOLS=%s USER=%s\n' "$pid" "$(cat /agentenv/tools-drive-version)" "$(id -un)"
echo TASKENV_BASE_CHECK_PASS
