#!/usr/bin/env bash
#
# Headless end-to-end verification of the built ISO: boots Mika with no window,
# brings up the desktop, lets the auto-started Calamares run, and captures the
# verdict (desktop rendered? Calamares launched + all modules loaded?) over serial.
# Nothing to click; safe to run alone (single RAM-capped VM).
#
# Usage: VM_MEM=3072 scripts/test/verify-mika-run.sh [uefi|bios]   (default uefi)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require qemu-system-x86_64 xorriso blkid python3
FW="${1:-uefi}"
[[ "$FW" == uefi || "$FW" == bios ]] || fail "usage: $0 [uefi|bios]"
LOG="${TEST_DIR}/verify-mika.log"

start_payload_server
trap 'stop_payload_server 2>/dev/null || true' EXIT
: > "$LOG"

log "Booting Mika (${FW}) HEADLESS to verify desktop + Calamares (~3 min)..."
SHOW_SERIAL=0 boot_iso_with_payload "$FW" 200 "$LOG" verify-mika.sh

echo
log "==================== MIKA VERIFICATION CAPTURE ===================="
sed 's/\x1b\[[0-9;]*m//g' "$LOG" | sed -n '/MIKA_VERIFY_START/,/MIKA_VERIFY_OK/p' || true
log "=================================================================="
if grep -qa MIKA_VERIFY_OK "$LOG"; then
    log "capture completed. full serial log: $LOG"
else
    log "capture did NOT complete cleanly; last 30 serial lines:"
    sed 's/\x1b\[[0-9;]*m//g' "$LOG" | tail -30 >&2 || true
fi
