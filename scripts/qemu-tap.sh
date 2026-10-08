#!/bin/bash
# Tap at screen pixel X Y in the running QEMU guest.
# Default: QEMU monitor mouse_move/mouse_button on the active absolute pointer (virtio tablet; the
#          harness disables vmport so vmmouse cannot steal absolute events).
# --sway:  synthesize the click inside the guest via swaymsg over the serial console (needs --console).
# Usage: qemu-tap.sh [--sway] X Y [screen_w screen_h]   (defaults 1280x800)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SOCK="${QEMU_MON:-$ROOT/build/qemu-mon.sock}"
MODE=mon; [ "${1:-}" = "--sway" ] && { MODE=sway; shift; }
X=$1; Y=$2; W=${3:-1280}; H=${4:-800}
if [ $MODE = sway ]; then
  "$ROOT/scripts/qemu-serial.sh" "swaymsg seat - cursor set $X $Y; swaymsg seat - cursor press button1; swaymsg seat - cursor release button1" >/dev/null
  sleep 0.5; exit 0
fi
ax=$(( X * 32767 / W )); ay=$(( Y * 32767 / H ))
mon() { echo "$1" | socat - "UNIX-CONNECT:$SOCK" >/dev/null; sleep 0.15; }
IDX=$(echo "info mice" | socat - "UNIX-CONNECT:$SOCK" | tr -d '\r' | sed -n 's/.*Mouse #\([0-9]*\): QEMU Virtio Tablet.*/\1/p' | head -1)
[ -n "$IDX" ] && mon "mouse_set $IDX"
mon "mouse_move $ax $ay"; mon "mouse_move $((ax+1)) $ay"; mon "mouse_button 1"; mon "mouse_button 0"
