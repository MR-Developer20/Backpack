#!/bin/bash
# Boot a copy-to-RAM entry and screenshot the plymouth splash every 2 s so the progress bar can be
# inspected: build/shots/toram-NN.png. Ends when the live system's self-test marker appears.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
rm -f build/qemu-*.sock build/logs/serial-toram.log build/shots/toram-*.png
nohup scripts/test-qemu.sh --headless --direct --append "toram" --tag toram --timeout 300 --keep-alive 10 > build/logs/toram-run.out 2>&1 &
until [ -S build/qemu-mon.sock ]; do sleep 1; done
i=0
while ! grep -q NETTOOLKIT-SELFTEST-DONE build/logs/serial-toram.log 2>/dev/null && [ $i -lt 60 ]; do
  i=$((i+1)); n=$(printf '%02d' $i)
  echo "screendump $ROOT/build/shots/toram-$n.ppm" | socat -t3 - UNIX-CONNECT:build/qemu-mon.sock >/dev/null 2>&1
  sleep 2
done
for f in build/shots/toram-*.ppm; do [ -s "$f" ] && pnmtopng "$f" > "${f%.ppm}.png" 2>/dev/null; rm -f "$f"; done
echo "captured $(ls build/shots/toram-*.png 2>/dev/null | wc -l) frames; boot: $(grep -ho 'BOOTTIME.*' build/logs/serial-toram.log | head -1)"
