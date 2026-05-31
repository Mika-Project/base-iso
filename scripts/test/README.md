# Mika ISO test harness

Build → boot → install, all in QEMU, with no USB stick and no test laptop.
The goal: on every push, prove that a change still produces an ISO that
**boots** and **installs into a system that itself boots** — in both BIOS and
UEFI mode.

Everything here is plain `bash` + `qemu`, so the exact same scripts run on a
developer machine and on any CI runner.

## What's here

| Script | Stage | What it proves |
|--------|-------|----------------|
| `run.sh` | — | Interactive boot of the ISO in a QEMU window (manual poke-around). |
| `boot-test.sh` | Boot smoke | The ISO boots headless (BIOS+UEFI) and the live env comes up. |
| `install-test.sh` | Install + post-install | A scripted install onto a blank disk succeeds, and the **installed** disk boots to a login prompt. |
| `payloads/selftest.sh` | — | Runs inside the live ISO; prints `MIKA_BOOT_OK`. |
| `payloads/install.sh` | — | Runs inside the live ISO; partitions, copies the rootfs, installs GRUB, prints `MIKA_INSTALL_OK`. |
| `lib.sh` | — | Shared helpers (sourced, not run). |

## How it works

1. **Build** the ISO as usual (`sudo mkarchiso -v .`) — output lands in `out/`.
2. The harness extracts the kernel + initramfs from the ISO and boots them
   with `-kernel/-initrd/-append`, because archiso sets its cmdline from the
   bootloader *inside* the ISO and we need to inject `script=`. archiso locates
   its squashfs via `archisolabel=` (read from the ISO with `blkid`).
3. The `script=<url>` cmdline triggers the ISO's existing
   `/root/.automated_script.sh`, which downloads and runs a **payload** from a
   throwaway HTTP server on the host (reachable from the guest at `10.0.2.2`).
   This keeps all test code **out of the production ISO**.
4. Payloads echo their result markers to `/dev/ttyS0`, which the harness
   captures as the headless serial log and greps for the marker.

## Run it locally

Prereqs (Arch): `sudo pacman -S qemu-desktop edk2-ovmf xorriso python`
KVM (`/dev/kvm`) is used automatically when present; without it QEMU falls back
to slow TCG emulation, so the scripts still work in a plain container.

```bash
# after a build:
scripts/test/boot-test.sh            # BIOS + UEFI smoke test
scripts/test/boot-test.sh uefi       # just UEFI
scripts/test/install-test.sh uefi    # scripted install + boot the result
scripts/test/run.sh uefi             # open it in a window and click around
```

Point at a specific ISO with `ISO=/path/to/x.iso scripts/test/boot-test.sh`.
Tunables (env vars): `VM_MEM`, `VM_SMP`, `DISK_SIZE`, `BOOT_TIMEOUT`,
`INSTALL_TIMEOUT`, `POSTINSTALL_TIMEOUT`.

## CI wiring (decide later — both options work)

The scripts are runner-agnostic; the only requirement for *fast* runs is
access to `/dev/kvm`. A starting workflow lives at
`.github/workflows/iso-test.yml` (manual `workflow_dispatch` for now so it
doesn't fire unexpectedly). Two ways to host it:

* **Self-hosted Arch runner** (you already have one in `main.yml`): build with
  `mkarchiso`, then run the harness directly. Make sure the runner user can
  read/write `/dev/kvm` (add it to the `kvm` group) for speed.
* **GitHub-hosted `ubuntu-latest`**: run `mkarchiso` inside a privileged
  `archlinux:latest` container, then run the harness. GitHub's larger Linux
  runners expose nested KVM; on standard runners it falls back to TCG (slow but
  green).

## Known sticking points (validate on first real run)

This harness was written from the repo layout; the **live-rootfs → installed**
conversion in `payloads/install.sh` is the part most likely to need tuning the
first time, because turning an archiso live root into a bootable installed
system has edge cases (initramfs hooks, GRUB target, fstab). The boot smoke
test is the simpler, higher-confidence gate; treat the install test as the
piece to iterate on. If a stage fails, the harness dumps the last 40 lines of
the guest serial log to help diagnose.
