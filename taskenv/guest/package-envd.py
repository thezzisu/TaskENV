#!/usr/bin/python3
from pathlib import Path
import os,shutil,subprocess,tempfile
root=Path(__file__).resolve().parent
out=root.parent/'artifacts/taskenv-envd_0.5.15+taskenv.1_amd64.deb'
with tempfile.TemporaryDirectory(prefix='taskenv-envd-') as temp:
 p=Path(temp);p.chmod(0o755);(p/'DEBIAN').mkdir()
 (p/'DEBIAN/control').write_text('''Package: taskenv-envd
Version: 0.5.15+taskenv.1
Architecture: amd64
Maintainer: thezzisu <thezzisu@gmail.com>
Depends: systemd
Description: TaskENV process agent, based on upstream envd
 Keeps initialized process defaults across daemon restarts.
''')
 for source,dest,mode in [(root.parent/'artifacts/envd/envd','usr/lib/taskenv/envd',0o755),(root/'envd.service','usr/lib/systemd/system/envd.service',0o644)]:
  target=p/dest;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target);target.chmod(mode)
 subprocess.run(['dpkg-deb','--root-owner-group','--build',str(p),str(out)],check=True,env=os.environ|{'SOURCE_DATE_EPOCH':'1789516800'})
print(out)
