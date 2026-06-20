/* Quick‑sort without calling any library functions.
   Works on an array of integers stored in memory. */

   void swap(int *a, int *b) {
    int tmp = *a;
    *a = *b;
    *b = tmp;
}

/* Partition the sub‑array arr[low..high] around a pivot.
   The pivot chosen is the last element (arr[high]). */
int partition(int arr[], int low, int high) {
    int pivot = arr[high];
    int i = low - 1;          /* Index of the smaller element */

    int j;
    for (j = low; j < high; ++j) {
        if (arr[j] <= pivot) {
            ++i;
            swap(&arr[i], &arr[j]);
        }
    }
    swap(&arr[i + 1], &arr[high]);   /* Place pivot in correct spot */
    return i + 1;                    /* Return pivot index */
}

/* Recursive quick‑sort */
void quickSort(int arr[], int low, int high) {
    if (low < high) {
        int pi = partition(arr, low, high);
        quickSort(arr, low, pi - 1);
        quickSort(arr, pi + 1, high);
    }
}

/* Example driver – you can replace the array contents
   and size with whatever you need. No I/O is performed. */
int main(void) {
    /* Sample data */
    int data[] = {34, 7, 23, 32, 5, 62};
    int n = sizeof(data) / sizeof(data[0]);

    /* Sort the array in place */
    quickSort(data, 0, n - 1);

    /* At this point `data` holds the sorted values:
       {5, 7, 23, 32, 34, 62}
       You can inspect it with a debugger or add your own
       platform‑specific output if needed. */
    return 0;
}
