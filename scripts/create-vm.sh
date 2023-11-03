#!/usr/bin/env bash

set -euxo pipefail

## setup
mountpoint="tmp/mnt"
image_file="tmp/vm.raw"
vm_disk="$1"
vm_kernel="$2"
vm_initrd="$3"
swap_offset="$4"

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
LC_ALL=C sudo pacstrap -cK "$mountpoint" base base-devel linux linux-firmware git rustup vim networkmanager sudo openssh
genfstab -U "$mountpoint" | grep -v $(swapon --show=NAME --noheadings) | sudo tee -a "${mountpoint}/etc/fstab"

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
chroot_cmd "sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems uresume fsck)/' /etc/mkinitcpio.conf"
# accounts
chroot_cmd "echo 'root:vm' | chpasswd"
chroot_cmd "echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers"
chroot_cmd "useradd -m -G wheel vm"
chroot_cmd "echo 'vm:vm' | chpasswd"
chroot_cmd "chown -R vm:vm /home/vm"
# create swap
sudo dd if=/dev/zero of="$mountpoint/swapfile" bs=1M count=512 status=progress
sudo chmod 0600 "$mountpoint/swapfile"
sudo mkswap -U clear "$mountpoint/swapfile"
echo '/swapfile none swap defaults 0 0' | sudo tee -a "$mountpoint/etc/fstab"
chroot_cmd "filefrag -v /swapfile | head -n4 | tail -1 | awk '{ print substr(\$4, 1, length(\$4) - 2) }' > /swapfile_offset"
# AUR helper
chroot_cmd "su - vm -c 'git clone https://aur.archlinux.org/paru-bin.git'"
chroot_cmd "su - vm -c 'cd paru-bin && makepkg --noconfirm --install --syncdeps'"
# uswswup-git
chroot_cmd "su - vm -c 'paru -S --noconfirm uswsusp-git'"
chroot_cmd 'echo -e "resume pause = 5\nresume device = /dev/sda1\nresume offset = $(cat /swapfile_offset)" > /etc/suspend.conf'
chroot_cmd "mkinitcpio -P"

## extract kernel and ramdisk for qemu
# NOTE: using the fallback image here because we're building this on the host and not in qemu, which
# results in the wrong modules being detected and the initramfs will fail to load the disks. Using
# the fallback image will mean everything will work.
# Another solution would be to build this image from within a qemu instance itself
# See: https://bbs.archlinux.org/viewtopic.php?pid=2129281#p2129281
sudo cp "${mountpoint}/boot/vmlinuz-linux"                "$vm_kernel"
sudo cp "${mountpoint}/boot/initramfs-linux-fallback.img" "$vm_initrd"
sudo cp "${mountpoint}/swapfile_offset"                   "$swap_offset"
sudo chown -R $USER:$USER "$vm_kernel"
sudo chown -R $USER:$USER "$vm_initrd"
sudo chown -R $USER:$USER "$swap_offset"

## run cleanup now
cleanup

# produce finalised image for qemu
qemu-img convert -f raw -O qcow2 "${image_file}" "${vm_disk}"
