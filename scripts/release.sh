#!/bin/sh
# Stage the built ISO under build/release/ with a versioned name and SHA256SUMS.
# VERSION (e.g. the release tag) names the ISO; it defaults to the UTC date.
# EDITION=normal (default) stages build/backpack.iso as backpack-live-<version>-amd64.iso;
# EDITION=extras stages build/backpack-extras.iso as backpack-extras-<version>-amd64.iso
# (not backpack-live-*, so writers released before the editions keep downloading the normal one).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EDITION="${EDITION:-normal}"
DATE="$(date -u +%Y%m%d)"
case "$EDITION" in
  normal) ISO="$ROOT/build/backpack.iso";        NAME="backpack-live-${VERSION:-$DATE}-amd64.iso" ;;
  extras) ISO="$ROOT/build/backpack-extras.iso"; NAME="backpack-extras-${VERSION:-$DATE}-amd64.iso" ;;
  *) echo "EDITION must be normal or extras" >&2; exit 1 ;;
esac
[ -f "$ISO" ] || { echo "No ISO. Run 'make build EDITION=$EDITION' first." >&2; exit 1; }
OUT="$ROOT/build/release"
mkdir -p "$OUT"
cp -f "$ISO" "$OUT/$NAME"
cd "$OUT"
sha256sum *.iso > SHA256SUMS
SIZE=$(( $(stat -c%s "$NAME") / 1048576 ))
echo "Release staged in build/release/:"
echo "  $NAME  (${SIZE} MiB)"
echo "  SHA256SUMS:"
sed 's/^/    /' SHA256SUMS
