#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
output="$repo/taskenv/artifacts/downloads"
mkdir -p "$output"
curl --retry 5 --retry-all-errors -fsSL https://github.com/selkies-project/selkies/releases/download/2.0.0rc0/selkies-2.0.0rc0-ubuntu24.04-amd64.deb -o "$output/selkies.deb"
printf '%s  %s\n' 5d4ce06caa9ba251747384207da4450f33e4c2fd2b214846dba8cb946fadeaca "$output/selkies.deb" | sha256sum --check
