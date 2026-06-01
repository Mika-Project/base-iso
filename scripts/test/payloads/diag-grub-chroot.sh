#!/usr/bin/env bash
#
# Faithful diagnostic: do a real install, then run Calamares' EXACT bootloader
# command INSIDE the target chroot (where / is /dev/vda2, like Calamares) and
# capture the full error. Also tries --no-nvram and --removable for comparison,
# and reports efivars/efibootmgr state. -e is OFF so failures are captured.
set -uo pipefail
exec >/dev/ttyS0 2>&1
echo "MIKA_DIAG_START"

DISK="/dev/vda"
SFS="/run/archiso/bootmnt/arch/x86_64/airootfs.sfs"
SRC="$(mktemp -d)"
timeout 180 systemctl is-system-running --wait >/dev/null 2>&1 || true

echo "== partition (ESP at /boot/efi, like Calamares) =="
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+512M -t1:ef00 -c1:EFI  "$DISK"
sgdisk -n2:0:0     -t2:8300 -c2:ROOT "$DISK"
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 -F  "${DISK}2"
mount "${DISK}2" /mnt
mkdir -p /mnt/boot/efi
mount "${DISK}1" /mnt/boot/efi

echo "== copy rootfs + kernel =="
mount -t squashfs -o ro "$SFS" "$SRC"
cp -a "${SRC}/." /mnt/
umount "$SRC"
cp /run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux /mnt/boot/vmlinuz-linux
: > /mnt/etc/fstab
genfstab -U /mnt >> /mnt/etc/fstab

echo "== run Calamares' EXACT grub-install inside the chroot =="
arch-chroot /mnt /bin/bash <<'CHROOT'
set +e
echo "--- in chroot: / is $(findmnt -no SOURCE / 2>/dev/null) ---"
echo "--- efivars mount ---"; mount | grep -i efivars || echo "efivars NOT mounted in chroot"
echo "--- /etc/mtab is: $(readlink -f /etc/mtab 2>/dev/null) ---"

echo "=== A) Calamares exact: grub-install --efi-directory=/boot/efi --bootloader-id=MIKA --force (writes NVRAM) ==="
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MIKA --force
echo ">>> A exit=$?"

echo "=== B) same + --no-nvram (skip efibootmgr) ==="
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MIKA --force --no-nvram
echo ">>> B exit=$?"

echo "=== C) --removable (what our install.sh uses) ==="
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MIKA --removable
echo ">>> C exit=$?"
CHROOT
echo ">>> arch-chroot wrapper exit=$?"

echo "MIKA_DIAG_OK"
sync
systemctl poweroff -i 2>/dev/null || poweroff -f
