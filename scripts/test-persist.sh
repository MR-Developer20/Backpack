#!/bin/bash
# Persistence test matrix: for BIOS and UEFI, boot a fresh USB image 3 times:
#   1. normal boot  -> expect PERSIST-MARKER-CREATED
#   2. normal boot  -> expect PERSIST-MARKER-FOUND
#   3. toram boot   -> expect PERSIST-MARKER-FOUND and /home on the persistence device
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; IMG="$ROOT/build/test-usb.img"; T="$ROOT/scripts/test-qemu.sh"
pass=0; fail=0
check() { # check TAG EXPECT
  if grep -q "$2" "$ROOT/build/logs/serial-$1.log" && grep -q BACKPACK-SELFTEST-DONE "$ROOT/build/logs/serial-$1.log"; then
    echo "PASS $1: $2 ($(grep -o 'HOME-MOUNT: .*' "$ROOT/build/logs/serial-$1.log"))"; pass=$((pass+1))
  else echo "FAIL $1: expected $2"; grep -E 'PERSIST|HOME-MOUNT|STATE' "$ROOT/build/logs/serial-$1.log" | head -n 4; fail=$((fail+1)); fi
}
for fw in bios uefi; do
  U=""; [ $fw = uefi ] && U="--uefi"
  "$ROOT/scripts/mkusb.sh" --image "$IMG" --yes >/dev/null
  "$T" --headless $U --disk "$IMG" --tag "persist-$fw-1" --timeout 300 >/dev/null 2>&1; check "persist-$fw-1" PERSIST-MARKER-CREATED
  "$T" --headless $U --disk "$IMG" --tag "persist-$fw-2" --timeout 300 >/dev/null 2>&1; check "persist-$fw-2" PERSIST-MARKER-FOUND
  "$T" --headless $U --disk "$IMG" --direct --append toram --tag "persist-$fw-toram" --timeout 300 >/dev/null 2>&1; check "persist-$fw-toram" PERSIST-MARKER-FOUND
done
echo "persistence: $pass passed, $fail failed"; [ $fail = 0 ]
