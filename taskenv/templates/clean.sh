#!/bin/bash
set -euo pipefail
sudo apt-get clean
python3 - <<'PY'
from pathlib import Path
import shutil
h=Path.home()
for name in ('install-taskenv.sh','taskenv-install.log','taskenv-dpkg-recovery.log','desktop-recovery.log','.bash_history'):
 (h/name).unlink(missing_ok=True)
for name in ('.cache/pip',):
 shutil.rmtree(h/name,ignore_errors=True)
for name in ('taskenv-input.txt',):
 (h/'Shared'/name).unlink(missing_ok=True)
PY
if command -v deskd >/dev/null; then
 systemctl --user restart deskd-display.service deskd.service
 for i in {1..30}; do if deskd check; then break; fi; sleep 1; done
 deskd check
fi
sudo python3 - <<'PY'
from pathlib import Path
for name in ('taskenv-envd.deb','upgrade-envd.sh','check-base.sh','check-dev.sh','check-desktop.py','check-desktop-recovery.sh','kvm-smoke.c','kvm-smoke','clean-taskenv.sh'):
 (Path('/tmp')/name).unlink(missing_ok=True)
PY
echo TASKENV_TEMPLATE_CLEAN
