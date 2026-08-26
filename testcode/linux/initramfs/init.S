/*
 * PID 1 for the boot test: print one string, then never exit.
 *
 * Written in raw assembly against the RISC-V Linux syscall ABI so the whole
 * userland needs no libc -- the bare-metal riscv64-unknown-elf- toolchain the
 * repo already uses is enough.  That keeps musl/glibc and buildroot entirely
 * off the critical path for "did we reach userspace".
 *
 * The kernel opens /dev/console as fds 0/1/2 for init, but only if the node
 * exists in the initramfs (see initramfs.spec).  We do not rely on that: open
 * the console explicitly and write to that descriptor, then write to fd 1 as
 * well, so a missing or renumbered descriptor still produces output.
 *
 * init must not return -- a PID 1 that exits panics the kernel, which would
 * turn a passing run into a confusing failure.  The final loop is safe because
 * ECE411_LINUX stops the testbench treating `j .` as a halt instruction.
 */

.equ __NR_openat, 56
.equ __NR_write,  64

.equ AT_FDCWD,    -100
.equ O_WRONLY,    1

/* Defined before .text: `li` expands at assembly time and cannot take a
 * forward-referenced label difference. */
.section .rodata
console: .string "/dev/console"
msg:     .ascii  "AMOEBA_LINUX_BOOT_OK\n"
msg_end:
.equ msg_len, msg_end - msg

.section .text
.globl _start
_start:
    li      a0, AT_FDCWD
    la      a1, console
    li      a2, O_WRONLY
    li      a3, 0
    li      a7, __NR_openat
    ecall

    blez    a0, 1f                 /* openat failed -- fall back to fd 1 */
    la      a1, msg
    li      a2, msg_len
    li      a7, __NR_write
    ecall

1:  li      a0, 1                  /* stdout, if the kernel wired it up */
    la      a1, msg
    li      a2, msg_len
    li      a7, __NR_write
    ecall

2:  j       2b                     /* never exit: PID 1 returning is a panic */
