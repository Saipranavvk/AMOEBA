/*
 * tc_task_queue.c — FreeRTOS queue test.
 *
 * Producer sends integers 0-9 through a FreeRTOS queue.
 * Consumer receives all 10 values and verifies their sum equals 45.
 *
 * Exit codes:
 *   0 = PASS
 *   1 = wrong sum
 *   2 = queue create failed
 */

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "test_utils_freertos.h"

static QueueHandle_t s_queue;

static void producer(void *pv)
{
    (void)pv;
    for (int i = 0; i <= 9; i++)
        xQueueSend(s_queue, &i, portMAX_DELAY);
    vTaskDelete(NULL);
}

static void consumer(void *pv)
{
    (void)pv;
    int sum = 0;
    for (int i = 0; i <= 9; i++) {
        int val;
        xQueueReceive(s_queue, &val, portMAX_DELAY);
        sum += val;
    }
    /* 0+1+...+9 = 45 */
    check(sum == 45, 1);
    tohost_exit(0);
}

int app_main(void)
{
    s_queue = xQueueCreate(5, sizeof(int));
    if (!s_queue)
        return 2;
    xTaskCreate(producer, "prod", configMINIMAL_STACK_SIZE, NULL, tskIDLE_PRIORITY + 2, NULL);
    xTaskCreate(consumer, "cons", configMINIMAL_STACK_SIZE, NULL, tskIDLE_PRIORITY + 1, NULL);
    /* Consumer calls tohost_exit(); app_main never returns */
    vTaskSuspend(NULL);
    return 0; /* unreachable */
}
