#!/bin/bash
set -euo pipefail
test "$(cat /proc/1/comm)" = systemd
test "$(hostname)" = taskenv
test "$(cat /etc/hostname)" = taskenv
getent ahostsv4 taskenv | grep '^127\.0\.1\.1 '
sudo systemctl is-active taskenv-envd dbus systemd-udevd user@1000.service
pid=$(systemctl show taskenv-envd --property=MainPID --value)
test "$pid" -gt 1
test "$(pgrep -x envd | wc -l)" -eq 1
test "$(awk '/PPid/{print $2}' /proc/$pid/status)" -eq 1
! pgrep -f '^/agentenv/bin/busybox runsv /run/sv/envd$'
case "$(cat /agentenv/tools-drive-version)" in
    0.1.2-taskenv.2|0.1.2-taskenv.3) ;;
    *) echo "unexpected tools drive version" >&2; exit 1 ;;
esac
test "$(sudo readlink /proc/$pid/exe)" = /agentenv/envd
test "$(findmnt -n -T /agentenv/envd -o SOURCE)" = "$(findmnt -n -T /agentenv/deskd -o SOURCE)"
findmnt -n -T /agentenv/envd -o SOURCE | grep '^/dev/vda\[/agentenv\]$'
test "$(readlink -f /etc/systemd/system/taskenv-envd.service)" = /agentenv/systemd/taskenv-envd.service
for path in /usr/bin/deskd /usr/local/bin/deskd /usr/local/bin/envd /usr/lib/taskenv/envd /usr/lib/deskd; do
    test ! -e "$path" && test ! -L "$path"
done
! dpkg-query -W -f='${Status}\n' taskenv-envd deskd 2>/dev/null | grep 'install ok installed'
sudo -n true
ip route get 1.1.1.1 >/dev/null
getent ahostsv4 github.com >/dev/null
curl --retry 3 --retry-all-errors -fsS --max-time 20 http://archive.ubuntu.com/ubuntu/ >/dev/null
curl --retry 3 --retry-all-errors -fsS --max-time 20 https://github.com >/dev/null
test -r /dev/kvm && test -w /dev/kvm
printf 'PID1=systemd ENVD_PID=%s TOOLS=%s USER=%s\n' "$pid" "$(cat /agentenv/tools-drive-version)" "$(id -un)"
echo TASKENV_BASE_CHECK_PASS
