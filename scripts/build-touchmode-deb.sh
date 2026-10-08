#!/bin/sh
# Build nettoolkit-touch_<ver>_all.deb (pure Python, no compile) into live/config/packages.chroot/.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/touchmode"; BASEVER="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$SRC/nettoolkit_touch/__init__.py")"
VER="${BASEVER}+$(date -u +%Y%m%d%H%M%S)"
STAGE="$ROOT/build/deb/nettoolkit-touch"; OUT="$ROOT/live/config/packages.chroot"
rm -rf "$STAGE"; mkdir -p "$STAGE/DEBIAN" "$OUT"
install -d "$STAGE/usr/lib/python3/dist-packages" "$STAGE/usr/bin" "$STAGE/usr/lib/nettoolkit" \
  "$STAGE/etc/nettoolkit" "$STAGE/usr/share/wayland-sessions" "$STAGE/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"
cp -r "$SRC/nettoolkit_touch" "$STAGE/usr/lib/python3/dist-packages/"
find "$STAGE/usr/lib/python3" -name __pycache__ -prune -exec rm -rf {} +
install -m755 "$SRC/bin/nettoolkit-touch" "$SRC/bin/nettoolkit-touch-session" "$STAGE/usr/bin/"
install -m755 "$SRC/bin/nettoolkit-ui" "$STAGE/usr/lib/nettoolkit/"
install -m644 "$SRC/etc/sway.config" "$STAGE/etc/nettoolkit/"
install -m644 "$SRC/etc/nettoolkit-touch.desktop" "$STAGE/usr/share/wayland-sessions/"
install -m644 "$SRC/etc/nettoolkit-ui.service" "$STAGE/lib/systemd/system/"
ln -s /lib/systemd/system/nettoolkit-ui.service "$STAGE/etc/systemd/system/multi-user.target.wants/nettoolkit-ui.service"
cat > "$STAGE/DEBIAN/control" <<CTL
Package: nettoolkit-touch
Version: $VER
Section: net
Priority: optional
Architecture: all
Maintainer: NetToolkit Live <nettoolkit@localhost>
Depends: python3, python3-yaml, python3-pyside6.qtcore, python3-pyside6.qtgui, python3-pyside6.qtqml, python3-pyside6.qtquick, python3-pyside6.qtquickcontrols2, qml6-module-qtquick, qml6-module-qtquick-controls, qml6-module-qtquick-layouts, qml6-module-qtquick-window, qml6-module-qtquick-templates, qml6-module-qtqml, qml6-module-qtqml-workerscript, qt6-wayland, sway, foot, fonts-dejavu-core
Description: NetToolkit Live Touch Mode launcher
 Full-screen tile launcher for the tools in /etc/nettoolkit/tools.yaml, running
 as a locked-down sway Wayland session selected with nettoolkit.ui=touch.
CTL
echo "/etc/nettoolkit/sway.config" > "$STAGE/DEBIAN/conffiles"
rm -f "$OUT"/nettoolkit-touch_*.deb
dpkg-deb --build --root-owner-group "$STAGE" "$OUT/nettoolkit-touch_${VER}_all.deb" >/dev/null
ls -l "$OUT/nettoolkit-touch_${VER}_all.deb"
