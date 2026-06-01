#!/usr/bin/env bash
#
# Stage 2 — Boot smoke test.
#
# Boots the built ISO headless in QEMU (BIOS and/or UEFI) using the extracted
# kernel + the `script=` hook, and asserts the live environment reaches our
# self-test payload, which echoes MIKA_BOOT_OK to the serial console.
#
# Usage:
#   scripts/test/boot-test.sh [bios|uefi|both]      (default: both)
#   ISO=/path/to/x.iso scripts/test/boot-test.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require qemu-system-x86_64 blkid xorriso

MODE="${1:-both}"
log "ISO under test: $(find_iso)"

start_payload_server
trap stop_payload_server EXIT

boot_once() {
    local fw="$1" logfile
    logfile="$(mktemp --suffix=-mika-boot-${fw}.log)"
    boot_iso_with_payload "$fw" "$BOOT_TIMEOUT" "$logfile" "selftest.sh"
    expect_sentinel "$logfile" "MIKA_BOOT_OK" "live environment booted (${fw})"
}

rc=0
case "$MODE" in
    bios) boot_once bios || rc=1 ;;
    uefi) boot_once uefi || rc=1 ;;
    both) boot_once bios || rc=1; boot_once uefi || rc=1 ;;
    *)    fail "usage: $0 [bios|uefi|both]" ;;
esac

[[ $rc -eq 0 ]] && ok "boot smoke test passed (${MODE})"
exit $rc
