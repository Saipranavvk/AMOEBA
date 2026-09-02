#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#include <stdio.h>

/*-----------------------------------------------------------
 * FreeRTOS configuration for Wally/AMOEBA RISC-V.
 *
 * CVW's clint_apb increments MTIME once per PCLK, and PCLK == HCLK == the CPU
 * clock (the separate TIMECLK path is commented out upstream and TIMECLK is
 * tied low in both wrappers), so the mtime frequency equals the CPU clock and
 * configCPU_CLOCK_HZ must be the clock the core is actually running at.
 *
 * That is 100 MHz in simulation and FCLK_CLK0 on the FPGA -- 25 MHz by default,
 * see FCLK_MHZ in fpga/pynq/Makefile.  Getting it wrong is a rate error rather
 * than a correctness one: FreeRTOS still runs, but every tick interval is off
 * by the ratio, so tc_timer_preempt and anything with a wall-clock expectation
 * reads wrong, and hardware-vs-simulation timing comparisons become
 * meaningless.  Hence the override below rather than a hardcoded constant.
 *----------------------------------------------------------*/

/* ---- Scheduler behaviour ---- */
#define configUSE_PREEMPTION                    1
#define configUSE_TIME_SLICING                  1
#define configUSE_IDLE_HOOK                     0
#define configUSE_TICK_HOOK                     0
#define configUSE_DAEMON_TASK_STARTUP_HOOK      0

/* ---- Clock / tick ---- */
/* Overridable from the build: the FPGA target passes -DconfigCPU_CLOCK_HZ. */
#ifndef configCPU_CLOCK_HZ
#define configCPU_CLOCK_HZ                      ( ( uint32_t ) 100000000 )
#endif
/*
 * The RISC-V port derives its mtimecmp step from
 *   uxTimerIncrementsForOneTick = configCPU_CLOCK_HZ / configTICK_RATE_HZ
 * and mtime advances one count per CPU cycle here, so that quotient is
 * literally the number of simulated clock cycles per FreeRTOS tick.
 *
 * A realistic 100 Hz tick would be 1,000,000 cycles -- longer than the
 * testbench's default 10,000,000-cycle timeout allows for a vTaskDelay(10),
 * and hours of wall time under Verilator with FST tracing.  10 kHz gives a
 * 10,000-cycle tick, which keeps tick-driven tests to seconds of wall time.
 * Tick counts (not wall-clock milliseconds) are what the tc_*.c tests assert
 * on, so shortening the tick does not weaken them.
 */
#define configTICK_RATE_HZ                      ( ( TickType_t ) 10000 )

/* ---- Memory ---- */
#define configTOTAL_HEAP_SIZE                   ( ( size_t ) ( 64 * 1024 ) )
#define configMINIMAL_STACK_SIZE                ( ( uint32_t ) 256 )  /* in words */
#define configMAX_TASK_NAME_LEN                 16
#define configSTACK_DEPTH_TYPE                  uint32_t

/* ---- Task priorities ---- */
#define configMAX_PRIORITIES                    5
#define configIDLE_SHOULD_YIELD                 1

/* ---- Features ---- */
#define configUSE_MUTEXES                       1
#define configUSE_RECURSIVE_MUTEXES             1
#define configUSE_COUNTING_SEMAPHORES           1
#define configUSE_TASK_NOTIFICATIONS            1
#define configUSE_QUEUE_SETS                    0
#define configUSE_TIMERS                        1
#define configTIMER_TASK_PRIORITY               ( configMAX_PRIORITIES - 1 )
#define configTIMER_QUEUE_LENGTH                10
#define configTIMER_TASK_STACK_DEPTH            configMINIMAL_STACK_SIZE
#define configQUEUE_REGISTRY_SIZE               8
#define configUSE_TRACE_FACILITY                0
#define configUSE_STATS_FORMATTING_FUNCTIONS    0
#define configUSE_16_BIT_TICKS                  0
#define configUSE_APPLICATION_TASK_TAG          0
#define configUSE_MALLOC_FAILED_HOOK            1
#define configCHECK_FOR_STACK_OVERFLOW          2   /* paint stack and check */
#define configGENERATE_RUN_TIME_STATS           0

/* ---- Output: printf via syscalls_amoeba.c (NS16550 UART) ---- */
#define configPRINT_STRING( x )                 printf( x )

/* ---- RISC-V port: CLINT addresses ---- */
#define configMTIME_BASE_ADDRESS                ( 0x02000000UL + 0xBFF8UL )
#define configMTIMECMP_BASE_ADDRESS             ( 0x02000000UL + 0x4000UL )

/* ---- Include/exclude API functions ---- */
#define INCLUDE_vTaskPrioritySet                1
#define INCLUDE_uxTaskPriorityGet               1
#define INCLUDE_vTaskDelete                     1
#define INCLUDE_vTaskSuspend                    1
#define INCLUDE_vTaskDelayUntil                 1
#define INCLUDE_vTaskDelay                      1
#define INCLUDE_xTaskGetCurrentTaskHandle       1
#define INCLUDE_xTaskGetSchedulerState          1
#define INCLUDE_uxTaskGetStackHighWaterMark     1
#define INCLUDE_xTimerPendFunctionCall          1

/* ---- Assertion: print and spin so watchdog fires ---- */
#define configASSERT( x ) \
    if( ( x ) == 0 ) { \
        printf( "ASSERT FAILED: %s:%d\r\n", __FILE__, __LINE__ ); \
        for(;;); \
    }

#endif /* FREERTOS_CONFIG_H */
