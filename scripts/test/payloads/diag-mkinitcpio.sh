#!/usr/bin/env bash
#
# A/B proof for the Calamares "ERROR: '/dev' must be mounted!" fix.
#
# Calamares runs mkinitcpio inside a PLAIN chroot whose mounts come from
# mount.conf. The OLD mount.conf mounted /dev with `--bind`; the NEW one mounts
# the kernel devtmpfs singleton (exactly what arch-chroot does). mkinitcpio 41
# gates the build on `[[ -e /dev/fd ]]` (mkinitcpio:1051) and dies with
# "/dev must be mounted!" if it is not satisfied.
#
# This payload sets up BOTH chroots on the live ISO and runs the REAL mkinitcpio
# in each, printing which one clears the /dev gate and builds an initramfs. It
# needs no rebuild and no scratch disk: it bind-mounts the live root as the
# throwaway "target" and only swaps how /dev is mounted. Verdict -> /dev/ttyS0.
exec >/dev/ttyS0 2>&1
echo "MKI_AB_START"
set +e

timeout 180 systemctl is-system-running --wait >/dev/null 2>&1 || true
echo "live /dev  : $(findmnt -no FSTYPE,SOURCE,TARGET /dev 2>&1)"
echo "live /dev/fd: $(ls -ld /dev/fd 2>&1)"
KSRC="/run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux"
echo "kernel src : $KSRC ($( [ -f "$KSRC" ] && echo present || echo MISSING ))"
echo

run_scenario() {            # $1 = label   $2 = command(s) to mount /dev
  local label="$1" devcmd="$2" T out
  T=$(mktemp -d)
  mount --bind / "$T"                       # throwaway target root (bash+mkinitcpio+modules)
  mount -t proc  proc "$T/proc"
  mount -t sysfs sys  "$T/sys"
  eval "$devcmd"                            # <-- the ONLY thing that differs A vs B
  [ -f "$KSRC" ] && cp -f "$KSRC" "$T/boot/vmlinuz-linux" 2>/dev/null
  echo "===== $label ====="
  echo -n "  chroot /dev is: "; findmnt -no FSTYPE,TARGET "$T/dev" 2>&1
  chroot "$T" /usr/bin/bash -c '
     [[ -e /proc/self/mountinfo ]] && echo "  gate /proc : OK" || echo "  gate /proc : MISSING"
     if [[ -e /dev/fd ]]; then echo "  gate /dev/fd: OK   (mkinitcpio:1051 passes)"
     else echo "  gate /dev/fd: MISSING  -> ERROR: /dev must be mounted!"; fi'
  echo "  -- real mkinitcpio -p linux (timeout 120s) --"
  out=$(timeout 120 chroot "$T" /usr/bin/mkinitcpio -p linux 2>&1)
  if echo "$out" | grep -qi "must be mounted"; then
     echo "  VERDICT: FAILED at the /dev gate  <<<<"
     echo "$out" | grep -i "must be mounted" | sed 's/^/    > /'
  elif echo "$out" | grep -qiE "Image generation successful|Generating.*initramfs"; then
     echo "  VERDICT: cleared /dev gate AND built the initramfs  <<<<"
     echo "$out" | grep -iE "Starting build|Image generation successful" | tail -2 | sed 's/^/    > /'
  else
     echo "  VERDICT: cleared /dev gate (build stopped for another reason)"
     echo "$out" | tail -4 | sed 's/^/    > /'
  fi
  umount -R "$T" 2>/dev/null; rmdir "$T" 2>/dev/null
  echo
}

run_scenario "A  OLD mount.conf   mount --bind /dev          (expect: FAIL)" \
             'mount --bind /dev "$T/dev"'

run_scenario "B  NEW mount.conf   mount -t devtmpfs udev /dev (expect: PASS)" \
             'mount -t devtmpfs udev "$T/dev" -o mode=0755,nosuid
              mkdir -p "$T/dev/pts" "$T/dev/shm"
              mount -t devpts devpts "$T/dev/pts" -o mode=0620,gid=5,nosuid,noexec 2>/dev/null
              mount -t tmpfs  shm    "$T/dev/shm" -o mode=1777,nosuid,nodev 2>/dev/null'

echo "MKI_AB_OK"
sync; systemctl poweroff -i 2>/dev/null || poweroff -f
