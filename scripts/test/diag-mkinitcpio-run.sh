#!/usr/bin/env bash
#
# Headless A/B proof of the Calamares mkinitcpio "/dev must be mounted" fix.
# Boots the CURRENT ISO windowless and runs diag-mkinitcpio.sh, which builds a
# real initramfs under the OLD (bind /dev) and NEW (devtmpfs /dev) chroot mounts
# and reports which clears mkinitcpio's /dev gate. No rebuild needed.
#
# Usage: VM_MEM=3072 scripts/test/diag-mkinitcpio-run.sh [uefi|bios]   (default uefi)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require qemu-system-x86_64 xorriso blkid python3
FW="${1:-uefi}"
[[ "$FW" == uefi || "$FW" == bios ]] || fail "usage: $0 [uefi|bios]"
LOG="${TEST_DIR}/diag-mkinitcpio.log"
start_payload_server
trap 'stop_payload_server 2>/dev/null || true' EXIT
: > "$LOG"
log "Booting Mika (${FW}) HEADLESS to A/B-test the mkinitcpio /dev fix (~3-4 min)..."
SHOW_SERIAL=0 boot_iso_with_payload "$FW" 300 "$LOG" diag-mkinitcpio.sh
echo
log "================= MKINITCPIO /dev A/B CAPTURE ================="
sed 's/\x1b\[[0-9;]*m//g' "$LOG" | sed -n '/MKI_AB_START/,/MKI_AB_OK/p' || true
log "=============================================================="
grep -qa MKI_AB_OK "$LOG" && log "A/B completed. full serial log: $LOG" \
  || { log "A/B did NOT complete; last 30 serial lines:"; sed 's/\x1b\[[0-9;]*m//g' "$LOG" | tail -30 >&2 || true; }
