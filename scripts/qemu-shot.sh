#!/bin/bash
# Screenshot the running QEMU guest to build/shots/NAME.png
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SOCK="${QEMU_MON:-$ROOT/build/qemu-mon.sock}"; N=$1
mkdir -p "$ROOT/build/shots"
echo "screendump $ROOT/build/shots/$N.ppm" | socat - "UNIX-CONNECT:$SOCK" >/dev/null; sleep 1
pnmtopng "$ROOT/build/shots/$N.ppm" > "$ROOT/build/shots/$N.png" 2>/dev/null && rm -f "$ROOT/build/shots/$N.ppm"
echo "build/shots/$N.png"
