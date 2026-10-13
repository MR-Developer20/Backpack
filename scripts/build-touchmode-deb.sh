#!/bin/sh
# Build backpack-touch_<ver>_all.deb (pure Python, no compile) into live/config/packages.chroot/.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/touchmode"; BASEVER="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$SRC/backpack_touch/__init__.py")"
VER="${BASEVER}+$(date -u +%Y%m%d%H%M%S)"
STAGE="$ROOT/build/deb/backpack-touch"; OUT="$ROOT/live/config/packages.chroot"
rm -rf "$STAGE"; mkdir -p "$STAGE/DEBIAN" "$OUT"
install -d "$STAGE/usr/lib/python3/dist-packages" "$STAGE/usr/bin" "$STAGE/usr/lib/backpack" \
  "$STAGE/etc/backpack" "$STAGE/usr/share/wayland-sessions" "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"
cp -r "$SRC/backpack_touch" "$STAGE/usr/lib/python3/dist-packages/"
find "$STAGE/usr/lib/python3" -name __pycache__ -prune -exec rm -rf {} +
install -m755 "$SRC/bin/backpack-touch" "$SRC/bin/backpack-touch-session" "$SRC/bin/backpack-cli-mode" "$STAGE/usr/bin/"
install -m755 "$SRC/bin/backpack-ui" "$STAGE/usr/lib/backpack/"
install -m644 "$SRC/etc/sway.config" "$STAGE/etc/backpack/"
install -m644 "$SRC/etc/backpack-touch.desktop" "$STAGE/usr/share/wayland-sessions/"
install -m644 "$SRC/etc/backpack-ui.service" "$STAGE/usr/lib/systemd/system/"
ln -s /usr/lib/systemd/system/backpack-ui.service "$STAGE/etc/systemd/system/multi-user.target.wants/backpack-ui.service"
cat > "$STAGE/DEBIAN/control" <<CTL
Package: backpack-touch
Version: $VER
Section: net
Priority: optional
Architecture: all
Maintainer: Backpack Live <backpack@localhost>
Depends: python3, python3-yaml, python3-pyside6.qtcore, python3-pyside6.qtgui, python3-pyside6.qtqml, python3-pyside6.qtquick, python3-pyside6.qtquickcontrols2, qml6-module-qtquick, qml6-module-qtquick-controls, qml6-module-qtquick-layouts, qml6-module-qtquick-window, qml6-module-qtquick-templates, qml6-module-qtqml, qml6-module-qtqml-workerscript, qt6-wayland, sway, foot, wvkbd, fonts-dejavu-core, fonts-jetbrains-mono, qml6-module-qtquick-shapes, dmidecode
Description: Backpack Live GUI Mode launcher
 Full-screen tile launcher for the tools in /etc/backpack/tools.yaml, running
 as a locked-down sway Wayland session (the "GUI Mode" boot entry, backpack.ui=touch).
CTL
echo "/etc/backpack/sway.config" > "$STAGE/DEBIAN/conffiles"
rm -f "$OUT"/backpack-touch_*.deb
dpkg-deb --build --root-owner-group "$STAGE" "$OUT/backpack-touch_${VER}_all.deb" >/dev/null
ls -l "$OUT/backpack-touch_${VER}_all.deb"
