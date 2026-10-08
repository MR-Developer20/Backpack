#!/bin/sh
# Build the eDEX-UI Debian package and stage it into live/config/packages.chroot/.
# Run from the repo root on the host (needs docker group); uses the nettoolkit-edex container.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm -v "$ROOT":/work -w /work/touchmode/edex nettoolkit-edex sh /work/build/tmpl/edex-deb.sh
# repack with trixie-correct ownership/deps into packages.chroot
D="$ROOT/touchmode/edex/dist/edex-ui_2.2.8_amd64.deb"
T="$(mktemp -d)"; dpkg-deb -R "$D" "$T/x"
sed -i 's/libgtk-3-0\b/libgtk-3-0t64/; s/libatspi2.0-0\b/libatspi2.0-0t64/' "$T/x/DEBIAN/control"
mkdir -p "$ROOT/live/config/packages.chroot"
dpkg-deb --build --root-owner-group "$T/x" "$ROOT/live/config/packages.chroot/edex-ui_2.2.8_amd64.deb"
rm -rf "$T"
