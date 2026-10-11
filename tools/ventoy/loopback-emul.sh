#!/bin/sh
set -e
apt-get update -qq >/dev/null 2>&1
apt-get install -y -q grub-efi-amd64-bin grub-common mtools dosfstools >/dev/null 2>&1
echo "grub tools installed"
cd /work/build
cat > vtgrub.cfg <<'CFG'
set timeout=3
insmod part_gpt
insmod fat
insmod iso9660
insmod loopback
insmod search
insmod echo
insmod normal
search --no-floppy --set=vtroot --file /backpack.iso
echo "vtroot=$vtroot"
loopback loop ($vtroot)/backpack.iso
set root=(loop)
set iso_path=/backpack.iso
export iso_path
echo "sourcing loopback.cfg from (loop)..."
source (loop)/boot/grub/loopback.cfg
echo "loopback.cfg returned"
sleep 10
CFG
grub-mkstandalone -O x86_64-efi -o BOOTX64.EFI \
  --modules="part_gpt part_msdos fat iso9660 loopback search search_fs_file normal echo linux configfile gfxterm all_video png" \
  "boot/grub/grub.cfg=vtgrub.cfg"
echo "grub efi built: $(stat -c%s BOOTX64.EFI) bytes"
IMG=ventoy-emul.img
rm -f "$IMG"
truncate -s 1400M "$IMG"
mkfs.vfat -F 32 -n VENTOY "$IMG" >/dev/null
mmd -i "$IMG" ::/EFI ::/EFI/BOOT
mcopy -i "$IMG" BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$IMG" backpack.iso ::/backpack.iso
echo "image built:"; mdir -i "$IMG" :: | tail -n 5
