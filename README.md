## Required packages for building iso
- archiso & git

`sudo pacman -S archiso git`

## Installation and Build
```bash
git clone https://github.com/Mika-Project/base-iso
cd base-iso
sudo mkarchiso -v .
```

Two directories will be created (`work` and `out`).
You can find the ISO file inside out directory.

## Optional 
>to auto remove the `work` directory, you can build the ISO with command:

`sudo mkarchiso -v -r .`

>instead of `sudo mkarchiso -v .`



## Quicky Test the ISO using QEMU

- Install the optional dependencies qemu-desktop and edk2-ovmf.
`sudo pacman -S qemu-desktop edk2-ovmf`


### MBR
`run_archiso -i /path/to/archlinux-yyyy.mm.dd-x86_64.iso`

### UEFI

`run_archiso -u -i /path/to/archlinux-yyyy.mm.dd-x86_64.iso`

## Known-issues
- [ ] unable to read due to background
- [ ] No volume control