#!/usr/bin/env bash
#
# Interactive local boot — just open the ISO in a QEMU window to click around.
# This is the "emulate it on my machine instead of a USB stick" shortcut.
#
# Usage:
#   scripts/test/run.sh [bios|uefi]     (default: uefi)
#   ISO=/path/to/x.iso scripts/test/run.sh
#
# Attaches a persistent 20G disk (scripts/test/.run-disk.qcow2) so you can do
# a real manual Calamares install and keep it between runs.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require qemu-system-x86_64 qemu-img

FW="${1:-uefi}"
ISO_PATH="$(find_iso)"
DISK="${TEST_DIR}/.run-disk.qcow2"
[[ -f "$DISK" ]] || qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null

accel="$(accel_args)"
fw_args=()
if [[ "$FW" == "uefi" ]]; then
    code="$(find_ovmf_code)"; tpl="$(find_ovmf_vars_template)"
    vars="${TEST_DIR}/.run-OVMF_VARS.fd"
    [[ -f "$vars" ]] || cp "$tpl" "$vars"
    fw_args=(-drive "if=pflash,format=raw,readonly=on,file=${code}"
             -drive "if=pflash,format=raw,file=${vars}")
fi

log "interactive boot (${FW}) of ${ISO_PATH} — close the window to quit"
# Attach the ISO as an explicit virtio-scsi CD-ROM with bootindex=0 so the
# firmware boots it. A bare `-drive media=cdrom` is not auto-wired by modern
# QEMU, so the guest/firmware never sees the disc (it would drop to the archiso
# emergency shell). No -display flag => QEMU opens a normal GUI window.
#
# GPU: Mika autologins into a Plasma 6 *Wayland* session, whose compositor
# (kwin_wayland) needs working OpenGL. Plain emulated VGA gives no usable GL, so
# SDDM starts but the screen stays black/text. virtio-vga-gl + -display gtk,gl=on
# gives the guest GL acceleration (virgl) so the desktop actually renders.
# (On real hardware this isn't needed — a real GPU provides GL natively.)
# shellcheck disable=SC2086
exec qemu-system-x86_64 $accel -m "$VM_MEM" -smp "$VM_SMP" "${fw_args[@]}" \
    -vga none -device virtio-vga-gl -display gtk,gl=on \
    -device virtio-scsi-pci,id=scsi0 \
    -drive "id=cd0,if=none,format=raw,readonly=on,file=${ISO_PATH}" \
    -device scsi-cd,bus=scsi0.0,drive=cd0,bootindex=0 \
    -drive "file=${DISK},if=virtio,format=qcow2" \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0
