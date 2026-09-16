#!/usr/bin/python3
"""Publish a prepared snapshot through the unmodified AgentENV template API."""
import argparse,json,tomllib,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('source');p.add_argument('--desktop',action='store_true');p.add_argument('--dev',action='store_true');a=p.parse_args()
c=tomllib.loads((Path.home()/'.config/aenv/credentials').read_text())
def call(path,data):
 req=urllib.request.Request(c['url'].rstrip('/')+path,json.dumps(data).encode(),{'X-API-Key':c['api_key'],'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=120) as f:return json.loads(f.read() or '{}')
env={'HOME':'/home/ubuntu','USER':'ubuntu','SHELL':'/bin/bash','PATH':'/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','XDG_RUNTIME_DIR':'/run/user/1000','DBUS_SESSION_BUS_ADDRESS':'unix:path=/run/user/1000/bus'}
if a.dev:env.update(NVM_DIR='/home/ubuntu/.nvm',GOPATH='/home/ubuntu/go',PATH='/home/ubuntu/.local/bin:/home/ubuntu/.nvm/versions/node/v24.21.0/bin:/home/ubuntu/.cargo/bin:/usr/local/go/bin:/home/ubuntu/go/bin:'+env['PATH'])
if a.desktop:env.update(DISPLAY=':1',XAUTHORITY='/home/ubuntu/.Xauthority',XDG_SESSION_TYPE='x11',XDG_CURRENT_DESKTOP='XFCE',PATH=env['PATH']+':/snap/bin')
b=call('/v3/templates',{'name':a.name,'cpuCount':16,'memoryMB':32768})
call(f"/v2/templates/{b['templateID']}/builds/{b['buildID']}",{'fromTemplate':a.source,'steps':[{'type':'USER','args':['ubuntu']},{'type':'WORKDIR','args':['/home/ubuntu']},{'type':'ENV','args':[v for pair in env.items() for v in pair]}],'startCmd':'','readyCmd':'deskd check' if a.desktop else 'systemctl is-active envd'})
print(json.dumps(b))
