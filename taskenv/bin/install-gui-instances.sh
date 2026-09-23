#!/bin/bash
# Install the boot-time lifecycle hook for the three permanent GUI sandboxes.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
test "$(id -u)" = 0

install -m 0755 "$repo/taskenv/bin/taskenv-gui-instances-resume.py" \
    /usr/local/sbin/taskenv-gui-instances-resume
install -m 0644 "$repo/taskenv/systemd/taskenv-gui-instances.service" \
    /etc/systemd/system/taskenv-gui-instances.service
systemctl daemon-reload
systemctl enable taskenv-gui-instances.service
systemctl reset-failed taskenv-gui-instances.service
systemctl restart taskenv-gui-instances.service
systemctl is-active taskenv-gui-instances.service
