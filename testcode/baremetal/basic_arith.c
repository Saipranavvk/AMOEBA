/* Basic arithmetic, branches, and memory access */
int main(void) {
    volatile int a = 42, b = 7;
    volatile int c = a + b;     /* 49 */
    volatile int d = a * b;     /* 294 */
    volatile int e = a / b;     /* 6 */
    volatile int f = a % b;     /* 0 */
    volatile long long g = (long long)a * b * 1000; /* 294000 */
    int arr[16];
    int i;
    for (i = 0; i < 16; i++) arr[i] = i * i;
    int sum = 0;
    for (i = 0; i < 16; i++) sum += arr[i];
    return sum;
}
