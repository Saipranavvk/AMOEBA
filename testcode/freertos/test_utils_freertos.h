#ifndef TEST_UTILS_FREERTOS_H
#define TEST_UTILS_FREERTOS_H

#include <stdint.h>

/*
 * tohost_exit() is implemented in syscalls_amoeba.c.
 * It writes (code<<1)|1 to the HTif tohost address, then forces that line out
 * of CVW's write-back D-cache by conflict eviction so the write actually
 * reaches the bus -- see htif_writeback() there for why it is a sweep and not
 * a cbo.flush.  The testbench tohost monitor fires $finish (code==0) or
 * $fatal (code!=0).
 */
extern void __attribute__((noreturn)) tohost_exit(uintptr_t code);

/*
 * check(cond, code): assert a condition; exit with error code if false.
 * Subtasks that detect failure call this directly — no need to return
 * to the root task.
 */
#define check(cond, code) \
    do { if (!(cond)) tohost_exit((uintptr_t)(unsigned)(code)); } while (0)

#endif /* TEST_UTILS_FREERTOS_H */
