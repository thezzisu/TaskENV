#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
version=0.1.2-taskenv.1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$repo"/tools-image/{Dockerfile,init,pivot-init} "$work/"
python3 - "$work/pivot-init" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
old='''/agentenv/bin/busybox runsv /run/sv/envd \\
    >/var/log/agentenv/envd-sv.log \\
    2>&1 &'''
new='''# TaskENV Ubuntu bases enable envd.service. Keep upstream supervision for
# arbitrary rootfs images that do not opt into the systemd integration.
if [ -f /etc/taskenv/systemd-envd ] && [ -f /usr/lib/systemd/system/envd.service ]; then
    echo "TaskENV: delegating envd to systemd"
else
    /agentenv/bin/busybox runsv /run/sv/envd \\
        >/var/log/agentenv/envd-sv.log \\
        2>&1 &
fi'''
assert s.count(old)==1, 'upstream envd bootstrap changed; review TaskENV integration'
p.write_text(s.replace(old,new))
PY
mkdir -p "$repo/taskenv/artifacts/tools"
docker buildx build --platform linux/amd64 --target artifact \
    --build-arg "TOOLS_VERSION=$version" --build-arg ENVD_REF=2026.17 \
    --output "type=local,dest=$repo/taskenv/artifacts/tools" "$work"
printf '%s\n' "$version" > "$repo/taskenv/artifacts/tools/version"
