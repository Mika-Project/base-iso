#!/usr/bin/env bash
#
# Headless diagnostic: why doesn't the X11/Plasma desktop render?
# Delivered via script= and run on tty1 in multi-user mode. It:
#   1. arms a transient systemd unit (IgnoreOnIsolate=yes, so it SURVIVES the
#      switch to graphical.target) that waits ~50s for SDDM to start X and
#      autologin `mika` into the plasmax11 session (or fail trying), then dumps
#      every relevant log — SDDM session log, Xorg log, journal (sddm/X/kwin/
#      plasma/gl/drm/pam), DRM nodes, failed units — to /dev/ttyS0 (captured on
#      the host) and powers off;
#   2. isolates graphical.target so SDDM actually runs.
# Net effect: the real reason the desktop fails is shipped to the host with no
# typing / clicking / networking inside the VM. Purely a test artifact.
exec >/dev/ttyS0 2>&1
echo "MIKA_DESKDIAG_START"

systemd-run --unit=mika-deskdiag --collect -p IgnoreOnIsolate=yes --quiet \
  /usr/bin/bash -c '
    exec >/dev/ttyS0 2>&1
    sleep 50
    echo "===== display-manager status ====="
    systemctl status display-manager.service --no-pager -l 2>&1 | head -25
    echo "===== systemctl --failed ====="
    systemctl --failed --no-pager 2>&1
    echo "===== /dev/dri (DRM render nodes) ====="
    ls -l /dev/dri/ 2>&1
    echo "===== loginctl sessions ====="
    loginctl --no-pager 2>&1
    echo "===== SDDM session logs (mika) ====="
    for f in /home/mika/.local/share/sddm/xorg-session.log \
             /home/mika/.local/share/sddm/wayland-session.log \
             /home/mika/.xsession-errors \
             /var/lib/sddm/.local/share/sddm/*.log; do
      [ -f "$f" ] && { echo "--- $f ---"; tail -n 60 "$f" 2>&1; }
    done
    echo "===== Xorg log (errors/warnings) ====="
    for f in /var/log/Xorg.0.log /home/mika/.local/share/xorg/Xorg.0.log; do
      [ -f "$f" ] && { echo "--- $f ---"; grep -iE "\(EE\)|\(WW\)|fatal|no screens|abort|modeset|glamor|fail" "$f" 2>&1 | tail -40; }
    done
    echo "===== journal (sddm/X/kwin/plasma/gl/drm/pam/errors) ====="
    journalctl -b --no-pager 2>&1 | grep -iE "sddm|xorg|startplasma|kwin|plasmashell|plasma_session|wayland|drm|kms|opengl|egl|gbm|libgl|swrast|llvmpipe|\(EE\)|fatal|segfault|core-dump|authentication|pam_|not meant to be run as root|cannot open|no screens found|permission denied" | tail -150
    echo "MIKA_DESKDIAG_OK"
    sync
    systemctl poweroff -i 2>/dev/null || poweroff -f
  '

echo "MIKA_DESKDIAG: armed transient capturer; isolating graphical.target ..."
systemctl --no-block isolate graphical.target
