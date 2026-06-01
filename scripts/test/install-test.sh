#!/usr/bin/env bash
#
# Stage 3 + 4 — Scripted install, then boot the installed disk.
#
# 1. Creates a fresh blank qcow2 disk.
# 2. Boots the ISO with the install payload, which partitions that disk,
#    copies the live system onto it (the way Calamares' unpackfs does),
#    installs GRUB, and powers off. It echoes MIKA_INSTALL_OK on success.
# 3. Boots the *installed* disk (no ISO) and asserts it reaches a login
#    prompt on the serial console (MIKA_POSTINSTALL via login: marker).
#
# Usage:
#   scripts/test/install-test.sh [bios|uefi]        (default: uefi)
#   ISO=/path/to/x.iso scripts/test/install-test.sh
#
# NOTE: converting a live archiso rootfs into a bootable installed system has
# real edge cases (initramfs hooks, bootloader, fstab). The payload models
# what Calamares does, but expect to tune payloads/install.sh against a real
# build the first time through.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require qemu-system-x86_64 qemu-img blkid xorriso

FW="${1:-uefi}"
[[ "$FW" == bios || "$FW" == uefi ]] || fail "usage: $0 [bios|uefi]"

log "ISO under test: $(find_iso)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DISK="${WORK}/mika-install.qcow2"
qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
log "created blank target disk (${DISK_SIZE})"

start_payload_server
trap 'stop_payload_server; rm -rf "$WORK"' EXIT

# --- Stage 3: run the scripted install ------------------------------------
install_log="$(mktemp --suffix=-mika-install.log)"
log "running scripted install (${FW})..."
boot_iso_with_payload "$FW" "$INSTALL_TIMEOUT" "$install_log" "install.sh" \
    -drive "file=${DISK},if=virtio,format=qcow2"
expect_sentinel "$install_log" "MIKA_INSTALL_OK" "scripted install completed (${FW})"

# --- Stage 4: boot the installed disk -------------------------------------
post_log="$(mktemp --suffix=-mika-postinstall.log)"
log "booting installed disk (${FW})..."
boot_disk "$FW" "$POSTINSTALL_TIMEOUT" "$post_log" "$DISK"
# A serial-getty login prompt is the proof the installed system boots.
expect_sentinel "$post_log" "login:" "installed system reached login prompt (${FW})"

ok "install test passed (${FW})"
