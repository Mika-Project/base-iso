#!/usr/bin/env bash
#
# Scripted install payload. Delivered to the live ISO via `script=<url>` and
# run on tty1. It performs, headlessly, the same work Calamares does — wipe
# the target disk, partition, copy the live root filesystem onto it, generate
# fstab, build a normal initramfs, install GRUB, set up a serial login — then
# powers off. Prints MIKA_INSTALL_OK to /dev/ttyS0 only if every step
# succeeded (set -e aborts before the marker otherwise, which the harness
# correctly reports as a failure).
#
# Target is the first virtio disk (/dev/vda) the harness attaches.
#
# This mirrors Calamares but is intentionally minimal; tune it against a real
# build the first time through (initramfs hooks and bootloader are the usual
# sticking points when converting an archiso live root into an installed one).

set -euo pipefail
exec >/dev/ttyS0 2>&1
echo "MIKA_INSTALL_START"

DISK="/dev/vda"
# Mount the pristine root squashfs exactly where Calamares' unpackfs.conf reads
# it from: archiso keeps the boot medium at /run/archiso/bootmnt and the
# read-only root image is arch/x86_64/airootfs.sfs on it. We mount that .sfs
# ourselves instead of assuming a transient /run/archiso/airootfs mountpoint,
# whose path varies between archiso versions.
SFS="/run/archiso/bootmnt/arch/x86_64/airootfs.sfs"
SRC="$(mktemp -d)"

# Wait for pacman-init etc. so the copied keyring/db is consistent.
timeout 180 systemctl is-system-running --wait >/dev/null 2>&1 || true

if [[ -d /sys/firmware/efi ]]; then FW="uefi"; else FW="bios"; fi
echo "firmware=${FW} target=${DISK} squashfs=${SFS}"
[[ -f "$SFS" ]] || { echo "ERROR: live squashfs $SFS not found"; exit 1; }
mount -t squashfs -o ro "$SFS" "$SRC"
echo "mounted live root: ${SFS} -> ${SRC}"

echo "== partitioning =="
sgdisk --zap-all "$DISK"
if [[ "$FW" == "uefi" ]]; then
    sgdisk -n1:0:+512M -t1:ef00 -c1:EFI  "$DISK"
    sgdisk -n2:0:0     -t2:8300 -c2:ROOT "$DISK"
    ESP="${DISK}1"; ROOT="${DISK}2"
    mkfs.fat -F32 "$ESP"
else
    sgdisk -n1:0:+1M -t1:ef02 -c1:BIOS "$DISK"   # BIOS boot partition for GRUB
    sgdisk -n2:0:0   -t2:8300 -c2:ROOT "$DISK"
    ROOT="${DISK}2"
fi
mkfs.ext4 -F "$ROOT"

echo "== mounting =="
mount "$ROOT" /mnt
if [[ "$FW" == "uefi" ]]; then
    mkdir -p /mnt/boot
    mount "$ESP" /mnt/boot
fi

echo "== copying live root filesystem =="
# cp -a preserves attrs; the squashfs is already a clean installed-style tree.
cp -a "${SRC}/." /mnt/
umount "$SRC"; rmdir "$SRC" 2>/dev/null || true

echo "== installing kernel + microcode =="
# archiso keeps the kernel and microcode OUT of the squashfs (served from the
# ISO), so /boot has no vmlinuz after the rootfs copy and mkinitcpio/GRUB would
# fail. Copy them from the boot medium, like Calamares' unpackfs.conf does. The
# matching kernel modules are already in the copied rootfs (/usr/lib/modules).
BOOTSRC="/run/archiso/bootmnt/arch/boot"
mkdir -p /mnt/boot
cp "${BOOTSRC}/x86_64/vmlinuz-linux" /mnt/boot/vmlinuz-linux
for _uc in intel-ucode.img amd-ucode.img; do
    [[ -f "${BOOTSRC}/${_uc}" ]] && cp "${BOOTSRC}/${_uc}" "/mnt/boot/${_uc}"
done

echo "== fstab =="
# Start from a clean fstab (the live image ships its own archiso fstab).
: > /mnt/etc/fstab
genfstab -U /mnt >> /mnt/etc/fstab

echo "== de-archiso-ifying + bootloader =="
arch-chroot /mnt /bin/bash -euo pipefail <<CHROOT
# Remove live-only autologin/automation so the installed system shows a real
# login prompt (the harness greps for "login:").
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
rm -f /root/.automated_script.sh /root/.zlogin

# A normal initramfs (drop archiso hooks).
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

# Serial console so the harness can see the login prompt + kernel messages.
sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 console=tty0 console=ttyS0,115200"|' /etc/default/grub || true
systemctl enable serial-getty@ttyS0.service
systemctl enable NetworkManager.service 2>/dev/null || true

if [[ "${FW}" == "uefi" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
else
    grub-install --target=i386-pc ${DISK}
fi
grub-mkconfig -o /boot/grub/grub.cfg

# A known root password (test only).
echo 'root:mika' | chpasswd
CHROOT

echo "== finishing =="
sync
umount -R /mnt

echo "MIKA_INSTALL_OK"
sync
systemctl poweroff -i 2>/dev/null || poweroff -f
