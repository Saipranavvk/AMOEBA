/* --------------------------------------------------------------
   ITERATIVE QUICK‑SORT  (no library calls, works for very large data)
   -------------------------------------------------------------- */

typedef struct {
    int lo;
    int hi;
} Range;

/* Simple swap */
static void swap(int *a, int *b)
{
    int t = *a;
    *a = *b;
    *b = t;
}

/* Partition – last element is the pivot */
static int partition(int a[], int lo, int hi)
{
    int pivot = a[hi];
    int i = lo - 1;
    int j;
    for (j = lo; j < hi; ++j) {
        if (a[j] <= pivot) {
            ++i;
            swap(&a[i], &a[j]);
        }
    }
    swap(&a[i + 1], &a[hi]);
    return i + 1;
}

/* Insertion sort for very small ranges (helps overall speed) */
static void insertion_sort(int a[], int lo, int hi)
{
    int i, j, key;
    for (i = lo + 1; i <= hi; ++i) {
        key = a[i];
        j = i - 1;
        while (j >= lo && a[j] > key) {
            a[j + 1] = a[j];
            --j;
        }
        a[j + 1] = key;
    }
}

/* --------------------------------------------------------------
   quickSortIterative
   -------------------------------------------------------------- */
void quickSortIterative(int a[], int n)
{
    const int MAX_STACK = 64;                 /* enough for >2^64 elements */
    Range stack[MAX_STACK];
    int top = -1;

    stack[++top] = (Range){0, n - 1};

    while (top >= 0) {
        Range cur = stack[top--];
        int lo = cur.lo;
        int hi = cur.hi;

        if (hi - lo <= 16) {          /* tiny partition → insertion sort */
            insertion_sort(a, lo, hi);
            continue;
        }

        int p = partition(a, lo, hi);

        /* Push larger sub‑range first → keep stack depth O(log n) */
        if (p - 1 - lo > hi - (p + 1)) {
            if (lo < p - 1) stack[++top] = (Range){lo, p - 1};
            if (p + 1 < hi) stack[++top] = (Range){p + 1, hi};
        } else {
            if (p + 1 < hi) stack[++top] = (Range){p + 1, hi};
            if (lo < p - 1) stack[++top] = (Range){lo, p - 1};
        }
    }
}

/* --------------------------------------------------------------
   Example driver – large data set (1 M elements)
   -------------------------------------------------------------- */
int main(void)
{
    const int N = 1000;
    int data[N];
    int i;
    unsigned int seed = 123456789u;

    /* Simple LCG – no library calls */
    for (i = 0; i < N; ++i) {
        seed = seed * 1103515245u + 12345u;
        data[i] = (int)(seed & 0x7fffffff);
    }

    quickSortIterative(data, N);

    return 0;
}
