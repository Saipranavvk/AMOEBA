

#ifndef TEST_UTILS_H
#define TEST_UTILS_H

#include <stdint.h>
#include <stddef.h>

// -------------------------------------------------------------------------
// tohost / fromhost mechanism
// The Wally testbench watches for a store to the symbol "tohost".
// Writing 1 signals success, writing non-zero signals failure code.
// -------------------------------------------------------------------------
extern volatile uint64_t tohost;
extern volatile uint64_t fromhost;

static inline void __attribute__((noreturn)) sim_exit(uint64_t code) {
    // Per RISC-V test convention: write (code << 1) | 1 to tohost.
    // Code 0 = success, nonzero = failure.
    tohost = (code << 1) | 1;
    // Spin in case the testbench doesn't halt us immediately
    while (1) { __asm__ volatile ("wfi"); }
}

// -------------------------------------------------------------------------
// Simple UART putchar
// Wally UART base address (default Wally memory map)
// -------------------------------------------------------------------------
#define UART_BASE       0x10000000UL
#define UART_THR        (*(volatile uint8_t *)(UART_BASE + 0x00))
#define UART_LSR        (*(volatile uint8_t *)(UART_BASE + 0x05))
#define UART_LSR_THRE   (1 << 5)   // Transmit Holding Register Empty

static inline void uart_putchar(char c) {
    while (!(UART_LSR & UART_LSR_THRE));
    UART_THR = (uint8_t)c;
}

static inline void uart_puts(const char *s) {
    while (*s) uart_putchar(*s++);
}

// Minimal integer-to-decimal string (unsigned)
static inline void uart_putu64(uint64_t v) {
    char buf[21];
    int i = 20;
    buf[i] = '\0';
    if (v == 0) { uart_putchar('0'); return; }
    while (v && i > 0) {
        buf[--i] = '0' + (v % 10);
        v /= 10;
    }
    uart_puts(&buf[i]);
}

// Minimal integer-to-hex string
static inline void uart_puthex64(uint64_t v) {
    const char *hex = "0123456789abcdef";
    uart_puts("0x");
    for (int i = 60; i >= 0; i -= 4)
        uart_putchar(hex[(v >> i) & 0xF]);
}

// -------------------------------------------------------------------------
// Test result tracking
// -------------------------------------------------------------------------
static int _pass_count = 0;
static int _fail_count = 0;
static const char *_current_test = "";

static inline void test_begin(const char *name) {
    _current_test = name;
    uart_puts("\n[TEST] ");
    uart_puts(name);
    uart_puts("\n");
}

static inline void check(const char *label,
                         uint64_t actual,
                         uint64_t expected) {
    if (actual == expected) {
        uart_puts("  PASS  ");
        uart_puts(label);
        uart_puts("\n");
        _pass_count++;
    } else {
        uart_puts("  FAIL  ");
        uart_puts(label);
        uart_puts("\n    got      ");
        uart_puthex64(actual);
        uart_puts("\n    expected ");
        uart_puthex64(expected);
        uart_puts("\n");
        _fail_count++;
    }
}

// Signed variant (cast both sides to int64_t before comparing)
static inline void check_s(const char *label,
                            int64_t actual,
                            int64_t expected) {
    check(label, (uint64_t)actual, (uint64_t)expected);
}

// Boolean variant
static inline void check_bool(const char *label, int condition) {
    check(label, (uint64_t)(condition != 0), 1ULL);
}

static inline void print_summary(void) {
    uart_puts("\n--- Summary ---\n");
    uart_puts("PASS: "); uart_putu64(_pass_count); uart_puts("\n");
    uart_puts("FAIL: "); uart_putu64(_fail_count); uart_puts("\n");
}

static inline int total_failures(void) { return _fail_count; }

static inline void __attribute__((noreturn)) test_finish(void) {
    sim_exit(total_failures() != 0 ? 1 : 0);
}

// -------------------------------------------------------------------------
// Fence.I helper (for self-modifying code test)
// -------------------------------------------------------------------------
static inline void fence_i(void) {
    __asm__ volatile ("fence.i" ::: "memory");
}

// -------------------------------------------------------------------------
// Cycle counter (rdcycle CSR)
// -------------------------------------------------------------------------
static inline uint64_t read_cycle(void) {
    uint64_t c;
    __asm__ volatile ("rdcycle %0" : "=r"(c));
    return c;
}

#endif // TEST_UTILS_H