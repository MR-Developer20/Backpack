#!/bin/sh
# Stage the built ISO under build/release/ with a version-dated name and SHA256SUMS.
# VERSION=1.2.3 (or v1.2.3) names it backpack-live-1.2.3-amd64.iso instead of the UTC date.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISO="$ROOT/build/backpack.iso"
[ -f "$ISO" ] || { echo "No ISO. Run 'make build' first." >&2; exit 1; }
VER="${VERSION:-$(date -u +%Y%m%d)}"; VER="${VER#v}"
OUT="$ROOT/build/release"
NAME="backpack-live-${VER}-amd64.iso"
mkdir -p "$OUT"
cp -f "$ISO" "$OUT/$NAME"
cd "$OUT"
sha256sum "$NAME" > SHA256SUMS
SIZE=$(( $(stat -c%s "$NAME") / 1048576 ))
echo "Release staged in build/release/:"
echo "  $NAME  (${SIZE} MiB)"
echo "  SHA256SUMS:"
sed 's/^/    /' SHA256SUMS
