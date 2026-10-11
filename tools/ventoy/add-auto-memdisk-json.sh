#!/bin/sh
apt-get update -qq >/dev/null 2>&1
apt-get install -y -q exfat-fuse fuse3 util-linux >/dev/null 2>&1
cd /work/build
IMG=ventoy-usb.img
losetup -D 2>/dev/null; sleep 1
LOOP=$(losetup --show -f -o 1048576 "$IMG")
mkdir -p /mnt/vtoy
mount.exfat-fuse "$LOOP" /mnt/vtoy
mkdir -p /mnt/vtoy/ventoy
cat > /mnt/vtoy/ventoy/ventoy.json <<'JSON'
{
    "auto_memdisk": [
        "/backpack.iso"
    ]
}
JSON
sync
echo "=== ventoy partition now:"; ls -la /mnt/vtoy/ /mnt/vtoy/ventoy/
echo "=== ventoy.json:"; cat /mnt/vtoy/ventoy/ventoy.json
fusermount3 -u /mnt/vtoy 2>/dev/null || umount /mnt/vtoy
losetup -d "$LOOP"
echo DONE
