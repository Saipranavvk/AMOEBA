/* Minimal random-instruction-insertion trace demo (AMOEBA).
 *
 * A deliberately tiny program -- roughly 100 retired instructions including the
 * startup code -- so the retirement trace is short enough to read line by line.
 * It prints nothing itself; all output comes from the RTL trace, which keeps the
 * log free of UART polling loops.
 *
 * Build the simulator with +define+ECE411_RETIRE_TRACE to get one line per retired
 * instruction, real and dummy interleaved in retirement order.  Add
 * +define+ECE411_DUMMY_TRACE as well to also see captures and injections at the
 * point they happen in Decode.
 *
 * Insertion is enabled only inside main, so the startup code retires clean first
 * and the dummies start appearing partway down the trace.
 *
 * Same medlow constraints as tc_rand_instr_insert.c: no string literals, no
 * globals, no linker symbols, so it builds without -mcmodel=medany even though the
 * image loads at 0x80000000.
 *
 *   riscv64-unknown-elf-gcc -march=rv64gc -mabi=lp64d -O2 -nostdlib \
 *       -T bin/link.ld bin/startup.s \
 *       testcode/isa_level_testing/tc_insert_trace.c \
 *       -o testcode/isa_level_testing/tc_insert_trace.elf
 */

#include <stdint.h>

#define RAND_INSTR_INSERT_FREQ 0x7c0
#define TOHOST (*(volatile uint64_t *)0x80800000UL)

static inline void set_insert_freq(uint64_t n) {
    __asm__ volatile ("csrw %0, %1" :: "i"(RAND_INSTR_INSERT_FREQ), "r"(n));
}

static void __attribute__((noreturn)) sim_exit(uint64_t code) {
    TOHOST = (code << 1) | 1;
    /* Monitor halt encoding (slti x0, x0, -256), same as bin/startup.s uses. */
    for (;;) __asm__ volatile ("slti x0, x0, -256");
}

int main(void) {
    uint64_t a = 3, b = 5, c = 0;

    /* Hide the initial values from the optimizer, otherwise -O2 constant-folds the
     * whole chain below into a single "li" and there is nothing left to trace. */
    __asm__ volatile ("" : "+r"(a), "+r"(b));

    /* Divider period 1: a strobe every cycle, injected with probability 1/2.  This
     * is the maximum rate, which a program this short needs -- the enabled window is
     * only a few dozen cycles and the first strobe can never inject (nothing has
     * been captured yet), so a slower divider leaves too few opportunities for any
     * dummy to appear at all. */
    set_insert_freq(1);

    /* A straight-line dependent chain, long enough to keep insertion enabled for a
     * useful number of cycles.  Every operation here is OP or OP-IMM, so all of them
     * are valid capture candidates for the stage 1 filter. */
    a = a + b;   c = a ^ b;   a = a << 2;  b = b | c;
    c = c + a;   a = a - b;   b = b & 0x3f; c = c ^ a;
    a = a + c;   b = b + a;   c = c << 1;  a = a ^ c;
    b = b - c;   c = c | a;   a = a + b;   b = b ^ c;
    c = c - a;   a = a & 0xffff; b = b + c; c = c ^ b;
    a = a + c;   b = b << 3;  c = c + a;   a = a ^ b;

    set_insert_freq(0);

    /* Insertion must not have perturbed any of it: a=26, b=104, c=213. */
    sim_exit((a + b + c) == 343 ? 0 : 1);
}
