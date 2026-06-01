#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="Mika Linux"
iso_label="project-mika_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Mika Linux <https://luciousdev.nl>"
iso_application="Mika Linux Live/Rescue CD"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
           'uefi-ia32.grub.esp' 'uefi-x64.grub.esp'
           'uefi-ia32.grub.eltorito' 'uefi-x64.grub.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/gshadow"]="0:0:400"
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/home/mika/"]="1000:1000:0750"
  ["/etc/polkit-1/rules.d"]="0:0:750"
  ["/etc/sudoers.d"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  # mkarchiso resets every airootfs file to 0644 unless it is listed here, even
  # if it is 0755 in the source tree. mika-grub-install is Calamares' grubInstall
  # wrapper (bootloader.conf) and is exec'd DIRECTLY during install — without the
  # exec bit the bootloader step fails with "permission denied" and the whole
  # install aborts. MUST stay listed. (script.sh + mikadiagnostic/* are chmod'd
  # by shellprocess-final at install time, so they self-heal and need no entry.)
  ["/usr/local/bin/mika-grub-install"]="0:0:755"
)