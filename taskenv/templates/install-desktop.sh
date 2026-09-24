#!/bin/bash
# Run in an interactive ubuntu shell inside a TaskENV base sandbox.
set -euo pipefail
test "$(id -un)" = ubuntu
test "$(cat /proc/1/comm)" = systemd
work=$HOME/taskenv-install
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  snapd python3-venv python3-tk python3-pil python3-xlib "$work/selkies.deb" \
  xfce4 xfce4-terminal xvfb xauth x11-utils x11-xserver-utils xdotool scrot xclip \
  xdg-utils libglib2.0-bin gvfs fonts-noto-cjk fonts-noto-color-emoji
sudo systemctl start systemd-udevd-control.socket systemd-udevd-kernel.socket systemd-udevd.service
sudo systemctl enable --now snapd.socket
sudo snap wait system seed.loaded
sudo snap install chromium --channel=latest/stable
mkdir -p ~/Desktop ~/Shared ~/.config/deskd
cp /var/lib/snapd/desktop/applications/chromium_chromium.desktop ~/Desktop/chromium.desktop
chmod 755 ~/Desktop/chromium.desktop
ln -sfn /home/ubuntu/Shared ~/Desktop/Shared
sudo loginctl enable-linger ubuntu
sudo systemctl start user@1000.service
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
systemctl --user daemon-reload
systemctl --user enable --now /agentenv/systemd/taskenv-display.service /agentenv/systemd/taskenv-deskd.service
cat > ~/.config/deskd/environment.sh <<'ENV'
export DISPLAY=:1
export XAUTHORITY=/home/ubuntu/.Xauthority
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export PATH="$PATH:/snap/bin"
ENV
if ! grep -q '/.config/deskd/environment.sh' ~/.profile; then
 printf '\n. "$HOME/.config/deskd/environment.sh"\n' >> ~/.profile
fi
python3 -m venv ~/.local/share/desktop-agent
~/.local/share/desktop-agent/bin/pip install --disable-pip-version-check PyAutoGUI==0.9.54 mss==10.1.0 Pillow==11.3.0
for n in {1..30}; do if /agentenv/deskd check; then break; fi; sleep 1; done
/agentenv/deskd check
sudo apt-get clean
sudo rm -rf -- "$work"
echo TASKENV_DESKTOP_INSTALLED
