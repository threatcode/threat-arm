#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Pinebook (64-bit)
# https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images for
# More information: https://www.kali.org/docs/arm/pinebook/
#

# Stop on error
set -e

# shellcheck disable=SC2154
# Load general functions
# shellcheck source=/dev/null
source ./common.d/functions.sh

# Hardware model
hw_model=${hw_model:-"pinebook"}
# Architecture
architecture=${architecture:-"arm64"}
# Variant name for image and dir build
variant=${variant:-"${architecture}"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load common variables
include variables
# Checks script environment
include check
# Packages build list
include packages
# Load automatic proxy configuration
include proxy_apt
# Execute initial debootstrap
debootstrap_exec http://http.kali.org/kali
# Enable eatmydata in compilation
include eatmydata
# debootstrap second stage
systemd-nspawn_exec eatmydata /debootstrap/debootstrap --second-stage
# Define sources.list
include sources.list
# APT options
include apt_options
# So X doesn't complain, we add kali to hosts
include hosts
# Set hostname
set_hostname "${hostname}"
# Network configs
include network
# Do not include wlan0 on a wireless only device, otherwise NetworkManager won't run
# wlan0 requires special editing of the /etc/network/interfaces.d/wlan0 file, to add the wireless network and ssid
#add_interface wlan0

# Copy directory bsp into build dir
status "Copy directory bsp into build dir"
cp -rp bsp "${work_dir}"-rp bsp "${work_dir}"

# Disable RESUME (suspend/resume is currently broken anyway!) which speeds up boot massively
mkdir -p ${work_dir}/etc/initramfs-tools/conf.d/
cat << EOF > ${work_dir}/etc/initramfs-tools/conf.d/resume
RESUME=none
EOF

# Third stage
cat <<EOF >"${work_dir}"/third-stage
#!/usr/bin/env bash
set -e
status_3i=0
status_3i=\$(grep '^status_stage3 ' \$0 | wc -l)

status_stage3() {
  status_3i=\$((status_3i+1))
  echo  " [i] Stage 3 (\${status_3i}/\${status_3t}): \$1"
}

status_stage3 'Update apt'
export DEBIAN_FRONTEND=noninteractive
eatmydata apt-get update

status_stage3 'Install core packages'
eatmydata apt-get -y install ${third_stage_pkgs}

status_stage3 'Install packages'
eatmydata apt-get install -y ${packages} || eatmydata apt-get install -y --fix-broken

status_stage3 'Install desktop packages'
eatmydata apt-get install -y ${desktop_pkgs} ${extra} || eatmydata apt-get install -y --fix-broken

status_stage3 'Clean up'
eatmydata apt-get -y --purge autoremove

status_stage3 'Linux console/keyboard configuration'
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

status_stage3 'Copy all services'
cp -p /bsp/services/all/*.service /etc/systemd/system/
cp -p /bsp/services/rpi/*.service /etc/systemd/system/

status_stage3 'Script mode wlan monitor START/STOP'
install -m755 /bsp/scripts/monstart /usr/bin/
install -m755 /bsp/scripts/monstop /usr/bin/

status_stage3 'Install the kernel packages'
eatmydata apt-get install -y dkms linux-image-arm64 u-boot-menu u-boot-sunxi

# The pinebook seems to always claim the filesystem is in use when attempting to resize it, and this causes
# parted to request a confirmation, but since we're doing this in a script, we don't actually get to
# Solution comes from a comment in https://bugs.launchpad.net/ubuntu/+source/parted/+bug/1270203.  This is
# new with parted 3.3+

status_stage3 'Copy script pinebook-resizerootfs'
install -m755 /bsp/scripts/pinebook-resizerootfs /usr/sbin/

status_stage3 'Since we handle it specially, sed the service so that we call pinebook-resizerootfs instead of rpi-resizerootfs'
sed -i -e 's/rpi/pinebook/' /etc/systemd/system/rpi-resizerootfs.service

status_stage3 'Enable rpi-resizerootfs first boot'
systemctl enable rpi-resizerootfs

status_stage3 'Generate SSH host keys on first run'
systemctl enable regenerate_ssh_host_keys

status_stage3 'Enabling ssh by putting ssh or ssh.txt file in /boot'
systemctl enable enable-ssh

status_stage3 'Allow users to use NetworkManager over ssh'
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

status_stage3 'Install ca-certificate'
cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

status_stage3 'Set a REGDOMAIN'
sed -i -e 's/REGDOM.*/REGDOMAIN=00/g' /etc/default/crda

status_stage3 'Enable login over serial'
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab

status_stage3 'Try and make the console a bit nicer. Set the terminus font for a bit nicer display'
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

status_stage3 'Fix startup time from 5 minutes to 15 secs on raise interface wlan0'
sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/g' "/usr/lib/systemd/system/networking.service"

status_stage3 'Enable runonce'
install -m755 /bsp/scripts/runonce /usr/sbin/
cp -rf /bsp/runonce.d /etc
systemctl enable runonce

status_stage3 'Install touchpad config file'
install -m644 /bsp/xorg/50-pine64-pinebook.touchpad.conf /etc/X11/xorg.conf.d/

status_stage3 'Add wifi firmware and driver, and attempt to build'
# so we don't need to build on first boot, which causes issues if people log in too soon
# Pull in the wifi and bluetooth firmware from anarsoul's git repository
git clone https://github.com/anarsoul/rtl8723bt-firmware
cd rtl8723bt-firmware
cp -a rtl_bt /lib/firmware/

status_stage3 'Need to package up the wifi driver'
# (it's a Realtek 8723cs, with the usual Realtek driver quality) still,
# so for now, we clone it and then build it inside the chroot
cd /usr/src/
git clone https://github.com/icenowy/rtl8723cs rtl8723cs-2020.02.27
cat << __EOF__ > /usr/src/rtl8723cs-2020.02.27/dkms.conf.orig
PACKAGE_NAME="rtl8723cs"
PACKAGE_VERSION="2020.02.27"

AUTOINSTALL="yes"

CLEAN[0]="make clean"

MAKE[0]="'make' -j4 ARCH=arm64 KVER=\${kernelver} KSRC=/lib/modules/\${kernelver}/build/"

BUILT_MODULE_NAME[0]="8723cs"

BUILT_MODULE_LOCATION[0]=""

DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless"
__EOF__

cat << __EOF__ > /usr/src/rtl8723cs-2020.02.27/dkms.conf
PACKAGE_NAME="rtl8723cs"
PACKAGE_VERSION="2020.02.27"

AUTOINSTALL="yes"

CLEAN[0]="make clean"

MAKE[0]="'make' -j4 ARCH=arm64 KVER=5.10.0-kali9-arm64 KSRC=/lib/modules/5.10.0-kali9-arm64/build/"

BUILT_MODULE_NAME[0]="8723cs"

BUILT_MODULE_LOCATION[0]=""

DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless"
__EOF__

cd /usr/src/rtl8723cs-2020.02.27
dkms install rtl8723cs/2020.02.27 -k 5.10.0-kali9-arm64

status_stage3 'Replace the conf file after we've built the module and hope for the best'
mv /usr/src/rtl8723cs-2020.02.27/dkms.conf.orig /usr/src/rtl8723cs-2020.02.27/dkms.conf

status_stage3 'Clean up dpkg.eatmydata'
rm -f /usr/bin/dpkg
dpkg-divert --remove --rename /usr/bin/dpkg
EOF

# Run third stage
chmod 0755 "${work_dir}"/third-stage
status "Run third stage"
systemd-nspawn_exec /third-stage

# Choose a locale
set_locale "$locale"
# Clean system
include clean_system
trap clean_build ERR SIGTERM SIGINT
# Define DNS server after last running systemd-nspawn
echo "nameserver ${nameserver}" > "${work_dir}"/etc/resolv.conf
# Disable the use of http proxy in case it is enabled
disable_proxy
# Reload sources.list
include sources.list
# Mirror & suite replacement
restore_mirror

# Set up some defaults for chromium, if the user ever installs it
mkdir -p ${work_dir}/etc/chromium/
cat << EOF > ${work_dir}/etc/chromium/default
#Options to pass to chromium
CHROMIUM_FLAGS="\
--disable-smooth-scrolling \
--disable-low-res-tiling \
--enable-low-end-device-mode \
--num-raster-threads=\$(nproc) \
--profiler-timing=0 \
--disable-composited-antialiasing \
"
EOF

cd "${current_dir}/"

# Calculate the space to create the image and create
make_image

# Create the disk partitions
status "Create the disk partitions"
parted -s ${current_dir}/${image_name}.img mklabel msdos
parted -s -a minimal ${current_dir}/${image_name}.img mkpart primary $fstype 32MiB 100%

# Set the partition variables
loopdevice=$(losetup --show -fP "${current_dir}/${image_name}.img")
rootp="${loopdevice}p1"

# Create file systems
status "Formatting partitions"
if [[ "$fstype" == "ext4" ]]; then
  features="^64bit,^metadata_csum"
elif [[ "$fstype" == "ext3" ]]; then
  features="^64bit"
fi
mkfs -O "$features" -t "$fstype" -L ROOTFS "${rootp}"

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root/
mount "${rootp}" "${base_dir}"/root

# We do this here because we don't want to hardcode the UUID for the partition during creation
# systemd doesn't seem to be generating the fstab properly for some people, so let's create one
status "/etc/fstab"
cat <<EOF >"${work_dir}"/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
UUID=$(blkid -s UUID -o value ${rootp})  /               $fstype    defaults,noatime  0       1
EOF

# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot
# We do this down here because we don't know the UUID until after the image is created
sed -i -e "0,/root=.*/s//root=UUID=$(blkid -s UUID -o value ${rootp}) rootfstype=$fstype console=ttyS0,115200 console=tty1 consoleblank=0 rw quiet rootwait/g" ${work_dir}/boot/extlinux/extlinux.conf
# And we remove the "Debian GNU/Linux because we're Kali"
sed -i -e "s/Debian GNU\/Linux/Kali Linux/g" ${work_dir}/boot/extlinux/extlinux.conf

status "Rsyncing rootfs into image file"
rsync -HPavz -q "${work_dir}"/ "${base_dir}"/root/
sync

# Adapted from the u-boot-install-sunxi64 script
dd conv=notrunc if=${work_dir}/usr/lib/u-boot/pinebook/sunxi-spl.bin of=${loopdevice} bs=8k seek=1
dd conv=notrunc if=${work_dir}/usr/lib/u-boot/pinebook/u-boot-sunxi-with-spl.fit.itb of=${loopdevice} bs=8k seek=5
sync

cd "${current_dir}/"

# Flush buffers and bytes - this is nicked from the Devuan arm-sdk
blockdev --flushbufs "${loopdevice}"
python -c 'import os; os.fsync(open("'${loopdevice}'", "r+b"))'

# Unmount filesystem
status "Unmount filesystem"
umount -l "${rootp}"

# Check filesystem
status "Check filesystem"
e2fsck -y -f "$rootp"

# Remove loop devices
status "Remove loop devices"
kpartx -dv "${loopdevice}" 
losetup -d "${loopdevice}"

# Compress image compilation
include compress_img

# Clean up all the temporary build stuff and remove the directories
# Comment this out to keep things around if you want to see what may have gone wrong
clean_build
