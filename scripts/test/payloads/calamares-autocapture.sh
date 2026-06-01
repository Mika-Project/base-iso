#!/usr/bin/env bash
#
# Auto-capture payload for calamares-test.sh. Delivered via script= and run on
# tty1 in multi-user mode. It:
#   1. arms a transient systemd service that waits for Calamares' session.log and
#      streams it to /dev/ttyS0 (captured on the host) — marked IgnoreOnIsolate
#      so it SURVIVES the switch to the graphical target;
#   2. switches to graphical.target so the desktop comes up and the user can run
#      Calamares with the mouse only.
# Net effect: the full installer log is shipped to the host automatically, with
# no typing / copy-paste / networking needed inside the VM.
exec >/dev/ttyS0 2>&1
echo "=== MIKA AUTO-CAPTURE: arming Calamares log streamer ==="

# Transient streamer: survives `systemctl isolate graphical.target`, GC'd on exit.
systemd-run --unit=mika-logstream --collect -p IgnoreOnIsolate=yes --quiet \
  /usr/bin/bash -c '
    exec >/dev/ttyS0 2>&1
    echo "=== MIKA_LOGSTREAM: waiting for Calamares session.log ==="
    i=0
    while [ "$i" -lt 2400 ]; do
        f=$(ls /root/.cache/calamares/session.log /home/*/.cache/calamares/session.log 2>/dev/null | head -n1)
        if [ -n "$f" ]; then
            echo "=== MIKA_LOGSTREAM: streaming $f ==="
            exec tail -n +1 -F "$f"
        fi
        i=$((i+1)); sleep 1
    done
    echo "=== MIKA_LOGSTREAM: gave up waiting for Calamares log ==="
  '

echo "=== MIKA AUTO-CAPTURE: bringing up the desktop (graphical.target) ==="
systemctl --no-block isolate graphical.target
echo "=== MIKA AUTO-CAPTURE: done; SDDM/desktop should appear in a moment ==="
