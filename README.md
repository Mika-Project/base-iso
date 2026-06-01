# Mika Linux — base ISO

The build profile for **Mika Linux**: an Arch-based live ISO with the **KDE Plasma**
desktop and the **Calamares** graphical installer, built with
[archiso](https://wiki.archlinux.org/title/Archiso) (`mkarchiso`). Boot the ISO and
you get a live Plasma session that auto-launches Calamares to install Mika to disk.

---

## For users — make a bootable USB

1. **Build the ISO** (see [Build](#build)) or download one from
   [Releases](https://github.com/Mika-Project/base-iso/releases). It lands in `out/`.
2. **Flash it** to a USB stick — replace `/dev/sdX` with *your* stick:

```bash
lsblk -d -o NAME,SIZE,TRAN,MODEL          # find your USB (TRAN=usb)
sudo umount /dev/sdX* 2>/dev/null
sudo dd if="out/Mika Linux-"*.iso of=/dev/sdX bs=4M status=progress oflag=direct conv=fsync
sync
```

> [!WARNING]
> `dd` overwrites the **whole** disk. The wrong `/dev/sdX` will wipe it — confirm with
> `lsblk` first (your USB is the one with `TRAN=usb` and the right size).

3. **Boot it** and run the installer: **Erase disk → create your user → Install**.

---

## Build

Needs `archiso` + `git`:

```bash
sudo pacman -S --needed archiso git
git clone https://github.com/Mika-Project/base-iso
cd base-iso
sudo mkarchiso -v -w /var/tmp/mika-work -o out .
```

The finished ISO is written to `out/`. `-w` sets the work directory — keep it **on
disk** (not a RAM-backed `/tmp`) on low-RAM machines.

> [!IMPORTANT]
> `mkarchiso` needs a **fresh** work dir each run. Delete it first
> (`sudo rm -rf /var/tmp/mika-work`), or build with `-r` to auto-remove it:
> `sudo mkarchiso -v -r .`

> [!NOTE]
> This repo already ships `airootfs/etc/localtime`. Only if a build complains about a
> missing localtime, recreate it: `ln -sf /usr/share/zoneinfo/UTC airootfs/etc/localtime`.

---

## Test it in QEMU (no USB needed)

**Interactive** — a QEMU window you click through by hand:

```bash
sudo pacman -S --needed qemu-desktop edk2-ovmf
run_archiso -u -i out/*.iso          # UEFI
run_archiso    -i out/*.iso          # BIOS / MBR
```

**Automated / headless** — proves the ISO **boots** *and* **installs into a system
that itself boots**, entirely over a serial console (full docs in
[`scripts/test/README.md`](scripts/test/README.md)):

```bash
scripts/test/boot-test.sh uefi       # boot smoke test          (bios | uefi | both)
scripts/test/install-test.sh uefi    # scripted install, then boot the installed disk
scripts/test/verify-mika-run.sh uefi # boot to desktop + verify Calamares loads every module
```

On a RAM-tight machine (e.g. 15 GB, no swap) prefix any of them with `VM_MEM=2048`.

---

## Repo layout (for contributors)

| Path | What it is |
|------|-----------|
| `airootfs/` | The live/installed root filesystem overlay — configs, users, `/etc/skel`, branding. |
| `airootfs/etc/calamares/` | **The Calamares installer config**: `settings.conf` (module sequence) + `modules/*.conf`. |
| `airootfs/etc/sddm.conf.d/` | Display manager + live autologin. |
| `packages.x86_64` | Every package installed into the ISO. |
| `profiledef.sh` | archiso profile — ISO name/label and **`file_permissions`** (see gotchas). |
| `pacman.conf` | Pacman config used during the build; points at the custom **`mikalinux-repo`**. |
| `scripts/test/` | The headless QEMU build → boot → install test harness. |

Mika pulls a few packages it can't get from official Arch (the Calamares build and
some soname shims) from its own package repo,
**[mikalinux-repo](https://github.com/Mika-Project/mikalinux-repo)**.

---

## Gotchas worth knowing (these have bitten us)

- **`profiledef.sh` `file_permissions` resets every file to `0644`.** Any custom script
  that must stay executable in the ISO — e.g. `usr/local/bin/mika-grub-install`
  (Calamares' GRUB wrapper) — **must** be listed there with mode `755`, or the install
  aborts with "permission denied". A **trailing slash** on a directory entry
  (`["/home/mika/"]=...`) makes the chown **recursive**.
- **Calamares `mount.conf` `options:` must be a YAML *list*, never a bare scalar.**
  `options: bind` is mangled into the invalid mount option `b,i,n,d` (the `/dev` mount
  then fails and the install dies at `mkinitcpio`). Write `options: [ bind ]`.
- **`services-systemd.conf` `mandatory: true`** aborts the install if the unit/package
  isn't present — only mark a service mandatory if its package is in `packages.x86_64`.

---

## Continuous integration

`.github/workflows/iso-test.yml` builds the ISO and runs the headless boot + install
tests on a runner, so a change that breaks the build or the install is caught
automatically before it ships.
