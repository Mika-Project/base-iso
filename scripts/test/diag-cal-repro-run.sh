#!/usr/bin/env bash
# Faithful Calamares-ordering reproduction of the mkinitcpio "/dev must be mounted"
# error: empty disk -> mount API fs -> unpackfs -> chroot mkinitcpio, OLD bind vs
# NEW devtmpfs. Attaches a fresh blank virtio disk as /dev/vda (like
# install-test.sh). ~8-10 min (two full unsquash passes).
# Usage: VM_MEM=3072 scripts/test/diag-cal-repro-run.sh [uefi|bios]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require qemu-system-x86_64 xorriso blkid python3 qemu-img
FW="${1:-uefi}"
[[ "$FW" == uefi || "$FW" == bios ]] || fail "usage: $0 [uefi|bios]"
LOG="${TEST_DIR}/diag-cal-repro.log"

# Fresh blank target disk attached as /dev/vda (the payload partitions it).
DISK="${TEST_DIR}/.cal-repro-disk.qcow2"
rm -f "$DISK"
qemu-img create -f qcow2 "$DISK" 12G >/dev/null
log "created blank target disk (12G) -> $DISK"

start_payload_server
trap 'stop_payload_server 2>/dev/null || true; rm -f "$DISK"' EXIT
: > "$LOG"
log "Booting Mika (${FW}) HEADLESS for faithful Calamares-order reproduction (~8-10 min)..."
SHOW_SERIAL=0 boot_iso_with_payload "$FW" 600 "$LOG" diag-cal-repro.sh \
    -drive "file=${DISK},if=virtio,format=qcow2"
echo
log "============== CALAMARES-ORDER /dev REPRODUCTION =============="
sed 's/\x1b\[[0-9;]*m//g' "$LOG" | sed -n '/CAL_REPRO_START/,/CAL_REPRO_OK/p' || true
log "=============================================================="
grep -qa CAL_REPRO_OK "$LOG" && log "reproduction completed. full log: $LOG" \
  || { log "did NOT complete; last 30 serial lines:"; sed 's/\x1b\[[0-9;]*m//g' "$LOG" | tail -30 >&2 || true; }
