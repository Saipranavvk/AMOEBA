/*
 * sorting_algo_app.c — default FreeRTOS userland workload.
 *
 * Provides void app_main(void), called by the FreeRTOS harness in
 * freertos_main.c.  When app_main returns the harness calls exit(0).
 *
 * Algorithm: iterative quicksort of 1000 pseudo-random 32-bit integers.
 * No halt instruction — termination is the harness's responsibility.
 */

typedef struct { int lo; int hi; } Range;

static void swap(int *a, int *b)
{
    int t = *a; *a = *b; *b = t;
}

static int partition(int a[], int lo, int hi)
{
    int pivot = a[hi];
    int i = lo - 1, j;
    for (j = lo; j < hi; ++j)
        if (a[j] <= pivot) { ++i; swap(&a[i], &a[j]); }
    swap(&a[i + 1], &a[hi]);
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

void app_main(void)
{
    const int N = 1000;
    int data[N];
    int i;
    unsigned int seed = 123456789u;

    for (i = 0; i < N; ++i) {
        seed = seed * 1103515245u + 12345u;
        data[i] = (int)(seed & 0x7fffffff);
    }

    quicksort_iterative(data, N);
    /* Return normally; freertos_main.c calls exit(0) after this returns. */
}
