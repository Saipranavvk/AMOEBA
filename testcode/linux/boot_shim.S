/*
 * Reset-vector shim.
 *
 * The core starts at RESET_VECTOR (0x80000000, pkg/config.vh) with the integer
 * register file uninitialised.  Verilator's --x-initial fast happens to zero
 * it, but VCS does not, and OpenSBI's _start hangs if a0 is not the boot
 * hartid.  Rather than depend on simulator X-handling, set a0 explicitly and
 * jump to firmware.
 *
 * a1 is zeroed for tidiness only: OpenSBI is built with FW_FDT_PATH, so it
 * overwrites a1 with the address of its built-in device tree regardless.
 */

#ifndef OPENSBI_ADDR
#define OPENSBI_ADDR 0x80001000
#endif

.section .text.init, "ax"
.globl _start
_start:
    li      a0, 0                  /* boot hartid */
    li      a1, 0                  /* FDT pointer; OpenSBI supplies its own */
    li      t0, OPENSBI_ADDR
    jr      t0
