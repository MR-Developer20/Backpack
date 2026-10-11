#!/bin/sh
# Build backpack-mkusb_<ver>_all.deb: the USB writer (scripts/mkusb.sh) + its GTK4 GUI
# (scripts/mkusb-gui.py), installable on any Debian/Ubuntu desktop without a repo checkout.
#
#   scripts/build-mkusb-deb.sh [OUTDIR]        -> OUTDIR/backpack-mkusb_<ver>_all.deb (default build/)
#   VERSION=1.2.3 scripts/build-mkusb-deb.sh   -> use that version instead of <__version__>+<UTC stamp>
#
# Installs: /usr/libexec/backpack/mkusb.sh, /usr/bin/backpack-mkusb (CLI), /usr/bin/backpack-mkusb-gui,
# a desktop entry and a polkit action so pkexec shows a Backpack-specific password prompt.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build}"
BASEVER="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$ROOT/scripts/mkusb-gui.py")"
VER="${VERSION:-${BASEVER}+$(date -u +%Y%m%d%H%M%S)}"
VER="${VER#v}"
STAGE="$ROOT/build/deb/backpack-mkusb"
rm -rf "$STAGE"; mkdir -p "$STAGE/DEBIAN" "$OUT"
install -d "$STAGE/usr/libexec/backpack" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/polkit-1/actions" "$STAGE/usr/share/doc/backpack-mkusb"
install -m755 "$ROOT/scripts/mkusb.sh" "$STAGE/usr/libexec/backpack/mkusb.sh"
install -m755 "$ROOT/scripts/mkusb-gui.py" "$STAGE/usr/bin/backpack-mkusb-gui"
ln -s ../libexec/backpack/mkusb.sh "$STAGE/usr/bin/backpack-mkusb"
install -m644 "$ROOT/mkusb/backpack-mkusb.desktop" "$STAGE/usr/share/applications/"
install -m644 "$ROOT/mkusb/live.backpack.mkusb.policy" "$STAGE/usr/share/polkit-1/actions/"
cat > "$STAGE/usr/share/doc/backpack-mkusb/README" <<TXT
backpack-mkusb $VER

  backpack-mkusb-gui                      pick an ISO and a USB stick, write (password via pkexec)
  sudo backpack-mkusb --iso FILE /dev/sdX  command line; --size 10G, --keep-persistence, --dry-run
  sudo backpack-mkusb --help

Both write the ISO, then add an ext4 partition labelled "persistence" (default 5 GB) so
/home, /var/lib/backpack and /etc/NetworkManager survive reboots. --keep-persistence replaces
only the system and leaves the existing persistence partition untouched.
TXT
cat > "$STAGE/DEBIAN/control" <<CTL
Package: backpack-mkusb
Version: $VER
Section: utils
Priority: optional
Architecture: all
Maintainer: Backpack Live <backpack@localhost>
Depends: python3, python3-gi, gir1.2-gtk-4.0, polkitd, pkexec, udisks2, util-linux, e2fsprogs, coreutils
Recommends: parted
Description: Backpack Live USB writer (command line + GTK4 GUI)
 Writes a Backpack Live ISO to a USB stick and adds an ext4 persistence
 partition; can also update the live system while keeping persistence.
 The GUI lists only removable disks and runs the writer through pkexec.
CTL
rm -f "$OUT"/backpack-mkusb_*.deb
dpkg-deb --build --root-owner-group "$STAGE" "$OUT/backpack-mkusb_${VER}_all.deb" >/dev/null
ls -l "$OUT/backpack-mkusb_${VER}_all.deb"
