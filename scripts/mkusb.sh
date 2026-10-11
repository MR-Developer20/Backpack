#!/bin/bash
# Write the Backpack ISO to a USB disk (or a raw image file) and add an ext4 persistence partition.
#
# Usage:
#   sudo mkusb.sh [--size 5G] [--dry-run] [--force] [--yes] [--iso FILE] /dev/sdX
#        mkusb.sh --image FILE [--image-size 8G] [--size 5G] [--dry-run] [--yes] [--iso FILE]
#
#   --size        persistence partition size (default 5G; sfdisk size syntax)
#   --image FILE  write to a raw disk image instead of a device (no root needed; used by QEMU tests)
#   --image-size  size of the image file to create (default 8G, sparse)
#   --dry-run     print the commands without running them
#   --force       allow disks larger than 256G (safety against wiping a data drive)
#   --yes         skip the interactive confirmation
#   --keep-persistence  (device mode) update the system only: rewrite the ISO, then restore the
#                 existing `persistence` partition at its old position WITHOUT formatting it
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISO="$ROOT/build/backpack.iso"; SIZE=5G; DRY=0; FORCE=0; YES=0; IMAGE=""; IMAGE_SIZE=8G; TARGET=""; KEEP=0
MAX_BYTES=$((256*1024*1024*1024))

while [ $# -gt 0 ]; do
  case "$1" in
    --size) SIZE="$2"; shift;; --dry-run) DRY=1;; --force) FORCE=1;; --yes) YES=1;;
    --iso) ISO="$2"; shift;; --image) IMAGE="$2"; shift;; --image-size) IMAGE_SIZE="$2"; shift;;
    --keep-persistence) KEEP=1;;
    -h|--help) sed -n '2,15p' "$0"; exit 0;;
    -*) echo "unknown option: $1" >&2; exit 2;;
    *) TARGET="$1";;
  esac; shift
done
[ -f "$ISO" ] || { echo "ISO not found: $ISO (run make build)" >&2; exit 2; }

run() { echo "+ $*"; [ $DRY = 1 ] || "$@"; }
run_sh() { echo "+ $1"; [ $DRY = 1 ] || bash -c "$1"; }

# persistence.conf: targeted union directories (not "/ union")
CONF_DIR="$(mktemp -d)"; trap 'rm -rf "$CONF_DIR"' EXIT
printf '%s\n' /home /var/lib/backpack /etc/NetworkManager > "$CONF_DIR/persistence.conf"

if [ -n "$IMAGE" ]; then
  # ---------------------------------------------------------------- image mode
  [ -z "$TARGET" ] || { echo "--image and a device are mutually exclusive" >&2; exit 2; }
  echo "Target: image file $IMAGE ($IMAGE_SIZE), persistence $SIZE"
  run mkdir -p "$(dirname "$IMAGE")"
  run rm -f "$IMAGE"
  run truncate -s "$IMAGE_SIZE" "$IMAGE"
  run_sh "dd if='$ISO' of='$IMAGE' bs=4M conv=notrunc status=none"
  run_sh "echo ',$SIZE,L' | sfdisk --quiet --append '$IMAGE'"
  if [ $DRY = 0 ]; then
    read -r START SECTORS < <(sfdisk --json "$IMAGE" | python3 -c 'import json,sys; p=json.load(sys.stdin)["partitiontable"]["partitions"][-1]; print(p["start"], p["size"])')
    run mkfs.ext4 -q -F -L persistence -E "offset=$((START*512))" -d "$CONF_DIR" "$IMAGE" "$((SECTORS/2))K"
  else
    echo "+ mkfs.ext4 -q -F -L persistence -E offset=<part3 start> -d <persistence.conf dir> $IMAGE <part3 size>"
  fi
  echo "Done: $IMAGE"; [ $DRY = 1 ] || sfdisk -l "$IMAGE" | tail -n 3
  exit 0
fi

