/*
 * tc_timer_preempt.c — FreeRTOS tick / CLINT timer integration test.
 *
 * Verifies that the FreeRTOS tick timer (driven by CLINT mtime interrupt)
 * is functional by measuring that vTaskDelay() suspends a task for at
 * least the requested number of ticks.
 *
 * A second lower-priority task busy-loops incrementing a counter while the
 * high-priority task sleeps.  After the delay, the high-priority task checks:
 *   1. At least DELAY_TICKS ticks elapsed (timer actually fired).
 *   2. The busy-loop counter advanced (lower-priority task ran during sleep,
 *      confirming the scheduler preempted as expected).
 *
 * Exit codes:
 *   0 = PASS
 *   1 = fewer ticks elapsed than requested (CLINT timer not working)
 *   2 = busy-loop task never ran (scheduler not preempting)
 */

#include "FreeRTOS.h"
#include "task.h"
#include "test_utils_freertos.h"

#define DELAY_TICKS  10

static volatile unsigned long s_busy_count;

static void busy_task(void *pv)
{
    (void)pv;
    for (;;)
        s_busy_count++;
}

static void checker_task(void *pv)
{
    (void)pv;
    TickType_t start = xTaskGetTickCount();
    vTaskDelay(DELAY_TICKS);
    TickType_t elapsed = xTaskGetTickCount() - start;

    check(elapsed >= (TickType_t)DELAY_TICKS, 1);
    check(s_busy_count > 0UL, 2);
    tohost_exit(0);
}

int app_main(void)
{
    s_busy_count = 0UL;
    /* busy_task at lower priority so checker_task can preempt it after delay */
    xTaskCreate(busy_task,    "busy",    configMINIMAL_STACK_SIZE, NULL, tskIDLE_PRIORITY + 1, NULL);
    xTaskCreate(checker_task, "checker", configMINIMAL_STACK_SIZE, NULL, tskIDLE_PRIORITY + 2, NULL);
    vTaskSuspend(NULL);
    return 0; /* unreachable */
}
