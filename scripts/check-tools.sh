#!/bin/sh
# Verify every command in the manifest is on PATH. Usage: check-tools.sh [manifest]
# Works on the build host, in the chroot, and on the booted live system.
set -u
MANIFEST="${1:-/etc/nettoolkit/tools.yaml}"
[ -f "$MANIFEST" ] || MANIFEST="$(dirname "$0")/../manifest/tools.yaml"
GEN="$(dirname "$0")/gen-package-list.py"
[ -f "$GEN" ] || GEN=/usr/local/lib/nettoolkit/gen-package-list.py
total=0; present=0
for cmd in $(python3 "$GEN" --manifest "$MANIFEST" --print-cmds | awk '{print $2}' | sort -u); do
  total=$((total+1))
  if command -v "$cmd" >/dev/null 2>&1 || [ -x "/usr/sbin/$cmd" ] || [ -x "/sbin/$cmd" ]; then
    present=$((present+1))
  else
    echo "MISSING: $cmd"
  fi
done
echo "TOOLS: $present/$total present"
[ "$present" -eq "$total" ]
