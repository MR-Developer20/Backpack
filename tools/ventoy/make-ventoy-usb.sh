#!/bin/sh
set -e
apt-get update -qq >/dev/null 2>&1
apt-get install -y -q exfatprogs exfat-fuse dosfstools util-linux parted >/dev/null 2>&1
cd /work/build
IMG=ventoy-usb.img
rm -f "$IMG"
truncate -s 3G "$IMG"
LOOP=$(losetup --show -f -P "$IMG")
echo "loop=$LOOP"
# Install Ventoy (force, non-interactive). -I = force install (wipes), -g = GPT layout (UEFI)
cd ventoy/ventoy-1.1.17
echo "=== Ventoy2Disk install:"
yes | sh Ventoy2Disk.sh -I -g "$LOOP" 2>&1 | tail -n 15 || { echo "install rc=$?"; }
cd /work/build
partprobe "$LOOP" 2>/dev/null || true
sleep 2
losetup -d "$LOOP"
# re-attach to see new partitions
LOOP=$(losetup --show -f -P "$IMG")
echo "=== partitions:"; lsblk -o NAME,SIZE,FSTYPE,LABEL "$LOOP" 2>/dev/null || parted -s "$IMG" print 2>/dev/null
# mount the Ventoy data partition (p1, exFAT) and copy the ISO
mkdir -p /mnt/vtoy
mount "${LOOP}p1" /mnt/vtoy 2>&1 || mount -t exfat "${LOOP}p1" /mnt/vtoy
cp /work/build/nettoolkit.iso /mnt/vtoy/
sync
echo "=== copied ISO:"; ls -l /mnt/vtoy/
umount /mnt/vtoy
losetup -d "$LOOP"
chown $(stat -c %u /work/build):$(stat -c %g /work/build) "$IMG"
echo "=== ventoy-usb.img ready: $(stat -c%s $IMG) bytes"
