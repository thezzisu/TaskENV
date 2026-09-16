#!/bin/bash
set -euo pipefail
test "$(timeout 3 xclip -selection clipboard -o)" = "$1"
printf '%s' "$2" | xclip -selection clipboard >/dev/null 2>&1
echo TASKENV_CLIPBOARD_GUEST_PASS
