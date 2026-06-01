#!/usr/bin/env bash
#
# Boot smoke-test payload. Delivered to the live ISO via `script=<url>` and
# executed by /root/.automated_script.sh on tty1. Its job: prove the live
# environment booted, then power off. All markers go to /dev/ttyS0 because
# that is what the headless harness captures.

exec >/dev/ttyS0 2>&1
echo "MIKA_SELFTEST_START"

# Give boot services a chance to settle (don't block forever if degraded).
timeout 120 systemctl is-system-running --wait >/dev/null 2>&1 || true

echo "kernel: $(uname -r)"
echo "systemd state: $(systemctl is-system-running 2>/dev/null || true)"

# The marker the harness greps for.
echo "MIKA_BOOT_OK"

sync
systemctl poweroff -i 2>/dev/null || poweroff -f
