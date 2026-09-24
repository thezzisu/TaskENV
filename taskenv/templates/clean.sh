#!/bin/bash
# Run as ubuntu in a disposable template builder before capture.
set -euo pipefail
test "$(id -un)" = ubuntu
sudo apt-get clean
python3 - <<'PY'
from pathlib import Path
import shutil
h=Path.home()
for name in ('install-taskenv.sh','taskenv-install.log','taskenv-install.exit','taskenv-dpkg-recovery.log','desktop-recovery.log','check-base.sh','check-dev.sh','.bash_history',
             'install-dev.sh','install-desktop.sh','finish-desktop.sh','clean-taskenv.sh',
             'dev-install.log','desktop-install.log','finish-desktop.log','.zshrc'):
 (h/name).unlink(missing_ok=True)
for name in ('.cache/pip','.rustup/downloads','.rustup/tmp'):
 shutil.rmtree(h/name,ignore_errors=True)
for name in ('taskenv-input.txt',):
 (h/'Shared'/name).unlink(missing_ok=True)
PY
if systemctl --user is-enabled --quiet taskenv-deskd.service 2>/dev/null; then
 systemctl --user restart taskenv-display.service taskenv-deskd.service
 for i in {1..30}; do if /agentenv/deskd check; then break; fi; sleep 1; done
 /agentenv/deskd check
fi
sudo python3 - "$HOME/taskenv-install" <<'PY'
from pathlib import Path
import shutil,sys
# Uploads can be root-owned even when provisioning runs as ubuntu.
work=Path(sys.argv[1])
if work.is_symlink():
 work.unlink()
elif work.exists():
 shutil.rmtree(work)
for name in ('taskenv-envd.deb','upgrade-envd.sh','check-base.sh','check-dev.sh','check-desktop.py','check-desktop-recovery.sh','kvm-smoke.c','kvm-smoke','clean-taskenv.sh'):
 (Path('/tmp')/name).unlink(missing_ok=True)
PY
echo TASKENV_TEMPLATE_CLEAN
