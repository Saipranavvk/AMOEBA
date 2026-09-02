/*
 * heartbeat_app.c -- liveness and clock-calibration workload for the FPGA.
 *
 * Prints one line every HB_PERIOD_MS of FreeRTOS time, forever (or for
 * HB_COUNT beats, if that is set non-zero).  It is deliberately the dullest
 * program in the tree, because what it proves is not about the program:
 *
 *   1. LIVENESS.  A terminating test tells you it passed or it did not.  This
 *      tells you the core is still running, continuously, which is what you
 *      actually want to know while probing a board for the first time.
 *
 *   2. THE CLOCK IS WHAT WE THINK IT IS.  This is the real reason it exists.
 *      configCPU_CLOCK_HZ has to match the clock the core is running at,
 *      because CVW's clint_apb increments MTIME once per PCLK and the RISC-V
 *      port derives its mtimecmp step from that constant.  Get it wrong and
 *      every terminating test STILL PASSES -- they check ordering and results,
 *      not rates -- while every interval in the system is off by the ratio.
 *      Here the error is the observable: beats arrive at
 *      HB_PERIOD_MS * (configCPU_CLOCK_HZ / actual_clock_hz) milliseconds of
 *      wall time, so the PS can measure the ratio and report the true clock.
 *
 *   3. THE WHOLE CONSOLE PATH.  Each beat is a store to the 16550's transmit
 *      register, which the PL's amoeba_bus_mon snoops off the AHB into a FIFO
 *      the PS drains.  A beat arriving intact exercises all of it.
 *
 * Each line carries the tick count as well as a sequence number so the PS has
 * three independent clocks to cross-check: its own wall time, the guest's
 * FreeRTOS ticks, and the PL's free-running cycle counter.  Disagreement
 * between any two localises the problem immediately -- see fpga/pynq/BRINGUP.md.
 *
 * Note this does NOT print mcycle: ZICNTR_SUPPORTED is 0 in
 * config_baremetal_linux, so the guest cannot read a cycle counter at all.
 * That is what the PL's CYCLES register is for.
 */

#include "FreeRTOS.h"
#include "task.h"
#include "test_utils_freertos.h"
#include "wally_uart.h"

/* Wall-clock period of one beat.  100 ms is slow enough to watch by eye and
 * fast enough that a wrong clock is obvious within a couple of seconds. */
#ifndef HB_PERIOD_MS
#define HB_PERIOD_MS 100
#endif

/* 0 = run forever (soak).  Non-zero = exit(0) after that many beats, which
 * makes this usable as a terminating regression test too. */
#ifndef HB_COUNT
#define HB_COUNT 0
#endif

static void put_u64(unsigned long long v)
{
    char buf[21];
    int  i = 0;

    if (v == 0ULL) { uart_putc('0'); return; }
    while (v > 0ULL) { buf[i++] = (char)('0' + (v % 10ULL)); v /= 10ULL; }
    while (i > 0) uart_putc(buf[--i]);
}

static void heartbeat_task(void *pv)
{
    TickType_t       wake   = xTaskGetTickCount();
    const TickType_t period = pdMS_TO_TICKS(HB_PERIOD_MS);
    unsigned long long seq  = 0ULL;

    /* Announce the parameters before the first beat so the PS can check its
     * expectations against the build rather than against a hardcoded guess. */
    uart_puts("HB start period_ms=");
    put_u64((unsigned long long)HB_PERIOD_MS);
    uart_puts(" tick_hz=");
    put_u64((unsigned long long)configTICK_RATE_HZ);
    uart_puts(" cpu_hz=");
    put_u64((unsigned long long)configCPU_CLOCK_HZ);
    uart_puts("\n");

    for (;;) {
        /* vTaskDelayUntil, not vTaskDelay: the period must not drift with the
         * time spent printing, or the PS's measured clock ratio absorbs the
         * printing cost and reports a clock that is slightly too slow. */
        vTaskDelayUntil(&wake, period);

        seq++;
        uart_puts("HB seq=");
        put_u64(seq);
        uart_puts(" tick=");
        put_u64((unsigned long long)xTaskGetTickCount());
        uart_puts("\n");

        if (HB_COUNT != 0 && seq >= (unsigned long long)HB_COUNT)
            tohost_exit(0);
    }
}

int app_main(void)
{
    if (xTaskCreate(heartbeat_task, "hb", configMINIMAL_STACK_SIZE * 2,
                    NULL, tskIDLE_PRIORITY + 1, NULL) != pdPASS)
        return 1;

    /* app_main runs inside a task already; the scheduler is up.  Block here so
     * the root task never returns and calls exit(). */
    for (;;)
        vTaskDelay(pdMS_TO_TICKS(1000));

    return 0;
}
