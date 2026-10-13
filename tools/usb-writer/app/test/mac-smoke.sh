#!/bin/sh
# macOS smoke test (CI): run the built app binary as root the way the window's worker runs
# (minimal environment, --json status file) against a disk image attached as /dev/diskN, and
# print every event. Usage: test/mac-smoke.sh path/to/binary
set -eu
BIN="$1"
NAME="${2:-$(basename "$BIN")}"
W="$(mktemp -d)"
python3 - "$W/fake.iso" <<'PY'
import struct, sys
n = 4096 * 512
b = bytearray(n)
b[16*2048:16*2048+6] = b"\x01CD001"
b[16*2048+40:16*2048+72] = b"BACKPACK_LIVE".ljust(32)
b[446] = 0x80; b[446+8:446+16] = struct.pack("<II", 0, 4096)
b[462+4] = 0xEF; b[462+8:462+16] = struct.pack("<II", 200, 100)
b[510:512] = b"\x55\xaa"
open(sys.argv[1], "wb").write(b)
PY
hdiutil create -size 300m -layout NONE -o "$W/blank.dmg" >/dev/null
DEV="$(hdiutil attach -nomount "$W/blank.dmg" | head -n1 | awk '{print $1}')"
echo "attached $DEV"
diskutil info "$DEV" | grep -E 'Device Location|Internal|Removable|Virtual|Whole' || true
: > "$W/events.jsonl"
chmod 666 "$W/events.jsonl"
set +e
sudo env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin "$BIN" --yes --json "$W/events.jsonl" \
  --iso "$W/fake.iso" --size 100M "$DEV" > "$W/output.log" 2>&1
rc=$?
set -e
echo "exit status $rc"
echo "--- output"; cat "$W/output.log"
echo "--- events"; cat "$W/events.jsonl"
hdiutil detach "$DEV" >/dev/null 2>&1 || true
# the same as a CI annotation, which is readable without the raw log
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  body="$(printf 'exit %s\n--- output\n%s\n--- events\n%s' "$rc" "$(tail -n 20 "$W/output.log")" "$(tail -n 20 "$W/events.jsonl")" | awk '{printf "%s%%0A", $0}')"
  echo "::notice title=mac-smoke $NAME::$body"
fi
grep -q '"phase":"done"' "$W/events.jsonl" || { echo "FAIL: the write did not finish"; exit 1; }
