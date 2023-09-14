# base-iso

## Prerequisites

- archiso
- git

`yay -S archiso git`

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
