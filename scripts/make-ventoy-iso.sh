#!/bin/sh
# Produce a persistence-free variant of the ISO (for Ventoy / pure live use) by stripping the
# `persistence` boot parameter from the GRUB (UEFI) and isolinux (BIOS) menus. Fast in-place
# repack with xorriso; the El Torito / isohybrid boot records are preserved.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/build/nettoolkit.iso}"
DST="${2:-$ROOT/build/nettoolkit-ventoy.iso}"
[ -f "$SRC" ] || { echo "source ISO not found: $SRC" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
xorriso -osirrox on -indev "$SRC" \
  -extract /boot/grub/grub.cfg "$TMP/grub.cfg" \
  -extract /isolinux/live.cfg "$TMP/live.cfg" >/dev/null 2>&1
sed -i 's/ persistence//g' "$TMP/grub.cfg" "$TMP/live.cfg"
echo "persistence refs after strip (expect 0): grub=$(grep -c persistence "$TMP/grub.cfg") live=$(grep -c persistence "$TMP/live.cfg")"
xorriso -indev "$SRC" -outdev "$DST" \
  -boot_image any replay \
  -compliance no_emul_toc \
  -map "$TMP/grub.cfg" /boot/grub/grub.cfg \
  -map "$TMP/live.cfg" /isolinux/live.cfg >/dev/null 2>&1
echo "wrote $DST ($(( $(stat -c%s "$DST") / 1048576 )) MiB)"
