#!/usr/bin/env bash
#
# FAITHFUL reproduction of Calamares' install ordering, to find the real cause of
# "ERROR: '/dev' must be mounted!". Calamares does, in this order:
#   partition -> mount (API filesystems onto the EMPTY freshly-formatted root)
#             -> unpackfs (unsquash airootfs OVER it) -> chroot mkinitcpio
# We replicate exactly that on the scratch disk and print /dev/fd BEFORE and AFTER
# unpackfs, for the OLD (bind /dev) and NEW (devtmpfs /dev) mount styles, then run
# the real mkinitcpio in a plain chroot. Verdict -> /dev/ttyS0.
exec >/dev/ttyS0 2>&1
echo "CAL_REPRO_START"
set +e
timeout 180 systemctl is-system-running --wait >/dev/null 2>&1 || true

DISK=/dev/vda
SFS="/run/archiso/bootmnt/arch/x86_64/airootfs.sfs"
KSRC="/run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux"
echo "disk=$DISK  sfs=$([ -f "$SFS" ] && echo ok || echo MISSING)  kernel=$([ -f "$KSRC" ] && echo ok || echo MISSING)"

prep_disk() {
  umount -R /mnt 2>/dev/null
  wipefs -a "$DISK"                   >/dev/null 2>&1
  sgdisk --zap-all "$DISK"            >/dev/null 2>&1
  sgdisk -n1:0:+512M -t1:ef00 -c1:EFI "$DISK" >/dev/null 2>&1
  sgdisk -n2:0:0     -t2:8300 -c2:ROOT "$DISK" >/dev/null 2>&1
  partprobe "$DISK" 2>/dev/null; udevadm settle 2>/dev/null; sleep 1
  mkfs.fat -F32 "${DISK}1" >/dev/null 2>&1
  mkfs.ext4 -F  "${DISK}2" >/dev/null 2>&1
  udevadm settle 2>/dev/null
  # Hard gate: the rest of run() does `cp -a` of the whole system; if these
  # nodes are missing the cp would land on the live RAM overlay and OOM the VM.
  [ -b "${DISK}1" ] && [ -b "${DISK}2" ] || { echo "  !! partition nodes missing after prep_disk"; return 1; }
}

run() {                      # $1 = label   $2 = style: bind | devtmpfs
  local label="$1" style="$2" out rc
  echo ""
  echo "########## $label ##########"
  prep_disk || { echo "  >>> RESULT: SKIPPED (disk prep failed)"; return; }
  mount "${DISK}2" /mnt || { echo "  >>> RESULT: SKIPPED (root mount failed)"; return; }
  mountpoint -q /mnt   || { echo "  >>> RESULT: SKIPPED (/mnt is NOT a real disk mount — refusing cp)"; return; }
  mkdir -p /mnt/boot && mount "${DISK}1" /mnt/boot

  # ---- mount module: API filesystems on the EMPTY root, Calamares order ----
  mkdir -p /mnt/proc /mnt/sys /mnt/dev /mnt/run
  mount -t proc  proc /mnt/proc
  mount -t sysfs sys  /mnt/sys
  if [ "$style" = bind ]; then
      mount --bind /dev /mnt/dev
  else
      mount -t devtmpfs udev /mnt/dev -o mode=0755,nosuid
      mkdir -p /mnt/dev/pts /mnt/dev/shm
      mount -t devpts devpts /mnt/dev/pts -o mode=0620,gid=5,nosuid,noexec 2>/dev/null
      mount -t tmpfs  shm    /mnt/dev/shm -o mode=1777,nosuid,nodev 2>/dev/null
  fi
  mount -t tmpfs tmpfs /mnt/run
  echo -n "  /mnt/dev BEFORE unpackfs   : "; findmnt -no FSTYPE,TARGET /mnt/dev 2>&1
  echo -n "  /mnt/dev/fd BEFORE unpackfs: "; ls -ld /mnt/dev/fd 2>&1 | tr -s ' '

  # ---- unpackfs: unsquash airootfs OVER the mounted root, then copy vmlinuz ----
  SRC=$(mktemp -d); mount -t squashfs -o ro "$SFS" "$SRC"
  cp -a "${SRC}/." /mnt/ 2>/tmp/cperr; rc=$?
  umount "$SRC"; rmdir "$SRC" 2>/dev/null
  cp -f "$KSRC" /mnt/boot/vmlinuz-linux 2>/dev/null
  echo "  unpackfs cp rc=$rc ; cp errors mentioning /mnt/dev: $(grep -c '/mnt/dev' /tmp/cperr 2>/dev/null)"
  echo -n "  /mnt/dev AFTER unpackfs    : "; findmnt -no FSTYPE,TARGET /mnt/dev 2>&1
  echo -n "  /mnt/dev/fd AFTER unpackfs : "; ls -ld /mnt/dev/fd 2>&1 | tr -s ' '

  # ---- initcpio module: mkinitcpio in a PLAIN chroot ----
  cat > /mnt/etc/mkinitcpio.conf.d/mika.conf <<'MKI'
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)
MKI
  echo "  -- mkinitcpio -p linux (plain chroot) --"
  out=$(chroot /mnt /usr/bin/mkinitcpio -p linux 2>&1)
  if   echo "$out" | grep -qi "must be mounted"; then
       echo "  >>> RESULT: *** REPRODUCED *** $(echo "$out" | grep -i 'must be mounted' | head -1)"
  elif echo "$out" | grep -qi "Image generation successful"; then
       echo "  >>> RESULT: OK (initramfs built)"
  else
       echo "  >>> RESULT: other ->"; echo "$out" | tail -5 | sed 's/^/        /'
  fi
  umount -R /mnt 2>/dev/null
}

run "A  OLD shipped:  bind /dev      (mounted before unpackfs)" bind
run "B  NEW fix:      devtmpfs /dev  (mounted before unpackfs)" devtmpfs

echo "CAL_REPRO_OK"
sync; systemctl poweroff -i 2>/dev/null || poweroff -f
