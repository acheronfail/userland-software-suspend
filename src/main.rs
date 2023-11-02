fn main() {
    // <setup>
    // make sure snapshot and resume device fds are above 2 (not sure why)
    // mlockall myself?
    // mount tmpfs into /proc/%d/
    // stat resume device to check it exists
    // if !S_ISBLK(stat_buf.st_mode) error
    // chdir into /proc/%d/
    // mknod("resume", S_IFBLK | 0600, stat_buf.st_rdev)
    // resume_fd = open("resume", O_RDWR);
    // stat /dev/snapshot to check it exists
    // if !S_ISCHR(stat_buf.st_mode) error
    // snapshot_fd = open(/dev/snapshot, O_RDONLY)

    // <set swap file>
    // if ! set_swap_file error

    // <console>
    // vt_fd = prepare_console(&orig_vc, &suspend_vc);
    // lock_vt()

    // <printk>
    // modify kernel log level

    // <swappiness>
    // swappiness_file = fopen("/proc/sys/vm/swappiness", "r+");
    // save swappiness
    // set new swappiness

    // sync

    // <rlimit>
    // rlim.rlim_cur = 0;
    // rlim.rlim_max = 0;
    // setrlimit(RLIMIT_NOFILE, &rlim);
    // setrlimit(RLIMIT_NPROC, &rlim);
    // setrlimit(RLIMIT_CORE, &rlim);

    // <suspend>
    //  if ! check_free_swap error
    //  freeze(/dev/snapshot)
    //  platform_prepare (to check shutdown method with ioctl)
    //  set_image_size
    //  in_suspend = atomic_snapshot
    //  if !in_suspend
    //      free_snapshot(/dev/snapshot)
    //      unfreeze(/dev/snapshot) return
    //  else write_image(): see <write_image>
    //      if err: free_swap_pages(), free_snapshot(/dev/snapshot)
    //      close(resume_fd)
    //      suspend_shutdown(/dev/snapshot): reboot/poweroff/etc

    // <write_image>
    // get_swap_page(): allocate swap page for userland header (ioctl) -- I believe we manage this header
    // get_image_size(): if this doesn't work, read it from /dev/snapshot (sizeof swsusp_info )
    // if !enough_swap(): error
    // if !preallocate_swap(): error
    // save_image(): see <save_image>
    // fsync(resume_fd)
    // write header to resume_fd?
    // fsync(resume_fd)
    // mark_swap(resume_fd)
    // fsync(resume_fd)

    // <save_image>
    // read from (/dev/snapshot) in page_size increments and write to (resume_fd)
    //  (look at uswsusp 72eb70a60ea537998a3d55fdd009a17267d346c7's message for details on speeding this up with threads)
    // save extents? (in an additional zeroed out swap page at the end?)

    // <restore swappiness>
    // <restore printk>
    // <unlock vt>
    // <chdir />
    // <umount /prod/%d/>

    println!("Hello, world!");
}
