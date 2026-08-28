/*
 * PID 1 for the Keystone boot test (K1).
 *
 * Extends testcode/linux/initramfs/init.S: rather than only proving userspace
 * runs, this proves the Keystone driver produced a *usable* device.
 *
 * Why open() and not a log line: the driver is built into the kernel, so its
 * module_init becomes a device_initcall that runs unconditionally.  If
 * misc_register() fails, Linux boots normally and the only symptom is that
 * /dev/keystone_enclave is absent -- exactly the silent failure the SM hit in
 * K0, where the code was linked but never ran.  Matching on the driver's
 * pr_info() would pass in that case.  Opening the node cannot.
 *
 * devtmpfs is mounted here rather than relying on CONFIG_DEVTMPFS_MOUNT, which
 * by design does not apply to initramfs.  The driver registers a misc device
 * with MISC_DYNAMIC_MINOR, so its minor is assigned at registration and a
 * static cpio node would break whenever it shifts.
 *
 * init must not return -- a PID 1 that exits panics the kernel.
 */

.equ __NR_mount,  40
.equ __NR_openat, 56
.equ __NR_write,  64

.equ AT_FDCWD,    -100
.equ O_WRONLY,    1
.equ O_RDWR,      2

/* .rodata precedes .text: `li` expands at assembly time and cannot take a
 * forward-referenced label difference. */
.section .rodata
devtmpfs: .string "devtmpfs"
devdir:   .string "/dev"
console:  .string "/dev/console"
ksdev:    .string "/dev/keystone_enclave"

ok:       .ascii  "AMOEBA_KEYSTONE_DRV_OK\n"
ok_end:
.equ ok_len, ok_end - ok

bad:      .ascii  "AMOEBA_KEYSTONE_DRV_FAIL\n"
bad_end:
.equ bad_len, bad_end - bad

.section .text
.globl _start
_start:
    /* mount("devtmpfs", "/dev", "devtmpfs", 0, NULL).  Failure is not fatal:
     * the cpio still carries a static /dev/console, so we can still report. */
    la      a0, devtmpfs
    la      a1, devdir
    la      a2, devtmpfs
    li      a3, 0
    li      a4, 0
    li      a7, __NR_mount
    ecall

    /* console fd -> s0, kept across the calls below */
    li      a0, AT_FDCWD
    la      a1, console
    li      a2, O_WRONLY
    li      a3, 0
    li      a7, __NR_openat
    ecall
    mv      s0, a0

    /* The actual K1 test: can we open the enclave device? */
    li      a0, AT_FDCWD
    la      a1, ksdev
    li      a2, O_RDWR
    li      a3, 0
    li      a7, __NR_openat
    ecall

    bltz    a0, 1f                 /* negative -> errno, device unusable */
    la      s1, ok
    li      s2, ok_len
    j       2f
1:  la      s1, bad
    li      s2, bad_len

2:  bltz    s0, 3f                 /* console open failed -- skip to fd 1 */
    mv      a0, s0
    mv      a1, s1
    mv      a2, s2
    li      a7, __NR_write
    ecall

3:  li      a0, 1                  /* stdout, if the kernel wired it up */
    mv      a1, s1
    mv      a2, s2
    li      a7, __NR_write
    ecall

4:  j       4b                     /* never exit: PID 1 returning is a panic */
