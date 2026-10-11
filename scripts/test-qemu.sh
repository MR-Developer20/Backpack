#!/bin/bash
# Boot the Backpack ISO (or a USB disk image) in QEMU and wait for the in-guest self-test marker.
# Usage: test-qemu.sh [--uefi] [--headless] [--touch] [--direct] [--append "params"]
#                     [--disk FILE] [--iso FILE] [--timeout SEC] [--tag NAME] [--keep-alive SEC]
#   --direct   boot kernel/initrd extracted from the ISO with `boot=live components <append>`;
#              the way to select toram / backpack.ui=touch without driving the boot menu
#   --console  (with --direct) add console=ttyS0 so a login shell is reachable on the serial socket:
#              scripts/qemu-serial.sh 'command' sends a line; output appears in the serial log
#   --disk     boot from a raw disk image (e.g. build/test-usb.img) instead of the ISO; the guest
#              is shut down gracefully so the persistence partition is flushed
# Exit 0 when BACKPACK-SELFTEST-DONE appears on the serial log before the timeout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISO="$ROOT/build/backpack.iso"; DISK=""; UEFI=0; HEADLESS=0; TOUCH=0; DIRECT=0
APPEND=""; TIMEOUT=300; TAG=""; KEEP=0; CONSOLE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --uefi) UEFI=1;; --headless) HEADLESS=1;; --touch) TOUCH=1;; --direct) DIRECT=1;;
    --append) APPEND="$2"; shift;; --disk) DISK="$2"; shift;; --iso) ISO="$2"; shift;;
    --timeout) TIMEOUT="$2"; shift;; --tag) TAG="$2"; shift;; --keep-alive) KEEP="$2"; shift;;
    --console) CONSOLE=1;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac; shift
done
[ -f "$ISO" ] || { echo "missing ISO: $ISO" >&2; exit 2; }
[ -z "$DISK" ] || [ -f "$DISK" ] || { echo "missing disk: $DISK" >&2; exit 2; }
if [ -z "$TAG" ]; then
  TAG=bios; [ $UEFI = 1 ] && TAG=uefi
  [ $DIRECT = 1 ] && TAG="$TAG-direct"
fi

B="$ROOT/build"; LOG="$B/logs/serial-$TAG.log"; MON="$B/qemu-mon.sock"; SHOTS="$B/shots"
mkdir -p "$B/logs" "$SHOTS" "$B/direct"; : > "$LOG"; rm -f "$MON"

SER="$B/qemu-serial.sock"; rm -f "$SER"
# serial port: unix socket (drive it with scripts/qemu-serial.sh) + logfile that the marker check reads
Q=(qemu-system-x86_64 -m 3G -smp 2 -nic user,model=virtio-net-pci
   -chardev "socket,id=ser0,path=$SER,server=on,wait=off,logfile=$LOG" -serial chardev:ser0
   -monitor "unix:$MON,server,nowait" -qmp "unix:$B/qemu-qmp.sock,server,nowait" -no-reboot)
if [ -w /dev/kvm ]; then Q+=(-enable-kvm -cpu host); else Q+=(-cpu max); echo "warn: no KVM, using TCG (slow)"; fi
# headless still needs a display backend for monitor input injection (sendkey/mouse_move): loopback VNC
[ $HEADLESS = 1 ] && Q+=(-display "vnc=127.0.0.1:${QEMU_VNC_DISPLAY:-9},to=99") || Q+=(-display gtk)
# QEMU_RES=WxH sets the virtio-vga native mode (e.g. 800x1280 to boot a portrait screen)
VGA=virtio-vga; [ -n "${QEMU_RES:-}" ] && VGA="virtio-vga,xres=${QEMU_RES%x*},yres=${QEMU_RES#*x}"
[ $TOUCH = 1 ] && Q+=(-device "$VGA" -device virtio-tablet-pci,id=tablet0 -machine vmport=off) || Q+=(-vga std)

