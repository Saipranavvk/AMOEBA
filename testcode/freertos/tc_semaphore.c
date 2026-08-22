/*
 * tc_semaphore.c — FreeRTOS binary semaphore sequencing test.
 *
 * Task A gives a binary semaphore 5 times.
 * Task B takes the semaphore 5 times, incrementing a counter each time.
 * Verifies the counter reaches 5, confirming semaphore synchronisation works.
 *
 * Exit codes:
 *   0 = PASS
 *   1 = count wrong
 *   2 = semaphore create failed
 */

#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "test_utils_freertos.h"

static SemaphoreHandle_t s_sem;

static void giver(void *pv)
{
    (void)pv;
    for (int i = 0; i < 5; i++) {
        xSemaphoreGive(s_sem);
        vTaskDelay(1); /* yield to allow taker to run */
    }
    vTaskDelete(NULL);
}

static void taker(void *pv)
{
    (void)pv;
    int count = 0;
    for (int i = 0; i < 5; i++) {
        if (xSemaphoreTake(s_sem, portMAX_DELAY) == pdTRUE)
            count++;
    }
    check(count == 5, 1);
    tohost_exit(0);
}

int app_main(void)
{
    s_sem = xSemaphoreCreateBinary();
    if (!s_sem)
        return 2;
    /*
     * The taker must outrank the giver.  A binary semaphore saturates at one
     * token, so a give issued while a token is still pending is silently
     * dropped and the taker can never reach 5.  Running the taker at the
     * higher priority guarantees it preempts the giver and drains the token
     * before the giver can run again, which makes the handshake independent
     * of configTICK_RATE_HZ and of how long task creation takes.
     *
     * Creating the taker first also means it is already blocked on the
     * semaphore before the first give, rather than being created in a window
     * where a tick can let the giver run a second time.
     */
    xTaskCreate(taker, "taker", configMINIMAL_STACK_SIZE, NULL, tskIDLE_PRIORITY + 2, NULL);
    xTaskCreate(giver, "giver", configMINIMAL_STACK_SIZE, NULL, tskIDLE_PRIORITY + 1, NULL);
    /* Taker calls tohost_exit(); app_main never returns */
    vTaskSuspend(NULL);
    return 0; /* unreachable */
}
