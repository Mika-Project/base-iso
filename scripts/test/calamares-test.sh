#!/usr/bin/env bash
#
# Test the REAL Calamares installer in a QEMU window and AUTOMATICALLY capture
# its full log on the HOST. No typing, no copy/paste, no internet needed inside
# the VM — you just click through the installer with the mouse.
#
# How: the harness boots the ISO and runs payloads/calamares-autocapture.sh,
# which arms a log streamer (ships Calamares' session.log over the emulated
# serial port to the host) and then brings up the desktop. You install with the
# mouse; the log is written to:
#     scripts/test/calamares-capture.log     (on the host)
#
# Use it to verify Calamares before a push: if the install completes cleanly the
# installer is good; if it fails, the captured log shows the exact error.
#
# Usage:
#   scripts/test/calamares-test.sh [uefi|bios]      (default: uefi)
#   VM_MEM=3072 scripts/test/calamares-test.sh uefi (smaller VM on a tight host)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require qemu-system-x86_64 qemu-img blkid xorriso python3

FW="${1:-uefi}"
[[ "$FW" == uefi || "$FW" == bios ]] || fail "usage: $0 [uefi|bios]"

WORK="$(mktemp -d)"
CAPTURE="${TEST_DIR}/calamares-capture.log"   # host log (user-writable; out/ is root-owned)
cleanup() { stop_payload_server 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

# Fresh blank target disk so "Erase disk" starts clean every run.
DISK="${WORK}/calamares-target.qcow2"
qemu-img create -f qcow2 "$DISK" "${DISK_SIZE}" >/dev/null

start_payload_server
: > "$CAPTURE"
log "================================================================"
log "Booting Mika (${FW}) in a QEMU window with a blank ${DISK_SIZE} disk."
log "It boots to text mode, arms the log capture, then the DESKTOP appears"
log "automatically (~1-2 min)."
log ""
log "  >>> JUST USE THE MOUSE: Install icon -> Erase disk -> install. <<<"
log ""
log "Calamares' full log is captured AUTOMATICALLY to the host file:"
log "    ${CAPTURE}"
log "When the install finishes or fails, close the QEMU window."
log "================================================================"

# Boot via the harness (extracted kernel + virtio-scsi CD), GUI window on, run
# the auto-capture payload, attach the blank target disk. The payload streams
# Calamares' log to the serial port, which the harness captures into $CAPTURE.
# 1800s is a safety cap; closing the window ends it sooner.
SHOW_GUI=1 SHOW_SERIAL=0 boot_iso_with_payload "$FW" 1800 "$CAPTURE" calamares-autocapture.sh \
    -drive "file=${DISK},if=virtio,format=qcow2"

echo
log "==== captured log: ${CAPTURE} ===="
if grep -qaiE "grub-install|bootloader|Bootloader|error|Calamares" "$CAPTURE" 2>/dev/null; then
    log "---- grub / bootloader / error lines ----"
    sed 's/\x1b\[[0-9;]*m//g' "$CAPTURE" \
        | grep -niE "grub-install|grub-probe|grub-mkconfig|efibootmgr|bootloader|error|failed|cannot|not supported|No space|Operation not permitted|canonical" \
        | tail -40 || true
    log "(full log is in ${CAPTURE})"
else
    log "No installer log captured. Did the desktop come up and did you run the"
    log "install? Re-run and watch for the desktop, then click Install -> Erase disk."
fi