# --------------------------------------------------------------------- device mode
[ -n "$TARGET" ] || { echo "usage: mkusb.sh [options] /dev/sdX   (or --image FILE)" >&2; exit 2; }
[ -b "$TARGET" ] || { echo "not a block device: $TARGET" >&2; exit 2; }
if [ $DRY = 0 ] && [ "$(id -u)" != 0 ]; then echo "device mode needs root (sudo)" >&2; exit 2; fi
TYPE="$(lsblk -dno TYPE "$TARGET")"; [ "$TYPE" = disk ] || { echo "$TARGET is a $TYPE, not a whole disk" >&2; exit 2; }
BYTES="$(lsblk -dnbo SIZE "$TARGET")"
if [ "$BYTES" -gt "$MAX_BYTES" ] && [ $FORCE = 0 ]; then
  echo "$TARGET is $((BYTES/1024/1024/1024)) GiB (> 256 GiB). Refusing without --force." >&2; exit 2
fi
if lsblk -no MOUNTPOINT "$TARGET" | grep -q .; then echo "$TARGET has mounted partitions; unmount first" >&2; exit 2; fi
ROOTDEV="$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true)"
[ "/dev/$ROOTDEV" != "$TARGET" ] || { echo "$TARGET holds the running system" >&2; exit 2; }

echo "Target device:"; lsblk -o NAME,SIZE,MODEL,TRAN,FSTYPE,LABEL,MOUNTPOINTS "$TARGET"
if [ $KEEP = 1 ]; then
  # locate the existing persistence partition; its start/size (512-byte sectors) come from sysfs
  PNAME="$(lsblk -nro NAME,LABEL "$TARGET" | awk '$2=="persistence"{print $1; exit}')"
  [ -n "$PNAME" ] || { echo "no partition labelled 'persistence' on $TARGET; run without --keep-persistence" >&2; exit 2; }
  P_START="$(cat "/sys/class/block/$PNAME/start")"; P_SIZE="$(cat "/sys/class/block/$PNAME/size")"
  ISO_SECTORS=$(( ($(stat -c %s "$ISO") + 511) / 512 ))
  if [ "$ISO_SECTORS" -gt "$P_START" ]; then
    echo "new ISO ($ISO_SECTORS sectors) would overlap the persistence partition (starts at $P_START)." >&2
    echo "Run without --keep-persistence (this erases persistence)." >&2; exit 2
  fi
  echo "System on $TARGET will be replaced. Persistence /dev/$PNAME (start $P_START, $((P_SIZE/2048)) MiB) is KEPT."
else
  echo "Everything on $TARGET will be erased. ISO: $ISO, persistence: $SIZE"
fi
if [ $YES = 0 ] && [ $DRY = 0 ]; then
  read -r -p "Type the device name ($TARGET) to continue: " ANSWER
  [ "$ANSWER" = "$TARGET" ] || { echo "aborted"; exit 1; }
fi
run_sh "dd if='$ISO' of='$TARGET' bs=4M conv=fsync status=progress"
if [ $KEEP = 1 ]; then
  run_sh "echo '$P_START,$P_SIZE,L' | sfdisk --quiet --append '$TARGET'"
else
  run_sh "echo ',$SIZE,L' | sfdisk --quiet --append '$TARGET'"
fi
# Re-read the partition table. partprobe warns + exits non-zero on an isohybrid ISO's fake
# 2048-byte block descriptor, which is harmless (sfdisk already wrote the table) — tolerate it.
echo "+ partprobe $TARGET (re-read partition table)"
if [ $DRY = 0 ]; then
  partprobe "$TARGET" 2>/dev/null || partx -u "$TARGET" 2>/dev/null || blockdev --rereadpt "$TARGET" 2>/dev/null || true
  udevadm settle 2>/dev/null || true
fi
if [ $DRY = 0 ]; then
  PART="$(sfdisk --json "$TARGET" | python3 -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][-1]["node"])')"
  for _ in $(seq 1 10); do [ -b "$PART" ] && break; sleep 1; done
  if [ $KEEP = 1 ]; then
    LBL="$(blkid -s LABEL -o value "$PART" 2>/dev/null || true)"
    [ "$LBL" = persistence ] && echo "persistence kept on $PART" || { echo "WARNING: $PART label is '$LBL', expected 'persistence'" >&2; exit 1; }
  else
    run mkfs.ext4 -q -F -L persistence -d "$CONF_DIR" "$PART"
  fi
  run sync
else
  echo "+ mkfs.ext4 -q -F -L persistence -d <persistence.conf dir> ${TARGET}<3>"
fi
echo "Done. You can remove $TARGET."
