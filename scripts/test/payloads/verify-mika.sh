#!/usr/bin/env bash
#
# Headless end-to-end verification: does Mika boot to the Plasma desktop, and does
# the auto-started Calamares launch and load ALL its modules (especially the users
# page that was failing)? Delivered via script= and run on tty1 (multi-user). Arms
# a transient capturer (IgnoreOnIsolate=yes, so it survives the switch to graphical)
# that waits for the desktop + auto-started Calamares, then dumps a verdict to the
# serial port the host captures. No display / clicking needed.
exec >/dev/ttyS0 2>&1
echo "MIKA_VERIFY_START"

systemd-run --unit=mika-verify --collect -p IgnoreOnIsolate=yes --quiet \
  /usr/bin/bash -c '
    exec >/dev/ttyS0 2>&1
    sleep 85   # desktop + mika autologin + autostart (sleep 3) + calamares module load
    echo "===== [1] display-manager (sddm) active? ====="
    printf "  is-active: "; systemctl is-active display-manager.service 2>&1
    echo "===== [2] graphical session (expect user=mika, type=x11, seat0) ====="
    loginctl --no-pager 2>&1
    for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk "{print \$1}"); do
      echo "  -- session $s --"
      loginctl show-session "$s" -p Name -p User -p Type -p Class -p Active -p State 2>&1 | sed "s/^/    /"
    done
    echo "===== [3] desktop + installer processes actually running? ====="
    ps -e -o comm= 2>&1 | grep -iE "^(Xorg|X|kwin_x11|kwin|plasmashell|startplasma|calamares|pkexec)$" | sort -u | sed "s/^/  running: /" \
      || echo "  !!! none of Xorg/kwin/plasmashell/calamares are running"
    echo "===== [4] Calamares session.log (pkexec runs it as root -> /root/.cache) ====="
    cln=""
    for f in /root/.cache/calamares/session.log /home/mika/.cache/calamares/session.log; do [ -f "$f" ] && cln="$f"; done
    if [ -n "$cln" ]; then
      echo "  found: $cln"
      echo "  --- module-load + failure/error lines ---"
      grep -inE "Loading|module|users|failed|cannot|could not|no such|error|warning|exception|abort|fatal" "$cln" 2>&1 | tail -90 | sed "s/^/    /"
      echo "  --- did it reach view steps / the users (Create User) page? ---"
      grep -inE "ViewStep|view step|users|usersq|Create User|welcome|partition|added view" "$cln" 2>&1 | tail -25 | sed "s/^/    /"
      echo "  --- tail of session.log ---"
      tail -25 "$cln" 2>&1 | sed "s/^/    /"
    else
      echo "  !!! NO Calamares session.log -> Calamares never started"
    fi
    echo "===== [5] journal: any sddm/plasma/calamares/pkexec/polkit failures ====="
    journalctl -b --no-pager 2>&1 | grep -iE "sddm|startplasma|kwin|plasmashell|calamares|pkexec|polkit|\(EE\)|segfault|core-dump|Loading failed|authentication failure|Failed to start" | tail -50 | sed "s/^/  /"
    echo "MIKA_VERIFY_OK"
    sync; systemctl poweroff -i 2>/dev/null || poweroff -f
  '

echo "MIKA_VERIFY: armed transient capturer; isolating graphical.target ..."
systemctl --no-block isolate graphical.target
