#!/bin/bash
# Send a line to the guest's serial console (needs test-qemu.sh --direct --console). Output lands in the serial log.
# Usage: qemu-serial.sh 'command'   |   qemu-serial.sh --login  (types user / live if a login prompt is shown)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SOCK="${QEMU_SERIAL:-$ROOT/build/qemu-serial.sock}"
send() { printf '%s\r' "$1" | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1; sleep 0.3; }
if [ "${1:-}" = "--login" ]; then send ""; sleep 1; send "user"; sleep 1; send "live"; sleep 1; exit 0; fi
send "$1"
