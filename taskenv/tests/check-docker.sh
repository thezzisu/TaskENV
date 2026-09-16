#!/bin/bash
set -euo pipefail
test "$(id -un)" = ubuntu
sudo -n true
printf 'USER=%s CPU=%s\n' "$(id -un)" "$(nproc)"
awk '/MemTotal/{print}' /proc/meminfo
lsblk -b -o NAME,SIZE,MOUNTPOINT | head -8
sudo systemctl is-active docker containerd
docker info --format 'CGROUP={{.CgroupVersion}} DRIVER={{.CgroupDriver}} WARNINGS={{json .Warnings}}'
docker pull python:3.12-alpine > /tmp/docker-audit-pull.log
work=$(mktemp -d /tmp/docker-audit.XXXXXX)
# Actual CPU throttling + configuration enforced by cgroup v2.
docker run --rm --cpus=0.25 --memory=64m --memory-swap=64m --pids-limit=64 --cpuset-cpus=0 python:3.12-alpine sh -c 'cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/pids.max /sys/fs/cgroup/cpuset.cpus.effective; python -c "while True: pass" & p=$!; sleep 3; cat /sys/fs/cgroup/cpu.stat; kill "$p"' > "$work/cgroup"
cat "$work/cgroup"
awk '$1=="nr_throttled"{if ($2<1) exit 1; found=1} END{if(!found)exit 1}' "$work/cgroup"
printf 'CPU_THROTTLING_PASS\n'
set +e
docker run --name taskenv-audit-oom --memory=64m --memory-swap=64m python:3.12-alpine python -c 'x=bytearray(256*1024*1024); print(len(x))'
code=$?
set -e
test "$code" -eq 137
test "$(docker inspect taskenv-audit-oom --format '{{.State.OOMKilled}}')" = true
docker rm taskenv-audit-oom >/dev/null
printf 'MEMORY_OOM_PASS\n'
docker run --rm --pids-limit=32 python:3.12-alpine python -c 'import subprocess; children=[]
try:
 for _ in range(64): children.append(subprocess.Popen(["sleep","30"]))
except BlockingIOError:
 print("PIDS_ENFORCED", len(children)); assert len(children)<32
else: raise AssertionError("PID limit did not apply")
finally:
 for p in children:p.terminate()
 for p in children:p.wait()'
docker run --rm --device=/dev/kvm -v /usr/local/bin/kvm-smoke:/kvm-smoke:ro ubuntu:24.04 /kvm-smoke
cat > "$work/compose.yaml" <<'YAML'
services:
  app:
    image: python:3.12-alpine
    command: ["sh", "-c", "echo COMPOSE_PERSIST_OK >/data/state; cd /data; exec python -m http.server 8080"]
    ports: ["127.0.0.1:18081:8080"]
    volumes: ["data:/data"]
  client:
    image: python:3.12-alpine
    command: ["python", "-c", "import urllib.request; s=urllib.request.urlopen('http://app:8080/state').read(); assert b'COMPOSE_PERSIST_OK' in s; print('COMPOSE_DNS_NETWORK_OK')"]
volumes:
  data:
YAML
docker compose -p taskenv-audit -f "$work/compose.yaml" up -d app
for attempt in {1..20}; do
 if curl -fsS --max-time 2 http://127.0.0.1:18081/state > "$work/state";then break;fi
 sleep 1
done
grep -q COMPOSE_PERSIST_OK "$work/state"
docker compose -p taskenv-audit -f "$work/compose.yaml" run --rm client
sudo systemctl restart docker
docker compose -p taskenv-audit -f "$work/compose.yaml" up -d app
for attempt in {1..20};do
 if curl -fsS --max-time 2 http://127.0.0.1:18081/state | grep -q COMPOSE_PERSIST_OK;then break;fi
 sleep 1
done
docker compose -p taskenv-audit -f "$work/compose.yaml" run --rm client
docker compose -p taskenv-audit -f "$work/compose.yaml" down -v
printf 'DOCKER_SYSTEMD_RESTART_COMPOSE_PASS\n'
uv --version; node --version; rustc --version; go version
echo TASKENV_DOCKER_AUDIT_COMPLETE
