#!/bin/bash
set -euo pipefail
sudo systemd-run --unit=taskenv-nested-test --uid=ubuntu --property=Type=exec --property=Restart=always /usr/bin/qemu-system-x86_64 -accel kvm -cpu host -m 128 -smp 1 -nodefaults -display none -serial none -no-reboot
sleep 2
sudo systemctl is-active taskenv-nested-test
pid=$(systemctl show taskenv-nested-test -p MainPID --value)
sudo ls -l "/proc/$pid/fd" | grep kvm
echo TASKENV_NESTED_VM_RUNNING
