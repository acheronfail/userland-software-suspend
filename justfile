disk := "vm/disk.qcow2"
kernel := "vm/vmlinuz-linux"
initrd := "vm/initramfs-linux.img"
swap_offset := "vm/swap_offset"

_default:
  just -l

vm-create:
  ./scripts/create-vm.sh {{disk}} {{kernel}} {{initrd}} {{swap_offset}}
vm-clean:
  sudo umount --lazy tmp/mnt || true
  sudo rm -rf tmp

vm-loopback-on:
  if [ ! -e "tmp/vm.raw" ]; then just vm-create; fi
  sudo losetup --show --find --partscan "tmp/vm.raw"
vm-loopback-off loop:
  sudo losetup --detach "{{loop}}"

vm-run:
  qemu-system-x86_64 \
    -kernel {{kernel}} -initrd {{initrd}} -append "root=/dev/sda1 rw resume=/dev/sda1 resume_offset=$(cat "{{swap_offset}}") console=ttyS0" \
    -drive file="{{disk}}" \
    -cpu host \
    -enable-kvm \
    -m 2048 \
    -smp 2 \
    -display gtk,zoom-to-fit=on \
    -net nic -net user,hostfwd=tcp::2222-:22 \
    -nographic
