#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#include <stdio.h>

/*-----------------------------------------------------------
 * FreeRTOS configuration for Wally/AMOEBA RISC-V bare metal simulation.
 *
 * Clock and timer values assume wallypipelinedsoc defaults:
 *   CPU: 100 MHz,  CLINT TIMECLK: 10 MHz
 *----------------------------------------------------------*/

/* ---- Scheduler behaviour ---- */
#define configUSE_PREEMPTION                    1
#define configUSE_TIME_SLICING                  1
#define configUSE_IDLE_HOOK                     0
#define configUSE_TICK_HOOK                     0
#define configUSE_DAEMON_TASK_STARTUP_HOOK      0

/* ---- Clock / tick ---- */
#define configCPU_CLOCK_HZ                      ( ( uint32_t ) 100000000 )
#define configTICK_RATE_HZ                      ( ( TickType_t ) 100 )
/* mtime frequency (TIMECLK) drives clint_set_timer_interval() */
#define configMTIME_HZ                          ( ( uint64_t ) 10000000 )
/* Interval in mtime counts between FreeRTOS ticks */
#define configTICK_CLOCK_HZ                     ( configMTIME_HZ / configTICK_RATE_HZ )

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