if [ $UEFI = 1 ]; then
  CODE=""; VARS=""
  for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd; do [ -f "$c" ] && { CODE="$c"; break; }; done
  for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do [ -f "$v" ] && { VARS="$v"; break; }; done
  [ -n "$CODE" ] || { echo "OVMF not found (apt install ovmf)" >&2; exit 2; }
  Q+=(-drive "if=pflash,format=raw,readonly=on,file=$CODE")
  if [ -n "$VARS" ]; then cp "$VARS" "$B/ovmf-vars-$TAG.fd"; Q+=(-drive "if=pflash,format=raw,file=$B/ovmf-vars-$TAG.fd"); fi
fi

if [ -n "$DISK" ]; then
  Q+=(-drive "file=$DISK,format=raw,if=virtio" -boot c)
else
  Q+=(-drive "file=$ISO,media=cdrom,readonly=on" -boot d)
fi
if [ $DIRECT = 1 ]; then
  if [ ! -f "$B/direct/vmlinuz" ] || [ "$ISO" -nt "$B/direct/vmlinuz" ]; then
    xorriso -osirrox on -indev "$ISO" -extract /live/vmlinuz "$B/direct/vmlinuz" \
            -extract /live/initrd.img "$B/direct/initrd.img" >/dev/null 2>&1
  fi
  BASE_APPEND="$(sed -n 's/^LB_BOOTAPPEND_LIVE="\(.*\)"$/\1/p' "$ROOT/live/config/binary" 2>/dev/null)"
  [ -n "$BASE_APPEND" ] || BASE_APPEND="boot=live components quiet persistence"
  [ $CONSOLE = 1 ] && APPEND="$APPEND console=tty0 console=ttyS0,115200"   # getty on the serial socket
  Q+=(-kernel "$B/direct/vmlinuz" -initrd "$B/direct/initrd.img" -append "$BASE_APPEND $APPEND")
fi

mon() { echo "$1" | socat - "UNIX-CONNECT:$MON" >/dev/null 2>&1 || true; }
shot() { # shot NAME
  mon "screendump $SHOTS/$1.ppm"; sleep 1
  command -v pnmtopng >/dev/null && [ -s "$SHOTS/$1.ppm" ] && pnmtopng "$SHOTS/$1.ppm" > "$SHOTS/$1.png" 2>/dev/null && rm -f "$SHOTS/$1.ppm"
  return 0
}

"${Q[@]}" >"$B/logs/qemu-$TAG.out" 2>&1 &
QPID=$!
rc=1; start=$SECONDS
while kill -0 $QPID 2>/dev/null && [ $((SECONDS-start)) -lt "$TIMEOUT" ]; do
  if grep -q BACKPACK-SELFTEST-DONE "$LOG"; then rc=0; break; fi
  sleep 2
done
if [ $rc = 0 ]; then sleep 3; shot "$TAG"; [ "$KEEP" -gt 0 ] && sleep "$KEEP"; shot "$TAG-final"; else shot "$TAG-FAIL"; fi
if kill -0 $QPID 2>/dev/null; then
  if [ -n "$DISK" ] || [ $rc = 0 ]; then
    mon system_powerdown
    for _ in $(seq 1 30); do kill -0 $QPID 2>/dev/null || break; sleep 2; done
  fi
  kill -0 $QPID 2>/dev/null && { mon quit; sleep 1; kill $QPID 2>/dev/null || true; }
fi
wait $QPID 2>/dev/null || true

echo "== $TAG: $([ $rc = 0 ] && echo PASS || echo FAIL) (${SECONDS}s elapsed, log: ${LOG#$ROOT/})"
grep -E '^(STATE|BOOTTIME|TOOLS|MISSING|FAILED-UNIT|LIVE-USER|DESKTOP-SESSION|TOUCH-SESSION|TOUCH-CONF|SWAY-INPUT|SWAY-LOG|PERSIST-MARKER|HOME-MOUNT|CMDLINE)' "$LOG" || tail -n 5 "$LOG"
exit $rc
