/*
 * freertos_main.c — FreeRTOS boot harness for AMOEBA simulation.
 *
 * Boots FreeRTOS, demonstrates preemptive scheduling and CLINT timer
 * interrupts, then runs the user-supplied workload (app_main).
 * When app_main() returns, exit(0) is called, which writes to the
 * HTif tohost location that the testbench monitors.
 *
 * Compile-time parameter:
 *   The file providing app_main() is passed as $(PROG) in the Makefile
 *   (default: sorting_algo_app.c).
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "FreeRTOS.h"
#include "task.h"
#include "timers.h"
#include "wally_clint.h"

/* Supplied by the PROG source file (default: sorting_algo_app.c) */
extern void app_main(void);

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

/* ---- Demo tasks (context-switch / timer demonstration) ---- */

static void vTask1(void *p)
{
    (void)p;
    uint32_t tick = 0;
    printf("Task1: started\r\n");
    for (;;) {
        printf("[Task1] tick %lu\r\n", (unsigned long)tick++);
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

static void vTask2(void *p)
{
    (void)p;
    uint32_t tick = 0;
    printf("Task2: started (higher priority, preempts Task1)\r\n");
    for (;;) {
        printf("[Task2] tick %lu\r\n", (unsigned long)tick++);
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

static void vTimerCallback(TimerHandle_t t)
{
    (void)t;
    static uint32_t fires = 0;
    printf("[Timer] fired %lu times  mtime=%llu\r\n",
           (unsigned long)++fires, (unsigned long long)clint_get_time());
}

/* ---- Userland task: runs app_main(), then terminates simulation ---- */

static void vUserTask(void *p)
{
    (void)p;
    printf("UserTask: calling app_main()\r\n");
    app_main();
    printf("UserTask: app_main() returned — simulation complete\r\n");
    exit(0); /* HTif tohost write; testbench detects and calls $finish */
}

/* ---- FreeRTOS application hooks ---- */

void vApplicationMallocFailedHook(void)
{
    printf("FATAL: FreeRTOS malloc failed\r\n");
    for (;;);
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    (void)xTask;
    printf("FATAL: stack overflow in task '%s'\r\n", pcTaskName);
    for (;;);
}

void vApplicationIdleHook(void) { /* nothing */ }

/* ---- main: initialise UART, create tasks, start scheduler ---- */

int main(void)
{
    /* uartInit is called by syscalls_amoeba.c's uartSend on first use;
       explicit init here ensures the line control register is set before
       any printf in early boot. */
    extern void uartInit(void);
    uartInit();

    printf("\r\n=== FreeRTOS on AMOEBA (wallypipelinedsoc) ===\r\n");
    printf("CLINT mtime at boot: %llu\r\n",
           (unsigned long long)clint_get_time());

    BaseType_t ret;

    /* Demo tasks at lower priority so they do not starve vUserTask */
    ret = xTaskCreate(vTask1, "Task1", configMINIMAL_STACK_SIZE,
                      NULL, tskIDLE_PRIORITY + 1, NULL);
    if (ret != pdPASS) { printf("FATAL: Task1 create failed\r\n"); for (;;); }

    ret = xTaskCreate(vTask2, "Task2", configMINIMAL_STACK_SIZE,
                      NULL, tskIDLE_PRIORITY + 2, NULL);
    if (ret != pdPASS) { printf("FATAL: Task2 create failed\r\n"); for (;;); }

    TimerHandle_t xTimer = xTimerCreate("SysTmr",
                                        pdMS_TO_TICKS(2000),
                                        pdTRUE, NULL, vTimerCallback);
    if (xTimer != NULL) xTimerStart(xTimer, 0);

    /* vUserTask at highest user priority so it runs first and to completion */
    ret = xTaskCreate(vUserTask, "User", configMINIMAL_STACK_SIZE * 4,
                      NULL, tskIDLE_PRIORITY + 3, NULL);
    if (ret != pdPASS) { printf("FATAL: UserTask create failed\r\n"); for (;;); }

    printf("Starting scheduler...\r\n");
    vTaskStartScheduler();

    /* Unreachable unless heap is exhausted */
    printf("FATAL: scheduler returned\r\n");
    for (;;);
    return 0;
}
