#!/usr/bin/env bash
# Reproduce the Calamares scalar-options /dev bug AND confirm the list-options fix.
# Attaches a fresh blank virtio disk as /dev/vda (one unpackfs pass; ~5 min).
# Usage: VM_MEM=3072 scripts/test/diag-dev-bug-run.sh [uefi|bios]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require qemu-system-x86_64 xorriso blkid python3 qemu-img
FW="${1:-uefi}"; [[ "$FW" == uefi || "$FW" == bios ]] || fail "usage: $0 [uefi|bios]"
LOG="${TEST_DIR}/diag-dev-bug.log"
DISK="${TEST_DIR}/.dev-bug-disk.qcow2"; rm -f "$DISK"
qemu-img create -f qcow2 "$DISK" 12G >/dev/null
log "created blank target disk (12G)"
start_payload_server
trap 'stop_payload_server 2>/dev/null || true; rm -f "$DISK"' EXIT
: > "$LOG"
log "Booting Mika (${FW}) HEADLESS to reproduce+confirm the /dev options bug (~5 min)..."
SHOW_SERIAL=0 boot_iso_with_payload "$FW" 480 "$LOG" diag-dev-bug.sh \
    -drive "file=${DISK},if=virtio,format=qcow2"
echo
log "============== /dev OPTIONS BUG: REPRODUCE + FIX =============="
sed 's/\x1b\[[0-9;]*m//g' "$LOG" | sed -n '/DEVBUG_START/,/DEVBUG_OK/p' || true
log "=============================================================="
grep -qa DEVBUG_OK "$LOG" && log "completed. full log: $LOG" \
  || { log "did NOT complete; last 25 serial lines:"; sed 's/\x1b\[[0-9;]*m//g' "$LOG" | tail -25 >&2 || true; }
