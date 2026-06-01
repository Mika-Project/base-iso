## Required packages for building iso

- archiso
- git

`sudo pacman -S archiso git`

## Installation and Build

### Option 1 (<16gb RAM)

> [!IMPORTANT]
> Before building please run the following commands to add a localtime file. (It does not have to be UTC timezone can also be something else.)

```bash
cd /path/to/archiso/configs/baseline/airootfs/etc
ln -sf /usr/share/zoneinfo/UTC localtime
```

```bash
git clone https://github.com/Mika-Project/base-iso
cd base-iso
sudo mkarchiso -v .
```

Two directories will be created (`work` and `out`).
You can find the ISO file inside out directory.

### if you have more RAM (>16gb)

```bash
git clone https://github.com/Mika-Project/base-iso
cd base-iso
sudo mkarchiso -v -w /tmp/archiso-tmp .
```

After building the iso make sure to remove the work/ directory or a different work directory that you've set yourself. If you don't do this you won't be able to build the ISO again.

You can find the ISO file inside out directory.

## Optional

> to auto remove the `work` directory, you can build the ISO with command:
> `sudo mkarchiso -v -r .`
> instead of `sudo mkarchiso -v .`

## Quicky Test the ISO using QEMU

Install the optional dependencies:
`sudo pacman -S qemu-desktop edk2-ovmf`

This opens the built ISO (in `out/` after a build) in a QEMU **window** so you can
click through the desktop and run the Calamares installer by hand:

- **UEFI:** `run_archiso -u -i out/*.iso`
- **BIOS/MBR:** `run_archiso -i out/*.iso`

## Automated boot & install testing (headless)

To prove an ISO actually **boots** and **installs into a system that itself boots**
— without a USB stick — use the QEMU test harness in
[`scripts/test/`](scripts/test/README.md):

```bash
scripts/test/boot-test.sh uefi      # boot smoke test
scripts/test/install-test.sh uefi   # scripted install, then boot the installed disk
scripts/test/run.sh uefi            # interactive boot in a window (like run_archiso)
```

On a RAM-tight machine (e.g. 15 GB, no swap) run them with `VM_MEM=2048`; the
harness keeps its scratch on disk automatically. See
[`scripts/test/README.md`](scripts/test/README.md) for details.
