#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$repo/tools-image/Dockerfile" "$work/Dockerfile"
cp "$repo/taskenv/guest/"{context_state.go,context_state_test.go,envd-context.patch} "$work/"
python3 - "$work/Dockerfile" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
needle='WORKDIR /src/infra/packages/envd\n'
assert s.count(needle)==1
s=s.replace(needle,needle+'''
COPY context_state.go context_state_test.go internal/execcontext/
COPY envd-context.patch /tmp/envd-context.patch
RUN git -C /src/infra apply --directory=packages/envd /tmp/envd-context.patch
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/go/pkg/mod go test ./internal/execcontext
''')
s+='\nFROM scratch AS taskenv-envd\nCOPY --from=envd-builder /out/envd /envd\n'
p.write_text(s)
PY
docker buildx build --platform linux/amd64 --target taskenv-envd \
  --build-arg ENVD_REF=2026.17 --output "type=local,dest=$repo/taskenv/artifacts/envd" "$work"

chmod 0755 "$repo/taskenv/artifacts/envd" "$repo/taskenv/artifacts/envd/envd"
