#!/bin/bash
# Preserve the existing installation/state; add TaskENV entry points.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
target=${CARGO_TARGET_DIR:-$repo/target}
test "$(id -u)" = 0
test -s "$repo/taskenv/artifacts/tools/tools.ext4"
version=$(cat "$repo/taskenv/artifacts/tools/version")
install -m 0755 "$target/release/aenv" /usr/local/bin/aenv.taskenv
mv /usr/local/bin/aenv.taskenv /usr/local/bin/aenv
ln -sfn aenv /usr/local/bin/taskenv
ln -sfn server /usr/local/bin/taskenv-server
install -D -m 0644 "$repo/taskenv/artifacts/tools/tools.ext4" "/var/lib/aenv/deps/taskenv-tools/$version/tools.ext4"
TASKENV_TOOLS_VERSION="$version" python3 - <<'PY'
from pathlib import Path
import os,shutil,tomllib,re
p=Path('/var/lib/aenv/config/config.toml');s=p.read_text();tomllib.loads(s)
backup=p.with_name('config.toml.before-taskenv')
if not backup.exists():shutil.copy2(p,backup)
version=os.environ['TASKENV_TOOLS_VERSION']
source=f'/var/lib/aenv/deps/taskenv-tools/{version}/tools.ext4'
section=re.search(r'(?ms)^\[tools\]\n.*?(?=^\[|\Z)',s)
assert section, 'tools section missing'
t=section.group(0)
for key in ('version','drive_path'):t=re.sub(r'(?m)^'+key+r'\s*=.*\n','',t)
t=t.replace('[tools]\n',f'[tools]\nversion = "{version}"\ndrive_path = "{source}"\n')
s=s[:section.start()]+t+s[section.end():];tomllib.loads(s);p.write_text(s)
PY
mkdir -p /etc/systemd/system/aenv.service.d
cat > /etc/systemd/system/aenv.service.d/20-taskenv.conf <<'UNIT'
[Unit]
Description=TaskENV Server (AgentENV compatible)
[Service]
ExecStart=
ExecStart=/usr/local/bin/taskenv-server
UNIT
ln -sfn aenv.service /etc/systemd/system/taskenv.service
systemctl daemon-reload
systemctl restart taskenv.service
systemctl is-active taskenv.service
/usr/local/bin/taskenv --help
