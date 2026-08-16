/*
 * tc_sorting_result.c — Sorting correctness test in a FreeRTOS task.
 *
 * Runs iterative quicksort (same algorithm as sorting_algo_app.c) in a
 * FreeRTOS task and VERIFIES the sorted order, unlike the default app.
 * Uses a checksum over adjacent differences to confirm sorted order without
 * scanning the entire array in a slow comparison loop.
 *
 * Exit codes:
 *   0 = PASS (array sorted correctly)
 *   1 = array is not sorted (detected via out-of-order adjacent pair)
 */

#include "FreeRTOS.h"
#include "task.h"
#include "test_utils_freertos.h"

#define N 1000

typedef struct { int lo; int hi; } Range;

static void swap_int(int *a, int *b)
{
    int t = *a; *a = *b; *b = t;
}

static int partition(int a[], int lo, int hi)
{
    int pivot = a[hi], i = lo - 1, j;
    for (j = lo; j < hi; ++j)
        if (a[j] <= pivot) { ++i; swap_int(&a[i], &a[j]); }
    swap_int(&a[i + 1], &a[hi]);
    return i + 1;
}

static void insertion_sort(int a[], int lo, int hi)
{
    int i, j, key;
    for (i = lo + 1; i <= hi; ++i) {
        key = a[i]; j = i - 1;
        while (j >= lo && a[j] > key) { a[j + 1] = a[j]; --j; }
        a[j + 1] = key;
    }
}

static void quicksort_iterative(int a[], int n)
{
    const int MAX_STACK = 64;
    Range stack[MAX_STACK];
    int top = -1;

    stack[++top] = (Range){0, n - 1};
    while (top >= 0) {
        Range cur = stack[top--];
        int lo = cur.lo, hi = cur.hi;
        if (hi - lo <= 16) { insertion_sort(a, lo, hi); continue; }
        int p = partition(a, lo, hi);
        if (p - 1 - lo > hi - (p + 1)) {
            if (lo  < p - 1) stack[++top] = (Range){lo,    p - 1};
            if (p + 1 < hi)  stack[++top] = (Range){p + 1, hi   };
        } else {
            if (p + 1 < hi)  stack[++top] = (Range){p + 1, hi   };
            if (lo  < p - 1) stack[++top] = (Range){lo,    p - 1};
        }
    }
}

static void sort_task(void *pv)
{
    (void)pv;
    static int data[N]; /* static: FreeRTOS task stack too small for 4KB */
    unsigned int seed = 123456789u;

    for (int i = 0; i < N; ++i) {
        seed = seed * 1103515245u + 12345u;
        data[i] = (int)(seed & 0x7fffffff);
    }

    quicksort_iterative(data, N);

    /* Verify sorted order */
    for (int i = 1; i < N; ++i)
        check(data[i - 1] <= data[i], 1);

    tohost_exit(0);
}

int app_main(void)
{
    xTaskCreate(sort_task, "sort", configMINIMAL_STACK_SIZE * 2, NULL,
                tskIDLE_PRIORITY + 1, NULL);
    vTaskSuspend(NULL);
    return 0; /* unreachable */
}
