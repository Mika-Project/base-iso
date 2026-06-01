#!/usr/bin/env bash
#
# Diagnostic payload: reproduce Calamares' failing EFI bootloader step and dump
# the FULL error to the serial console. Calamares runs (and it fails, code 1):
#   grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MIKA --force
#
# Not an install — it just sets up an ESP on /dev/vda and runs that exact
# command in the live env, plus reports efivars/efibootmgr/grub-probe state, so
# we can see WHY grub-install returns 1. NOTE: -e is intentionally OFF so a
# failure is captured and printed instead of aborting before the marker.
set -uo pipefail
exec >/dev/ttyS0 2>&1
echo "MIKA_DIAG_START"

timeout 120 systemctl is-system-running --wait >/dev/null 2>&1 || true

echo "===== firmware / efivars state ====="
if [[ -d /sys/firmware/efi ]]; then echo "booted: UEFI"; else echo "booted: BIOS (no /sys/firmware/efi)"; fi
mount | grep -i efivars || echo "efivars: NOT mounted"
if [[ -d /sys/firmware/efi/efivars ]]; then
    if touch /sys/firmware/efi/efivars/.wtest 2>/tmp/wt.err; then
        echo "efivars: WRITABLE"; rm -f /sys/firmware/efi/efivars/.wtest 2>/dev/null
    else
        echo "efivars: NOT writable -> $(cat /tmp/wt.err)"
    fi
fi
echo "-- efibootmgr --"; efibootmgr 2>&1 | head -20
echo "grub version: $(grub-install --version 2>&1)"
echo "x86_64-efi modules present: $([[ -d /usr/lib/grub/x86_64-efi ]] && echo yes || echo NO)"

echo "===== set up ESP on /dev/vda ====="
DISK=/dev/vda
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+512M -t1:ef00 -c1:EFI  "$DISK"
sgdisk -n2:0:0     -t2:8300 -c2:ROOT "$DISK"
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 -F  "${DISK}2"
mount "${DISK}2" /mnt
mkdir -p /mnt/boot/efi
mount "${DISK}1" /mnt/boot/efi

echo "===== run the EXACT Calamares grub-install command ====="
echo "+ grub-install --target=x86_64-efi --efi-directory=/mnt/boot/efi --bootloader-id=MIKA --force"
grub-install --target=x86_64-efi --efi-directory=/mnt/boot/efi --bootloader-id=MIKA --force
echo ">>> grub-install (with NVRAM) exit=$?"

echo "===== compare: same but --no-nvram (skips efibootmgr) ====="
grub-install --target=x86_64-efi --efi-directory=/mnt/boot/efi --bootloader-id=MIKA --force --no-nvram
echo ">>> grub-install --no-nvram exit=$?"

echo "===== compare: --removable (what our install.sh uses) ====="
grub-install --target=x86_64-efi --efi-directory=/mnt/boot/efi --bootloader-id=MIKA --removable
echo ">>> grub-install --removable exit=$?"

echo "===== grub-probe checks ====="
grub-probe --target=device /mnt/boot/efi 2>&1; echo ">>> grub-probe esp exit=$?"
grub-probe --target=device /mnt 2>&1;          echo ">>> grub-probe root exit=$?"

echo "MIKA_DIAG_OK"
sync
systemctl poweroff -i 2>/dev/null || poweroff -f
