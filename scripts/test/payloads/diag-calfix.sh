#!/usr/bin/env bash
#
# Verify the Calamares GRUB fix end-to-end. Installs with the SAME layout
# Calamares uses (ESP at /boot/efi, kernel on the root partition's /boot) and
# the SAME bootloader flow the mika-grub-install wrapper produces:
#   grub-install --no-nvram ... --bootloader-id=MIKA --force   (no efibootmgr)
#   then copy grubx64.efi -> /EFI/BOOT/bootx64.efi  (Calamares installEFIFallback)
# Prints MIKA_INSTALL_OK on success; the harness then boots the installed disk.
set -uo pipefail
exec >/dev/ttyS0 2>&1
echo "MIKA_INSTALL_START"

DISK="/dev/vda"
SFS="/run/archiso/bootmnt/arch/x86_64/airootfs.sfs"
SRC="$(mktemp -d)"
timeout 180 systemctl is-system-running --wait >/dev/null 2>&1 || true

set -e
echo "== partition (Calamares layout: ESP /boot/efi + root) =="
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+512M -t1:ef00 -c1:EFI  "$DISK"
sgdisk -n2:0:0     -t2:8300 -c2:ROOT "$DISK"
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 -F  "${DISK}2"
mount "${DISK}2" /mnt
mkdir -p /mnt/boot/efi
mount "${DISK}1" /mnt/boot/efi

echo "== copy rootfs + kernel (kernel on ROOT /boot) =="
mount -t squashfs -o ro "$SFS" "$SRC"
cp -a "${SRC}/." /mnt/
umount "$SRC"
cp /run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux /mnt/boot/vmlinuz-linux
: > /mnt/etc/fstab
genfstab -U /mnt >> /mnt/etc/fstab

echo "== chroot: mkinitcpio + FIXED grub flow (--no-nvram + fallback copy) =="
arch-chroot /mnt /bin/bash -euo pipefail <<'CHROOT'
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf /root/.automated_script.sh /root/.zlogin
cat > /etc/mkinitcpio.conf.d/mika.conf <<'MKI'
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)
MKI
cat > /etc/mkinitcpio.d/linux.preset <<'PRE'
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default' 'fallback')
default_image="/boot/initramfs-linux.img"
fallback_image="/boot/initramfs-linux-fallback.img"
fallback_options="-S autodetect"
PRE
mkinitcpio -P
sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 console=tty0 console=ttyS0,115200"|' /etc/default/grub || true
systemctl enable serial-getty@ttyS0.service
echo "--- grub-install --no-nvram (the wrapper's EFI behaviour) ---"
grub-install --no-nvram --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MIKA --force
echo ">>> grub-install exit=$?"
echo "--- installEFIFallback copy -> /EFI/BOOT/bootx64.efi ---"
install -Dm644 /boot/efi/EFI/MIKA/grubx64.efi /boot/efi/EFI/BOOT/bootx64.efi
ls -l /boot/efi/EFI/BOOT/bootx64.efi
grub-mkconfig -o /boot/grub/grub.cfg
echo 'root:mika' | chpasswd
CHROOT

echo "== finishing =="
sync
umount -R /mnt
echo "MIKA_INSTALL_OK"
sync
systemctl poweroff -i 2>/dev/null || poweroff -f
