#!/bin/sh
# Stage the built ISO under build/release/ with a version-dated name and SHA256SUMS.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISO="$ROOT/build/nettoolkit.iso"
[ -f "$ISO" ] || { echo "No ISO. Run 'make build' first." >&2; exit 1; }
DATE="$(date -u +%Y%m%d)"
OUT="$ROOT/build/release"
NAME="nettoolkit-live-${DATE}-amd64.iso"
mkdir -p "$OUT"
cp -f "$ISO" "$OUT/$NAME"
cd "$OUT"
sha256sum "$NAME" > SHA256SUMS
SIZE=$(( $(stat -c%s "$NAME") / 1048576 ))
echo "Release staged in build/release/:"
echo "  $NAME  (${SIZE} MiB)"
echo "  SHA256SUMS:"
sed 's/^/    /' SHA256SUMS
