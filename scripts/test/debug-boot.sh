#!/usr/bin/env bash
#
# Interactive debug boot of the harness payload path.
#
# Unlike boot-test.sh (headless, CI), this opens a QEMU WINDOW you can watch and
# puts the live console on the GUI (tty0 is last on the cmdline, so it owns
# /dev/console). If archiso can't find its medium and drops to the emergency
# shell, that shell is right there in the window — run `lsblk` / `blkid` to see
# what block devices the guest actually has.
#
# Usage:
#   scripts/test/debug-boot.sh [bios|uefi]            (default: uefi)
#
# Env knobs:
#   PAYLOAD=selftest.sh|install.sh   which payload to serve (default selftest.sh)
#   QEMU_DISPLAY=gtk|sdl|none        window backend (default gtk; none = headless)
#   EXTRA_CMDLINE="rootdelay=60 ..." extra kernel params for debugging
#   VM_MEM / VM_SMP / DISK_SIZE      as in lib.sh
#
# It serves the payload over HTTP (guest reaches it at 10.0.2.2) exactly like
# the real harness, and attaches a scratch disk so install.sh can be tried too.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require qemu-system-x86_64 blkid xorriso python3

FW="${1:-uefi}"
[[ "$FW" == bios || "$FW" == uefi ]] || fail "usage: $0 [bios|uefi]"
PAYLOAD="${PAYLOAD:-selftest.sh}"
QEMU_DISPLAY="${QEMU_DISPLAY:-gtk}"

iso="$(find_iso)"
label="$(iso_label "$iso")"
log "ISO under test : ${iso}"
log "archisolabel   : ${label}   (the guest must find /dev/disk/by-label/${label})"
log "firmware       : ${FW}"
log "payload        : ${PAYLOAD}"

WORK="$(mktemp -d)"
cleanup() { stop_payload_server; rm -rf "$WORK"; }
trap cleanup EXIT

extract_iso_boot "$iso" "$WORK"
start_payload_server
url="$(guest_payload_url "$PAYLOAD")"

# A scratch disk so install.sh has a /dev/vda target if you want to try it.
DISK="${WORK}/debug-disk.qcow2"
qemu-img create -f qcow2 "$DISK" "${DISK_SIZE}" >/dev/null
log "scratch disk   : ${DISK} (${DISK_SIZE}) -> guest /dev/vda"

# tty0 is LAST so the GUI window owns /dev/console (interactive emergency shell
# / login). The payload still writes its markers to /dev/ttyS0, captured below.
cmdline="archisobasedir=arch archisolabel=${label} cow_spacesize=4G systemd.unit=multi-user.target systemd.wants=network-online.target console=ttyS0,115200 console=tty0 script=${url}${EXTRA_CMDLINE:+ ${EXTRA_CMDLINE}}"

accel="$(accel_args)"
fw_args=()
if [[ "$FW" == uefi ]]; then
    code="$(find_ovmf_code)"; tpl="$(find_ovmf_vars_template)"
    vars="${WORK}/OVMF_VARS.fd"; cp "$tpl" "$vars"
    fw_args=(-drive "if=pflash,format=raw,readonly=on,file=${code}"
             -drive "if=pflash,format=raw,file=${vars}")
fi

serial_log="${WORK}/serial.log"
log "serial log     : ${serial_log}   (payload MIKA_* markers land here)"
log "kernel cmdline :"
printf '    %s\n' "$cmdline" >&2
log "------------------------------------------------------------------"
log "Watch the QEMU window. If you land in the archiso emergency shell, run:"
log "    lsblk ; blkid ; ls -l /dev/disk/by-label/"
log "Close the window (or Ctrl-C here) to quit."
log "------------------------------------------------------------------"

# shellcheck disable=SC2086
qemu-system-x86_64 $accel -m "${VM_MEM}" -smp "${VM_SMP}" "${fw_args[@]}" \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    -display "${QEMU_DISPLAY}" -no-reboot \
    -serial "file:${serial_log}" \
    -kernel "$KERNEL" -initrd "$INITRD" -append "$cmdline" \
    -device virtio-scsi-pci,id=scsi0 \
    -drive "id=cd0,if=none,format=raw,readonly=on,file=${iso}" \
    -device scsi-cd,bus=scsi0.0,drive=cd0 \
    -drive "file=${DISK},if=virtio,format=qcow2" || true

echo
log "==== last 50 lines of serial log ===="
tail -n 50 "$serial_log" 2>/dev/null || true
if grep -qa MIKA_BOOT_OK "$serial_log" 2>/dev/null; then
    ok "MIKA_BOOT_OK was printed — payload delivery works."
else
    log "MIKA_BOOT_OK not seen (see serial log above for where it stopped)."
fi
