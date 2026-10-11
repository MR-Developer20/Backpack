#!/bin/sh
apt-get update -qq >/dev/null 2>&1
apt-get install -y -q exfat-fuse fuse3 util-linux >/dev/null 2>&1
cd /work/build
IMG=ventoy-usb.img
losetup -D 2>/dev/null   # free any leaked loops
sleep 1
LOOP=$(losetup --show -f -o 1048576 "$IMG")   # exFAT data partition starts at 1 MiB
echo "loop=$LOOP"; ls -l "$LOOP" 2>&1
mkdir -p /mnt/vtoy
if mount.exfat-fuse "$LOOP" /mnt/vtoy 2>/tmp/e; then
  echo "mounted"; cp /work/build/backpack.iso /mnt/vtoy/; sync; ls -l /mnt/vtoy/
  fusermount3 -u /mnt/vtoy 2>/dev/null || umount /mnt/vtoy
  echo "COPY-OK"
else
  echo "mount failed:"; cat /tmp/e
fi
losetup -d "$LOOP" 2>/dev/null
chown $(stat -c %u /work/build):$(stat -c %g /work/build) "$IMG"
