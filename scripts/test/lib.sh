# shellcheck shell=bash
#
# Shared helpers for the Mika ISO test harness.
#
# Source this file, don't execute it:
#     source "$(dirname "$0")/lib.sh"
#
# Design notes (why it works the way it does):
#
#  * Runner-agnostic. Needs only bash, qemu, util-linux (blkid), python3 and
#    — for UEFI — edk2-ovmf. Identical behaviour on a laptop and in CI. KVM is
#    used when /dev/kvm is present and falls back to slow TCG otherwise.
#
#  * Booting the ISO. archiso sets the kernel cmdline from the bootloader
#    INSIDE the ISO, so we cannot inject `script=` through QEMU's -append while
#    booting the CD directly. Instead we extract vmlinuz + initramfs (+ucode)
#    from the ISO and boot them with `-kernel/-initrd/-append`, the way the
#    archiso wiki documents headless QEMU testing. archiso finds its squashfs
#    via `archisolabel=<LABEL>` (read from the ISO with blkid), so no UUID is
#    needed.
#
#  * Running a script in the guest. The live ISO's /root/.automated_script.sh
#    already executes `script=<url>` from the cmdline — but ONLY on tty1, and
#    its output goes to tty1. We serve the payload over HTTP (reachable from
#    the guest at 10.0.2.2) and the payload echoes its result to /dev/ttyS0 so
#    the headless serial log captures it. This keeps all test code OUT of the
#    production ISO.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
PAYLOAD_DIR="${TEST_DIR}/payloads"

# Tunables (override via environment).
VM_MEM="${VM_MEM:-4096}"
VM_SMP="${VM_SMP:-2}"
DISK_SIZE="${DISK_SIZE:-20G}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"          # reach the live boot sentinel
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-1800}"   # full scripted install
POSTINSTALL_TIMEOUT="${POSTINSTALL_TIMEOUT:-300}" # boot the installed disk

# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------
log()  { printf '\033[1;34m[test]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
# Dependencies & assets
# ----------------------------------------------------------------------------
require() {
    local missing=0 cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || { log "missing command: $cmd"; missing=1; }
    done
    [[ $missing -eq 0 ]] || fail "install the missing dependencies and retry"
}

# Locate the built ISO ($ISO override, else newest out/*.iso).
find_iso() {
    if [[ -n "${ISO:-}" ]]; then
        [[ -f "$ISO" ]] || fail "ISO=$ISO does not exist"
        printf '%s\n' "$ISO"; return
    fi
    local found
    found="$(ls -t "${REPO_ROOT}/out/"*.iso 2>/dev/null | head -n1 || true)"
    [[ -n "$found" ]] || fail "no ISO in ${REPO_ROOT}/out/ — build it first or set ISO=..."
    printf '%s\n' "$found"
}

# Read the ISO9660 volume label archiso matches on.
iso_label() {
    local label
    label="$(blkid -s LABEL -o value "$1" 2>/dev/null || true)"
    [[ -n "$label" ]] || fail "could not read volume label from $1"
    printf '%s\n' "$label"
}

# Extract the boot bits from the ISO into $1 (dir). Echoes nothing; sets
# globals KERNEL and INITRD (comma-joined: ucode first, then initramfs).
KERNEL=""; INITRD=""
extract_iso_boot() {
    local iso="$1" dest="$2"
    require xorriso
    mkdir -p "$dest"
    # install_dir is "arch" (profiledef.sh). Extract kernel + any microcode +
    # the main initramfs.
    local base="/arch/boot"
    xorriso -osirrox on -indev "$iso" \
        -extract "${base}/x86_64/vmlinuz-linux"     "${dest}/vmlinuz-linux" \
        -extract "${base}/x86_64/initramfs-linux.img" "${dest}/initramfs-linux.img" \
        >/dev/null 2>&1 || fail "failed to extract kernel/initramfs from $iso"
    KERNEL="${dest}/vmlinuz-linux"
    local initrds=()
    local uc
    for uc in intel-ucode.img amd-ucode.img; do
        if xorriso -osirrox on -indev "$iso" \
              -extract "${base}/${uc}" "${dest}/${uc}" >/dev/null 2>&1; then
            initrds+=("${dest}/${uc}")
        fi
    done
    initrds+=("${dest}/initramfs-linux.img")
    INITRD="$(IFS=,; echo "${initrds[*]}")"
}

accel_args() {
    if [[ -r /dev/kvm && -w /dev/kvm ]]; then
        printf '%s\n' "-enable-kvm -cpu host"
    else
        log "/dev/kvm unavailable — using slow TCG emulation"
        printf '%s\n' "-cpu max"
    fi
}

find_ovmf_code() {
    local c
    for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd \
             /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
             /usr/share/OVMF/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE.fd; do
        [[ -f "$c" ]] && { printf '%s\n' "$c"; return; }
    done
    fail "OVMF code not found — install edk2-ovmf (Arch) / ovmf (Debian)"
}
find_ovmf_vars_template() {
    local v
    for v in /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.fd \
             /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
             /usr/share/OVMF/OVMF_VARS.4m.fd /usr/share/OVMF/OVMF_VARS.fd; do
        [[ -f "$v" ]] && { printf '%s\n' "$v"; return; }
    done
    fail "OVMF vars template not found — install edk2-ovmf / ovmf"
}

# ----------------------------------------------------------------------------
# Payload HTTP server (guest reaches host at 10.0.2.2)
# ----------------------------------------------------------------------------
HTTP_PID=""; HTTP_PORT=""
start_payload_server() {
    require python3
    HTTP_PORT="$(( (RANDOM % 20000) + 20000 ))"
    ( cd "$PAYLOAD_DIR" && exec python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 ) \
        >/dev/null 2>&1 &
    HTTP_PID=$!
    sleep 1
    kill -0 "$HTTP_PID" 2>/dev/null || fail "payload HTTP server failed to start"
    log "payloads on host:${HTTP_PORT} (guest base http://10.0.2.2:${HTTP_PORT}/)"
}
stop_payload_server() { [[ -n "$HTTP_PID" ]] && kill "$HTTP_PID" 2>/dev/null || true; HTTP_PID=""; }
guest_payload_url() { printf 'http://10.0.2.2:%s/%s\n' "$HTTP_PORT" "$1"; }

# ----------------------------------------------------------------------------
# QEMU
# ----------------------------------------------------------------------------
# _qemu <firmware> <timeout> <logfile> -- <extra args...>
# Boots headless, serial -> logfile, exits on guest poweroff or timeout.
_qemu() {
    local firmware="$1" timeout_s="$2" logfile="$3"; shift 3
    [[ "${1:-}" == "--" ]] && shift
    local accel; accel="$(accel_args)"
    local -a fw_args=()
    local vars=""
    if [[ "$firmware" == "uefi" ]]; then
        local code tpl
        code="$(find_ovmf_code)"; tpl="$(find_ovmf_vars_template)"
        vars="$(mktemp --suffix=-OVMF_VARS.fd)"; cp "$tpl" "$vars"
        fw_args=(-drive "if=pflash,format=raw,readonly=on,file=${code}"
                 -drive "if=pflash,format=raw,file=${vars}")
    fi
    log "qemu (${firmware}, timeout ${timeout_s}s) -> $(basename "$logfile")"
    # shellcheck disable=SC2086
    timeout --foreground "$timeout_s" \
        qemu-system-x86_64 $accel -m "$VM_MEM" -smp "$VM_SMP" "${fw_args[@]}" \
            -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
            -display none -no-reboot -serial "file:${logfile}" "$@" || true
    [[ -n "$vars" ]] && rm -f "$vars"
}

# Boot the ISO (via extracted kernel) running a payload. Args:
#   boot_iso_with_payload <firmware> <timeout> <logfile> <payload-file> [extra qemu args...]
boot_iso_with_payload() {
    local fw="$1" timeout_s="$2" logfile="$3" payload="$4"; shift 4
    local iso label url tmpd
    iso="$(find_iso)"
    label="$(iso_label "$iso")"
    tmpd="$(mktemp -d)"
    extract_iso_boot "$iso" "$tmpd"
    url="$(guest_payload_url "$payload")"
    # cow_spacesize gives the live overlay room; console=ttyS0 sends boot
    # messages to our captured serial; script= triggers the payload on tty1.
    local cmdline="archisobasedir=arch archisolabel=${label} cow_spacesize=4G console=tty0 console=ttyS0,115200 script=${url}"
    _qemu "$fw" "$timeout_s" "$logfile" -- \
        -kernel "$KERNEL" -initrd "$INITRD" -append "$cmdline" \
        -drive "file=${iso},media=cdrom,readonly=on" \
        "$@"
    rm -rf "$tmpd"
}

# Boot an installed disk image (no ISO). Args:
#   boot_disk <firmware> <timeout> <logfile> <disk.qcow2> [extra qemu args...]
boot_disk() {
    local fw="$1" timeout_s="$2" logfile="$3" disk="$4"; shift 4
    _qemu "$fw" "$timeout_s" "$logfile" -- \
        -drive "file=${disk},if=virtio,format=qcow2" "$@"
}

expect_sentinel() {
    local logfile="$1" pattern="$2" desc="${3:-$2}"
    if grep -qa -- "$pattern" "$logfile"; then ok "found: ${desc}"; return 0; fi
    log "----- last 40 lines of serial ($(basename "$logfile")) -----"
    tail -n 40 "$logfile" >&2 || true
    log "-----------------------------------------------------------"
    fail "missing expected marker: ${desc}"
}
