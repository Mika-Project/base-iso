#!/usr/bin/env bash
#
# Headless desktop diagnostic. Boots the ISO with no window, brings up SDDM/the
# Plasma X11 session, and captures WHY it does (or doesn't) render — the full
# SDDM/Xorg/Plasma/journal dump is shipped over the serial port to a host file.
# Nothing to type or click in the VM.
#
# Usage:
#   scripts/test/desktop-diag.sh [uefi|bios]        (default: uefi)
#   VM_MEM=3072 scripts/test/desktop-diag.sh uefi
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require qemu-system-x86_64 xorriso blkid python3

FW="${1:-uefi}"
[[ "$FW" == uefi || "$FW" == bios ]] || fail "usage: $0 [uefi|bios]"
LOG="${TEST_DIR}/desktop-diag.log"

start_payload_server
trap 'stop_payload_server 2>/dev/null || true' EXIT
: > "$LOG"

log "Booting Mika (${FW}) HEADLESS to capture desktop/SDDM logs (~2 min, no window)..."
SHOW_SERIAL=0 boot_iso_with_payload "$FW" 160 "$LOG" desk-diag.sh

echo
log "==================== captured desktop diagnostic ===================="
sed 's/\x1b\[[0-9;]*m//g' "$LOG" | sed -n '/MIKA_DESKDIAG_START/,/MIKA_DESKDIAG_OK/p' || true
log "====================================================================="
if ! grep -qa MIKA_DESKDIAG_OK "$LOG"; then
    log "capture did not complete; last 30 serial lines:"
    sed 's/\x1b\[[0-9;]*m//g' "$LOG" | tail -30 >&2 || true
fi
log "full serial log: $LOG"
