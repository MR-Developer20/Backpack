#!/bin/sh
# Build the Ventoy deliverable for NetToolkit Live.
#
# Ventoy's normal/grub2 modes cannot load the Debian trixie kernel's EFI image
# ("error: cannot load image"); only Ventoy memdisk mode works (it loads the whole ISO into
# RAM and boots the ISO's own bootloader). This script produces, under build/ventoy/:
#   1. nettoolkit-ventoy.iso  - the ISO with the `persistence` boot param stripped (memdisk runs
#      from RAM, so persistence does not apply), repacked fast with xorriso (boot records kept).
#   2. ventoy/ventoy.json     - a Ventoy auto_memdisk plugin config so the ISO boots straight into
#      memdisk mode with no manual menu picking.
#   3. README-VENTOY.txt      - drop-both-on-the-drive instructions.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/build/nettoolkit.iso}"
OUT="$ROOT/build/ventoy-dist"
ISONAME="nettoolkit-ventoy.iso"
DST="$OUT/$ISONAME"
[ -f "$SRC" ] || { echo "source ISO not found: $SRC (run make build first)" >&2; exit 1; }
mkdir -p "$OUT/ventoy"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. strip the persistence boot param (irrelevant under memdisk/RAM boot)
xorriso -osirrox on -indev "$SRC" \
  -extract /boot/grub/grub.cfg "$TMP/grub.cfg" \
  -extract /isolinux/live.cfg "$TMP/live.cfg" >/dev/null 2>&1
sed -i 's/ persistence//g' "$TMP/grub.cfg" "$TMP/live.cfg"
xorriso -indev "$SRC" -outdev "$DST" \
  -boot_image any replay -compliance no_emul_toc \
  -map "$TMP/grub.cfg" /boot/grub/grub.cfg \
  -map "$TMP/live.cfg" /isolinux/live.cfg >/dev/null 2>&1

# 2. Ventoy auto_memdisk plugin: force memdisk mode for this ISO (path is relative to the
#    Ventoy partition root; keep the ISO at the root of the Ventoy drive).
cat > "$OUT/ventoy/ventoy.json" <<JSON
{
    "auto_memdisk": [
        "/$ISONAME"
    ]
}
JSON

# 3. instructions
cat > "$OUT/README-VENTOY.txt" <<TXT
NetToolkit Live - Ventoy instructions
=====================================

Ventoy's normal and grub2 boot modes cannot load this image's kernel
("error: cannot load image"). Ventoy *memdisk* mode works. These files make
Ventoy boot NetToolkit in memdisk mode automatically.

Copy BOTH of these onto your Ventoy USB drive, keeping the paths:

  $ISONAME        -> the root of the Ventoy drive
  ventoy/ventoy.json          -> a "ventoy" folder at the root of the Ventoy drive

(If you already have a ventoy/ventoy.json with other plugins, merge the
"auto_memdisk" array into it instead of overwriting.)

Then boot the drive and pick NetToolkit. It goes straight to
"memdisk mode boot ... Loading ISO file to memory" and boots the desktop.
Your laptop needs ~1.5 GB of free RAM (the ISO is loaded into memory).

Note: memdisk runs entirely from RAM, so persistence is not available this way.
For persistence, write the ISO to a dedicated stick instead:  make mkusb DEV=/dev/sdX
TXT

echo "Ventoy deliverable in build/ventoy-dist/:"
echo "  $ISONAME  ($(( $(stat -c%s "$DST") / 1048576 )) MiB)"
echo "  ventoy/ventoy.json"
echo "  README-VENTOY.txt"
