#!/usr/bin/env bash
#
# Definitive proof of the real cause of "==> ERROR: '/dev' must be mounted!":
# Calamares' mount module does `",".join(partition["options"])`. With the OLD
# scalar `options: bind` that yields the string "b,i,n,d", so Calamares actually
# ran `mount -o b,i,n,d /dev <target>/dev`, which FAILS (no real bind), leaving
# /dev unmounted -> mkinitcpio aborts at its `[[ -e /dev/fd ]]` gate. With the
# NEW list `options: [ bind ]` the join yields "bind" -> a correct bind mount.
#
# This payload unpacks the system once onto the scratch disk, then runs the REAL
# mkinitcpio twice: once mounting /dev with the buggy "b,i,n,d" options string
# (reproduces the failure) and once with "bind" (confirms the fix). Verdict ->
# /dev/ttyS0.
exec >/dev/ttyS0 2>&1
echo "DEVBUG_START"
set +e
timeout 180 systemctl is-system-running --wait >/dev/null 2>&1 || true

DISK=/dev/vda
SFS="/run/archiso/bootmnt/arch/x86_64/airootfs.sfs"
KSRC="/run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux"
echo "disk=$DISK  sfs=$([ -f "$SFS" ] && echo ok || echo MISS)  kernel=$([ -f "$KSRC" ] && echo ok || echo MISS)"

# ---- one-time: partition + format + mount root, then unpackfs ONCE ----
umount -R /mnt 2>/dev/null
wipefs -a "$DISK"        >/dev/null 2>&1
sgdisk --zap-all "$DISK" >/dev/null 2>&1
sgdisk -n1:0:+512M -t1:ef00 -c1:EFI "$DISK" >/dev/null 2>&1
sgdisk -n2:0:0     -t2:8300 -c2:ROOT "$DISK" >/dev/null 2>&1
partprobe "$DISK" 2>/dev/null; udevadm settle 2>/dev/null; sleep 1
mkfs.fat -F32 "${DISK}1" >/dev/null 2>&1
mkfs.ext4 -F  "${DISK}2" >/dev/null 2>&1
udevadm settle 2>/dev/null
[ -b "${DISK}1" ] && [ -b "${DISK}2" ] || { echo "ABORT: no partition nodes"; systemctl poweroff -i; exit; }
mount "${DISK}2" /mnt || { echo "ABORT: root mount failed"; systemctl poweroff -i; exit; }
mountpoint -q /mnt    || { echo "ABORT: /mnt not a real mount"; systemctl poweroff -i; exit; }
mkdir -p /mnt/boot && mount "${DISK}1" /mnt/boot
mkdir -p /mnt/proc /mnt/sys /mnt/dev /mnt/run
mount -t proc proc /mnt/proc; mount -t sysfs sys /mnt/sys; mount -t tmpfs tmpfs /mnt/run
echo "== unpackfs (once) =="
SRC=$(mktemp -d); mount -t squashfs -o ro "$SFS" "$SRC"
cp -a "${SRC}/." /mnt/ 2>/dev/null; umount "$SRC"; rmdir "$SRC" 2>/dev/null
cp -f "$KSRC" /mnt/boot/vmlinuz-linux 2>/dev/null
cat > /mnt/etc/mkinitcpio.conf.d/mika.conf <<'MKI'
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)
MKI

test_dev() {   # $1 = label   $2 = EXACT options string Calamares' ",".join produces
  local label="$1" opts="$2" out
  umount /mnt/dev 2>/dev/null
  echo ""
  echo "########## $label ##########"
  echo "  Calamares ran:  mount -o '$opts' /dev <target>/dev"
  mount -o "$opts" /dev /mnt/dev 2>&1 | sed 's/^/    mount says: /'
  if mountpoint -q /mnt/dev; then echo "  /mnt/dev mounted? YES"
  else echo "  /mnt/dev mounted? NO  (mount failed -> /dev stays the unpacked static dir)"; fi
  echo -n "  /mnt/dev/fd: "; ls -ld /mnt/dev/fd 2>&1 | tr -s ' '
  out=$(chroot /mnt /usr/bin/mkinitcpio -p linux 2>&1)
  if   echo "$out" | grep -qi "must be mounted"; then
       echo "  >>> mkinitcpio: *** /dev must be mounted! ***  (REPRODUCES the install failure)"
  elif echo "$out" | grep -qi "Image generation successful"; then
       echo "  >>> mkinitcpio: OK — initramfs built"
  else echo "  >>> mkinitcpio: other ->"; echo "$out" | tail -3 | sed 's/^/      /'; fi
}

test_dev "A  OLD  scalar  options: bind    -> join => 'b,i,n,d'" "b,i,n,d"
test_dev "B  NEW  list    options: [ bind ] -> join => 'bind'"   "bind"

echo "DEVBUG_OK"
sync; systemctl poweroff -i 2>/dev/null || poweroff -f
