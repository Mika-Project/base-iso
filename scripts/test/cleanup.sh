#!/usr/bin/env bash
#
# Reclaim RAM/disk held by orphaned ISO-test scratch, and kill any stray test
# VMs. Run this if a test was killed (host OOM, editor/VSCode crash, kill -9):
# a killed run never cleans up its mktemp dir, and a leftover install qcow2 can
# be several GB. If TMPDIR pointed at a tmpfs /tmp (the harness now avoids that),
# that leftover sits in RAM and can wedge a low-memory machine.
#
#   scripts/test/cleanup.sh
#
# Safe to run any time you are NOT mid-test. It only removes this harness's own
# scratch (the dedicated /var/tmp/mika-iso-test + ~/.cache/mika-iso-test dirs and
# files matching the harness's mktemp templates).

set -euo pipefail
log() { printf '\033[1;34m[cleanup]\033[0m %s\n' "$*" >&2; }

mem() { free -h 2>/dev/null | awk 'NR==2{printf "used %s, free %s, avail %s\n",$3,$4,$7}'; }
log "memory before: $(mem)"

# 1) Kill stray test VMs / payload servers (a hung QEMU holds its whole VM_MEM).
if pgrep -f 'qemu-system-x86_64.*archisolabel|qemu-system-x86_64.*mika-install' >/dev/null 2>&1; then
    log "killing stray qemu test VM(s)"
    pkill -f 'qemu-system-x86_64.*archisolabel' 2>/dev/null || true
    pkill -f 'qemu-system-x86_64.*mika-install' 2>/dev/null || true
fi
pkill -f 'python3 -m http.server' 2>/dev/null || true

# 2) Empty the dedicated disk-backed scratch dirs the harness uses.
for d in /var/tmp/mika-iso-test "${HOME}/.cache/mika-iso-test"; do
    if [[ -d "$d" ]]; then
        log "clearing scratch dir $d ($(du -sh "$d" 2>/dev/null | cut -f1))"
        rm -rf "${d:?}/"* "${d:?}/".* 2>/dev/null || true
    fi
done

# 3) Sweep legacy leftovers from before scratch moved off /tmp: orphaned mktemp
#    dirs/files matching the harness templates, in /tmp and any TMPDIR.
for base in /tmp "${TMPDIR:-/tmp}" /tmp/claude-*; do
    [[ -d "$base" ]] || continue
    find "$base" -maxdepth 2 \( \
            -name 'mika-install.qcow2' -o \
            -name '*-mika-boot-*.log' -o \
            -name '*-mika-install.log' -o \
            -name '*-mika-postinstall.log' -o \
            -name '*-OVMF_VARS.fd' -o \
            -name 'initrd.img' -o -name 'initramfs-linux.img' \
        \) -type f -delete 2>/dev/null || true
done

log "memory after:  $(mem)"
log "done."
