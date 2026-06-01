#!/usr/bin/env bash
#
# Diagnostic: why doesn't the graphical desktop render? Boots to multi-user,
# arms a service that switches to graphical.target, waits for SDDM/Plasma to
# try, then dumps the relevant journal + SDDM logs + DRM state to the serial
# port (captured on the host). Fully headless.
exec >/dev/ttyS0 2>&1
echo "MIKA_DESKDIAG_START"

systemd-run --unit=mika-deskdiag --collect -p IgnoreOnIsolate=yes --quiet /usr/bin/bash -c '
  exec >/dev/ttyS0 2>&1
  sleep 55
  echo "===== /dev/dri (GPU/DRM devices) ====="; ls -l /dev/dri/ 2>&1
  echo "===== systemctl --failed ====="; systemctl --failed --no-pager 2>&1
  echo "===== display-manager status ====="; systemctl status display-manager --no-pager -l 2>&1 | head -25
  echo "===== loginctl sessions/seats ====="; loginctl 2>&1; loginctl seat-status seat0 2>&1 | head -15
  echo "===== journal: sddm/kwin/wayland/drm/gl/plasma/errors ====="
  journalctl -b --no-pager 2>&1 | grep -iE "sddm|kwin|wayland|drm |gl |opengl|egl|plasma|greeter|xorg|\(EE\)|failed|error|cannot|no provider|libGL|swrast|llvmpipe" | tail -90
  echo "===== sddm greeter / xorg-session logs ====="
  for f in /var/lib/sddm/.local/share/sddm/*.log /root/.local/share/sddm/*.log /home/*/.local/share/sddm/*.log; do
    [ -f "$f" ] && { echo "--- $f ---"; tail -30 "$f" 2>&1; }
  done
  echo "MIKA_DESKDIAG_OK"
  sync; systemctl poweroff -i 2>/dev/null || poweroff -f
'

echo "isolating graphical.target (SDDM will try to start the desktop) ..."
systemctl --no-block isolate graphical.target
