#!/bin/bash
# Run in an interactive ubuntu shell. Official installers populate user profiles.
set -euo pipefail
test "$(id -un)" = ubuntu
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git build-essential pkg-config libssl-dev unzip zip file jq vim-tiny less wget python3-venv qemu-system-x86 busybox-static cpio
# Docker's own repository and systemd units.
sudo install -m 0755 -d /etc/apt/keyrings
curl --retry 5 --retry-all-errors -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu
sudo systemctl enable --now docker containerd
# nvm + Node LTS, installed using the official nvm installer.
curl --retry 5 --retry-all-errors -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh -o /tmp/taskenv-nvm-install.sh
PROFILE="$HOME/.bashrc" bash /tmp/taskenv-nvm-install.sh
export NVM_DIR="$HOME/.nvm"
set +u
. "$NVM_DIR/nvm.sh"
nvm install 24.21.0
nvm alias default 24.21.0
set -u
# Rust's official installer and a pinned stable toolchain.
curl --retry 5 --retry-all-errors --proto '=https' --tlsv1.2 -fsS https://sh.rustup.rs -o /tmp/taskenv-rustup.sh
sh /tmp/taskenv-rustup.sh -y --profile minimal --default-toolchain 1.98.1
. "$HOME/.cargo/env"
# Go's official archive, verified against go.dev's release metadata.
python3 - <<'PY'
import hashlib,json,urllib.request
from pathlib import Path
name='go1.27.1.linux-amd64.tar.gz'
with urllib.request.urlopen('https://go.dev/dl/?mode=json&include=all',timeout=60) as r:data=json.load(r)
f=next(f for r in data for f in r['files'] if f['filename']==name)
p=Path('/tmp')/name
urllib.request.urlretrieve('https://go.dev/dl/'+name,p)
assert hashlib.sha256(p.read_bytes()).hexdigest()==f['sha256']
print(name+' SHA256 verified')
PY
sudo tar -C /usr/local -xzf /tmp/go1.27.1.linux-amd64.tar.gz
# Astral's official uv installer, pinned for reproducibility.
curl --retry 5 --retry-all-errors -LsSf https://astral.sh/uv/0.12.14/install.sh -o /tmp/taskenv-uv-install.sh
sh /tmp/taskenv-uv-install.sh
mkdir -p ~/.config/taskenv
cat > ~/.config/taskenv/toolchain.sh <<'EOF'
export NVM_DIR="$HOME/.nvm"
[ ! -s "$NVM_DIR/nvm.sh" ] || . "$NVM_DIR/nvm.sh"
[ ! -f "$HOME/.cargo/env" ] || . "$HOME/.cargo/env"
export GOPATH="$HOME/go"
export PATH="$HOME/.local/bin:/usr/local/go/bin:$GOPATH/bin:$PATH"
EOF
printf '\n. "$HOME/.config/taskenv/toolchain.sh"\n' >> ~/.profile
printf '\n. "$HOME/.config/taskenv/toolchain.sh"\n' >> ~/.bashrc
. ~/.config/taskenv/toolchain.sh
node --version; rustc --version; go version; uv --version
sudo docker info --format 'Docker cgroup={{.CgroupVersion}} driver={{.CgroupDriver}}'
sudo apt-get clean
rm -f /tmp/taskenv-{nvm-install,rustup,uv-install}.sh /tmp/go1.27.1.linux-amd64.tar.gz
echo TASKENV_DEV_INSTALLED
