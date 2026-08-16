/*
 * freertos_main.c — FreeRTOS boot harness for AMOEBA simulation.
 *
 * Boots FreeRTOS, creates the root task that calls the user-supplied
 * app_main(), and passes the return value to exit().  Test programs
 * return 0 on pass, a non-zero error code on failure.  FreeRTOS tasks
 * that detect failure can also call tohost_exit() directly.
 *
 * Compile-time parameter:
 *   The file providing app_main() is passed as $(PROG) in the Makefile
 *   (default: sorting_algo_app.c).
 */

#include <stdint.h>
#include <stdlib.h>
#include "FreeRTOS.h"
#include "task.h"

/* Supplied by the PROG source file */
extern int app_main(void);

/* Soft CLZ helpers required by some GCC toolchain versions */
int __clzdi2(uint64_t x)
{
    if (x == 0) return 64;
    int n = 0;
    if ((x & 0xFFFFFFFF00000000ULL) == 0) { n += 32; x <<= 32; }
    if ((x & 0xFFFF000000000000ULL) == 0) { n += 16; x <<= 16; }
    if ((x & 0xFF00000000000000ULL) == 0) { n +=  8; x <<=  8; }
    if ((x & 0xF000000000000000ULL) == 0) { n +=  4; x <<=  4; }
    if ((x & 0xC000000000000000ULL) == 0) { n +=  2; x <<=  2; }
    if ((x & 0x8000000000000000ULL) == 0) { n +=  1; }
    return n;
}

int __clzsi2(uint32_t x)
{
    if (x == 0) return 32;
    int n = 0;
    if ((x & 0xFFFF0000U) == 0) { n += 16; x <<= 16; }
    if ((x & 0xFF000000U) == 0) { n +=  8; x <<=  8; }
    if ((x & 0xF0000000U) == 0) { n +=  4; x <<=  4; }
    if ((x & 0xC0000000U) == 0) { n +=  2; x <<=  2; }
    if ((x & 0x80000000U) == 0) { n +=  1; }
    return n;
}

/* Root task: runs app_main() and exits with its return code */
static void vRootTask(void *p)
{
    (void)p;
    exit(app_main());
}

/* ---- FreeRTOS application hooks ---- */

void vApplicationMallocFailedHook(void)
{
    exit(2); /* exit code 2: heap exhausted */
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    (void)xTask; (void)pcTaskName;
    exit(3); /* exit code 3: stack overflow */
}

void vApplicationIdleHook(void) { /* nothing */ }

/* ---- main: create root task, start scheduler ---- */

int main(void)
{
    BaseType_t ret = xTaskCreate(vRootTask, "Root", configMINIMAL_STACK_SIZE * 4,
                                 NULL, tskIDLE_PRIORITY + 1, NULL);
    if (ret != pdPASS)
        exit(4); /* exit code 4: root task creation failed */

    vTaskStartScheduler();

    /* Unreachable unless heap is exhausted */
    exit(5);
    return 0;
}
