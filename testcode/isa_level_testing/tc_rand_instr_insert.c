/* Random dummy-instruction insertion (AMOEBA).
 *
 * rand_instr_insert_freq (CSR 0x7c0) holds the divider period N: a strobe every N
 * cycles, injected with probability 1/2, so a dummy lands every 2N cycles on average.
 * Writing 0 disables the feature.
 *
 * The feature is only correct if it is architecturally invisible, so this checks:
 *   C  the CSR reads back what was written
 *   R  an ALU-heavy loop gives identical results with insertion on and off
 *   I  minstret advances identically either way (dummies never retire)
 *   D  mcycle advances MORE with insertion on -- the evidence that dummies were
 *      actually inserted rather than the feature silently doing nothing
 *
 * Build the simulator with +define+ECE411_DUMMY_TRACE for a log line per capture
 * and per insertion.
 *
 * Deliberately self-contained: no test_utils.h, no string literals, no globals.
 * Every address here is a literal integer constant rather than a linker symbol, so
 * the file builds under the default medlow code model even though the image loads
 * at 0x80000000.  A string constant would land in .rodata above medlow's reach and
 * fail to link with "relocation truncated to fit: R_RISCV_HI20".
 *
 *   riscv64-unknown-elf-gcc -march=rv64gc -mabi=lp64d -O2 -nostdlib \
 *       -T bin/link.ld bin/startup.s \
 *       testcode/isa_level_testing/tc_rand_instr_insert.c \
 *       -o testcode/isa_level_testing/tc_rand_instr_insert.elf
 */

#include <stdint.h>

#define RAND_INSTR_INSERT_FREQ 0x7c0

/* Addresses as literals, never as linker symbols (see the medlow note above).
 * tohost matches the PROVIDE in bin/link.ld. */
#define UART_THR   (*(volatile uint8_t  *)0x10000000UL)
#define UART_LSR   (*(volatile uint8_t  *)0x10000005UL)
#define UART_THRE  (1u << 5)
#define TOHOST     (*(volatile uint64_t *)0x80800000UL)

static void uart_putc(char c) {
    while (!(UART_LSR & UART_THRE));
    UART_THR = (uint8_t)c;
}

/* Nibble arithmetic rather than a lookup table, which would be .rodata. */
static void uart_puthex(uint64_t v) {
    for (int i = 60; i >= 0; i -= 4) {
        unsigned d = (unsigned)((v >> i) & 0xf);
        uart_putc(d < 10 ? (char)('0' + d) : (char)('a' + d - 10));
    }
}

/* One line per check: "<id>=P" or "<id>=F".  Returns 1 on failure so the caller can
 * accumulate in a local -- a static counter would live in .bss and need exactly the
 * kind of absolute relocation this file is avoiding. */
static int report(char id, int ok) {
    uart_putc(id);
    uart_putc('=');
    uart_putc(ok ? 'P' : 'F');
    uart_putc('\n');
    return ok ? 0 : 1;
}

static void __attribute__((noreturn)) sim_exit(uint64_t code) {
    TOHOST = (code << 1) | 1;
    /* Monitor halt encoding (slti x0, x0, -256), same as bin/startup.s uses. */
    for (;;) __asm__ volatile ("slti x0, x0, -256");
}

static inline void set_insert_freq(uint64_t n) {
    __asm__ volatile ("csrw %0, %1" :: "i"(RAND_INSTR_INSERT_FREQ), "r"(n));
}

static inline uint64_t get_insert_freq(void) {
    uint64_t v;
    __asm__ volatile ("csrr %0, %1" : "=r"(v) : "i"(RAND_INSTR_INSERT_FREQ));
    return v;
}

static inline uint64_t read_cycle(void) {
    uint64_t c;
    __asm__ volatile ("rdcycle %0" : "=r"(c));
    return c;
}

static inline uint64_t read_instret(void) {
    uint64_t c;
    __asm__ volatile ("rdinstret %0" : "=r"(c));
    return c;
}

/* Shifts, adds and xors only, so nearly every instruction here is a valid capture
 * candidate for the ALU-class filter.  noinline keeps the two calls identical. */
static uint64_t __attribute__((noinline)) mix_loop(void) {
    uint64_t acc = 0;
    for (int i = 0; i < 256; i++) {
        uint64_t x = (uint64_t)i;
        x += (x << 10);
        x ^= (x >> 6);
        x += (x << 3);
        x ^= (x >> 11);
        x += (x << 15);
        acc ^= x + (acc << 5) + (acc >> 2);
    }
    return acc;
}

/* The measured window must contain exactly the same instruction sequence in both
 * runs, so the CSR is programmed outside it and only its value differs. */
static uint64_t __attribute__((noinline))
measure(uint64_t freq, uint64_t *cycles, uint64_t *instrs) {
    uint64_t r, i0, i1, c0, c1;

    set_insert_freq(freq);
    c0 = read_cycle();  i0 = read_instret();
    r  = mix_loop();
    i1 = read_instret(); c1 = read_cycle();
    set_insert_freq(0);

    *cycles = c1 - c0;
    *instrs = i1 - i0;
    return r;
}

int main(void) {
    uint64_t golden, checked;
    uint64_t instr_off, instr_on, cyc_off, cyc_on;
    int csr_ok, fails = 0;

    /* C: the CSR holds what is written and can be turned back off. */
    set_insert_freq(0);
    csr_ok  = (get_insert_freq() == 0);
    set_insert_freq(8);
    csr_ok &= (get_insert_freq() == 8);
    set_insert_freq(1024);
    csr_ok &= (get_insert_freq() == 1024);
    set_insert_freq(0);
    csr_ok &= (get_insert_freq() == 0);
    fails += report('C', csr_ok);

    golden  = measure(0, &cyc_off, &instr_off);   /* insertion disabled */
    checked = measure(8, &cyc_on,  &instr_on);    /* dummy every ~16 cycles */

    fails += report('R', checked == golden);
    fails += report('I', instr_on == instr_off);

    /* If no dummy was ever inserted the cycle counts would be near-identical; the
     * extra cycles are the insertions.  A failure here means insertion is not
     * happening, not that architectural state was corrupted. */
    fails += report('D', cyc_on > cyc_off);

    /* cycles off, cycles on, retired instructions -- for eyeballing the rate. */
    uart_putc('c'); uart_putc(':'); uart_puthex(cyc_off);   uart_putc('\n');
    uart_putc('C'); uart_putc(':'); uart_puthex(cyc_on);    uart_putc('\n');
    uart_putc('i'); uart_putc(':'); uart_puthex(instr_off); uart_putc('\n');

    sim_exit(fails != 0 ? 1 : 0);
}
