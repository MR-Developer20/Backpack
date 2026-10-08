#!/bin/sh
# Download upstream .debs and apt keys declared in manifest/tools.yaml, verify sha256,
# and place them where live-build picks them up. Cached in build/cache/.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/build/cache"; mkdir -p "$CACHE" "$ROOT/live/config/packages.chroot" "$ROOT/live/config/archives"
python3 - "$ROOT/manifest/tools.yaml" "$ROOT" <<'PY' | while read -r kind id url sha; do
import sys, yaml
for t in yaml.safe_load(open(sys.argv[1]))["tools"]:
    s = t.get("source") or {}
    if "url" in s: print("deb", t["id"], s["url"], s["sha256"])
    if "apt_repo" in s:
        print("key", t["id"], s["apt_key_url"], s["apt_key_sha256"])
        open(f"{sys.argv[2]}/live/config/archives/{t['id']}.list", "w").write(s["apt_repo"] + "\n")
PY
  f="$CACHE/$(basename "$url")"
  [ -f "$f" ] || curl -sSLo "$f" "$url"
  echo "$sha  $f" | sha256sum -c --quiet || { echo "sha256 mismatch for $f"; exit 1; }
  case "$kind" in
    deb) cp "$f" "$ROOT/live/config/packages.chroot/"; echo "deb  $id -> packages.chroot/$(basename "$f")";;
    key) cp "$f" "$ROOT/live/config/archives/$id.key"; echo "key  $id -> archives/$id.key + $id.list";;
  esac
done
