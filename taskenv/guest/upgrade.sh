#!/bin/bash
# Upgrade a prepared TaskENV guest; fresh images install the same package at build time.
set -euo pipefail
sudo dpkg -i /tmp/taskenv-envd.deb
sudo install -d -m 0700 /run/taskenv-envd
sudo python3 - <<'PY'
import json,os
from pathlib import Path
p=Path('/run/taskenv-envd/context.json')
if not p.exists():
 fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
 with os.fdopen(fd,'w') as f:json.dump({'user':'ubuntu','workdir':'/home/ubuntu','envVars':{'HOME':'/home/ubuntu','USER':'ubuntu','SHELL':'/bin/bash','PATH':'/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','XDG_RUNTIME_DIR':'/run/user/1000','DBUS_SESSION_BUS_ADDRESS':'unix:path=/run/user/1000/bus'}},f)
PY
sudo systemctl daemon-reload
sudo systemctl restart --no-block envd
