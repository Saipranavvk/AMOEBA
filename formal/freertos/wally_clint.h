#ifndef WALLY_CLINT_H
#define WALLY_CLINT_H

#include <stdint.h>

/* CLINT at CLINT_BASE = 0x02000000 (wallypipelinedsoc / SiFive standard) */
#define CLINT_BASE      0x02000000UL

#define CLINT_MSIP      (*(volatile uint32_t *)(CLINT_BASE + 0x0000))   /* M-mode software interrupt */
#define CLINT_MTIMECMP  (*(volatile uint64_t *)(CLINT_BASE + 0x4000))   /* M-mode timer compare */
#define CLINT_MTIME     (*(volatile uint64_t *)(CLINT_BASE + 0xBFF8))   /* M-mode timer counter */

static inline uint64_t clint_get_time(void) {
    return CLINT_MTIME;
}

static inline void clint_set_timer_interval(uint64_t interval) {
    CLINT_MTIMECMP = CLINT_MTIME + interval;
}

static inline void clint_advance_timer(uint64_t interval) {
    CLINT_MTIMECMP += interval;
}

#endif /* WALLY_CLINT_H */
