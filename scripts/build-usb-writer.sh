#!/bin/sh
# Package the GTK USB writer (scripts/mkusb-gui.py + scripts/mkusb.sh) as a .deb and an AppImage
# into build/dist/. VERSION (e.g. 1.2.0, from the release tag) defaults to 0.0.0+<UTC timestamp>.
# The AppImage step downloads a pinned appimagetool into build/cache/; SKIP_APPIMAGE=1 skips it.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tools/usb-writer"; OUT="$ROOT/build/dist"
VER="${VERSION:-0.0.0+$(date -u +%Y%m%d%H%M%S)}"; VER="${VER#v}"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
APPIMAGETOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
mkdir -p "$OUT"

# stage: same relative layout as the repo, so mkusb-gui.py finds scripts/mkusb.sh next to itself
stage() {
  install -d "$1/usr/share/backpack-usb-writer/scripts" "$1/usr/share/applications" \
    "$1/usr/share/icons/hicolor/scalable/apps"
  install -m755 "$ROOT/scripts/mkusb-gui.py" "$ROOT/scripts/mkusb.sh" "$1/usr/share/backpack-usb-writer/scripts/"
  install -m644 "$SRC/live.backpack.UsbWriter.desktop" "$1/usr/share/applications/"
  install -m644 "$SRC/backpack-usb-writer.svg" "$1/usr/share/icons/hicolor/scalable/apps/"
}

# ------------------------------------------------------------------------------ .deb
DEB="$ROOT/build/deb/backpack-usb-writer"
rm -rf "$DEB"; stage "$DEB"; install -d "$DEB/DEBIAN" "$DEB/usr/bin"
printf '#!/bin/sh\nexec python3 /usr/share/backpack-usb-writer/scripts/mkusb-gui.py "$@"\n' > "$DEB/usr/bin/backpack-usb-writer"
chmod 755 "$DEB/usr/bin/backpack-usb-writer"
cat > "$DEB/DEBIAN/control" <<CTL
Package: backpack-usb-writer
Version: $VER
Section: admin
Priority: optional
Architecture: all
Maintainer: Backpack Live <backpack@localhost>
Depends: python3, python3-gi, gir1.2-gtk-4.0, pkexec | policykit-1, udisks2, util-linux, fdisk, e2fsprogs, coreutils
Recommends: parted
Description: Backpack Live USB writer
 GTK front-end that writes the Backpack Live ISO to a USB drive and adds an
 ext4 persistence partition, or updates the system while keeping persistence.
CTL
rm -f "$OUT"/backpack-usb-writer_*.deb
dpkg-deb --build --root-owner-group "$DEB" "$OUT/backpack-usb-writer_${VER}_all.deb" >/dev/null
ls -l "$OUT/backpack-usb-writer_${VER}_all.deb"

# -------------------------------------------------------------------------- AppImage
[ "${SKIP_APPIMAGE:-0}" = 1 ] && exit 0
TOOL="$ROOT/build/cache/appimagetool-1.9.1-x86_64.AppImage"; mkdir -p "$ROOT/build/cache"
[ -f "$TOOL" ] || curl -fsSLo "$TOOL" "$APPIMAGETOOL_URL" || { rm -f "$TOOL"; exit 1; }
echo "$APPIMAGETOOL_SHA256  $TOOL" | sha256sum -c --quiet || { echo "appimagetool sha256 mismatch (removed)" >&2; rm -f "$TOOL"; exit 1; }
chmod +x "$TOOL"
APPDIR="$ROOT/build/appimage/BackpackUsbWriter.AppDir"
rm -rf "$APPDIR"; stage "$APPDIR"
install -m755 "$SRC/AppRun" "$APPDIR/AppRun"
cp "$SRC/live.backpack.UsbWriter.desktop" "$SRC/backpack-usb-writer.svg" "$APPDIR/"
ln -s backpack-usb-writer.svg "$APPDIR/.DirIcon"
IMG="$OUT/Backpack_USB_Writer-${VER}-x86_64.AppImage"
rm -f "$OUT"/Backpack_USB_Writer-*.AppImage
# extract-and-run: CI runners and containers have no FUSE
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 VERSION="$VER" "$TOOL" --no-appstream "$APPDIR" "$IMG" >/dev/null 2>&1 \
  || { ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 VERSION="$VER" "$TOOL" --no-appstream "$APPDIR" "$IMG"; exit 1; }
ls -l "$IMG"
