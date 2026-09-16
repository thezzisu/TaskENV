#!/usr/bin/python3
"""Acceptance against a disposable instance: /init, fault, restore defaults."""
import base64,json,sys,time,tomllib,urllib.request
from pathlib import Path
c=tomllib.loads((Path.home()/'.config/aenv/credentials').read_text());base=c['url'].rstrip('/');sid=sys.argv[1]
def request(path,body=None,headers=None):
 hdr={'X-API-Key':c['api_key']};hdr.update(headers or {})
 if body is not None:hdr['Content-Type']='application/json'
 r=urllib.request.Request(base+path,None if body is None else json.dumps(body).encode(),hdr)
 with urllib.request.urlopen(r,timeout=20) as f:
  content=f.read();return json.loads(content) if content else None
s=request('/sandboxes/'+sid)
token=s['envdAccessToken']
env={'TASKENV_RESTART_SENTINEL':'preserved-by-envd','PATH':'/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'}
request('/proxy/init',{'envVars':env,'defaultUser':'ubuntu','defaultWorkdir':'/home/ubuntu','accessToken':token},{'x-agentenv-sandbox-id':sid,'x-agentenv-target-port':'49983','X-Access-Token':token})
print('TASKENV_ENVD_CONTEXT_INITIALIZED',flush=True)
