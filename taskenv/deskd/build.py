#!/usr/bin/python3
"""Assemble deskd and build it with the distribution's dpkg-deb tool."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parent
OUT=ROOT.parent/'artifacts/deskd_0.1.1_all.deb'
CONTROL=b'''Package: deskd
Version: 0.1.1
Architecture: all
Maintainer: thezzisu <thezzisu@gmail.com>
Section: misc
Priority: optional
Depends: python3, selkies, systemd, dbus-user-session, xfce4, xfce4-terminal, xvfb, xauth, x11-utils, x11-xserver-utils, xdotool, scrot, xclip, xdg-utils, libglib2.0-bin, gvfs, fonts-noto-cjk, fonts-noto-color-emoji
Description: TaskENV desktop agent and persistent desktop integration
 Selkies streaming with a systemd-managed Xfce display for unattended tasks.
'''

OUT.parent.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='deskd-package-') as temp:
    root=Path(temp);root.chmod(0o755)
    (root/'DEBIAN').mkdir()
    (root/'DEBIAN/control').write_bytes(CONTROL)
    files={'deskd':'usr/bin/deskd','session':'usr/lib/deskd/session',
           'deskd.service':'usr/lib/systemd/user/deskd.service',
           'deskd-display.service':'usr/lib/systemd/user/deskd-display.service'}
    for source,destination in files.items():
        target=root/destination;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/source,target)
        target.chmod(0o755 if source in ('deskd','session') else 0o644)
    manifest=root/'usr/share/taskenv/desktop.json'
    manifest.parent.mkdir(parents=True,exist_ok=True)
    manifest.write_text('{"capability":"desktop","version":"0.1.1","backend":"selkies","port":6900,"display":":1","connection_protocol":1}\n')
    subprocess.run(['dpkg-deb','--root-owner-group','--build',str(root),str(OUT)],check=True,env=os.environ | {'SOURCE_DATE_EPOCH':'1789516800'})
print(OUT)
