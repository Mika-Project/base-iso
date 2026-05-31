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
# shellcheck disable=SC2086
exec qemu-system-x86_64 $accel -m "$VM_MEM" -smp "$VM_SMP" "${fw_args[@]}" \
    -drive "file=${ISO_PATH},media=cdrom,readonly=on" \
    -drive "file=${DISK},if=virtio,format=qcow2" \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    -boot d
