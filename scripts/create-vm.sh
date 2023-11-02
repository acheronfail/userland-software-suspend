#!/usr/bin/env bash

set -euxo pipefail

# TODO: create a swapfile to hibernate into
# TODO: run this script inside qemu using the archiso, so modules are built correctly, and the host doesn't influence the build

## setup
mountpoint="tmp/mnt"
image_file="tmp/vm.raw"
vm_disk="$1"
vm_kernel="$2"
vm_initrd="$3"

mkdir -p "$mountpoint"
mkdir -p "$(dirname "$vm_disk")"

## create qemu image
qemu-img create -f raw "$image_file" 20G
loop="$(sudo losetup --show --find --partscan "$image_file")"

## handle cleanup
function cleanup() {
  sync
  # FIXME: why does it always say "target is busy", even though we're no longer using it?
  sudo umount --lazy "$mountpoint" || true
  sudo losetup --detach "$loop"
}
trap cleanup EXIT

## partition and format disk
sudo parted                 $loop mklabel msdos          2>/dev/null
sudo parted --align optimal $loop mkpart primary 0% 100% 2>/dev/null
sudo parted                 $loop set 1 boot on          2>/dev/null
part="${loop}p1"
sudo mkfs.ext4 "$part"
sudo mount "$part" "$mountpoint"

## bootstrap arch system
LC_ALL=C sudo pacstrap -cK "$mountpoint" base linux linux-firmware git rustup vim networkmanager sudo openssh
genfstab -U "$mountpoint" | sudo tee -a "${mountpoint}/etc/fstab"

## setup ssh
if [ -e "$HOME/.ssh/id_rsa.pub" ]; then
  sudo mkdir -p $mountpoint/root/.ssh/
  sudo cp "$HOME/.ssh/id_rsa.pub" "$mountpoint/root/.ssh/authorized_keys"
  sudo mkdir -p $mountpoint/home/vm/.ssh/
  sudo cp "$HOME/.ssh/id_rsa.pub" "$mountpoint/home/vm/.ssh/authorized_keys"
fi

## configure arch system
function chroot_cmd() {
  LC_ALL=C sudo arch-chroot "$mountpoint" sh -c "$1"
}
# network
chroot_cmd "systemctl enable NetworkManager"
chroot_cmd "systemctl enable sshd"
# clock
chroot_cmd "hwclock --systohc"
# locale
chroot_cmd "sed -i 's/^#en_AU.UTF-8 UTF-8\$/en_AU.UTF-8 UTF-8/' /etc/locale.gen"
chroot_cmd "sed -i 's/^#en_US.UTF-8 UTF-8\$/en_US.UTF-8 UTF-8/' /etc/locale.gen"
chroot_cmd "echo 'LANG=en_AU.UTF-8' > /etc/locale.conf"
chroot_cmd "locale-gen"
# hostname
chroot_cmd "echo 'vm' > /etc/hostname"
chroot_cmd "echo '127.0.1.1 vm.localdomain  vm' >> /etc/hosts"
# mkinitcpio
chroot_cmd "sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems resume fsck)/' /etc/mkinitcpio.conf"
chroot_cmd "mkinitcpio -P"
# accounts
chroot_cmd "echo 'root:vm' | chpasswd"
chroot_cmd "echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers"
chroot_cmd "useradd -m -G wheel vm"
chroot_cmd "echo 'vm:vm' | chpasswd"

## extract kernel and ramdisk for qemu
# NOTE: using the fallback image here because we're building this on the host and not in qemu, which
# results in the wrong modules being detected and the initramfs will fail to load the disks. Using
# the fallback image will mean everything will work.
# Another solution would be to build this image from within a qemu instance itself (that's what
# https://gitlab.archlinux.org/archlinux/arch-boxes does).
# See: https://bbs.archlinux.org/viewtopic.php?pid=2129281#p2129281
sudo cp "${mountpoint}/boot/vmlinuz-linux"                "$vm_kernel"
sudo cp "${mountpoint}/boot/initramfs-linux-fallback.img" "$vm_initrd"
sudo chown -R $USER:$USER "$vm_kernel"
sudo chown -R $USER:$USER "$vm_initrd"

## run cleanup now
cleanup

# produce finalised image for qemu
qemu-img convert -f raw -O qcow2 "${image_file}" "${vm_disk}"
