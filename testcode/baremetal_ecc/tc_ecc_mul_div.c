/* tc_ecc_mul_div.c
 *
 * Multiply/divide heavy test.
 * Mul and div instructions stall the pipeline for several cycles while the
 * MDU computes.  During stalls the SrcAM and WriteDataM pipeline registers
 * hold live values that can receive injected errors; SECDED must correct them
 * before the result is written back.
 */

#include <stdint.h>

volatile uint64_t sink;

int main(void) {
    /* Basic mul/div sanity */
    volatile uint64_t a = 123456789ULL;
    volatile uint64_t b = 987654321ULL;
    volatile uint64_t p = a * b;
    if (p != 121932631112635269ULL)
        return 1;

    volatile uint64_t q = p / a;
    if (q != b)
        return 1;

    volatile uint64_t r = p % a;
    if (r != 0ULL)
        return 1;

    /* 32-bit signed multiply (maps to mulw on RV64) */
    volatile int32_t x = -1000;
    volatile int32_t y =  1000;
    volatile int64_t  z = (int64_t)x * y;
    if (z != -1000000LL)
        return 1;

    /* Long chain of multiplications — high cumulative injection exposure */
    volatile uint64_t acc = 1ULL;
    int i;
    for (i = 1; i <= 20; i++) {
        acc = (acc * (uint64_t)i) % 1000000007ULL;
    }
    /* 20! mod 1000000007 = 146326063 */
    if (acc != 146326063ULL)
        return 1;

    /* Division chain */
    volatile uint64_t d = 1000000000000000000ULL;
    for (i = 1; i <= 10; i++) {
        d /= (uint64_t)i;
    }
    if (d != 1000000000000000000ULL / (10ULL * 9ULL * 8ULL * 7ULL * 6ULL *
                                        5ULL * 4ULL * 3ULL * 2ULL * 1ULL))
        return 1;

    /* Unsigned multiply then verify with division */
    volatile uint64_t u  = 0xDEADBEEFULL;
    volatile uint64_t v  = 0xCAFEBABEULL;
    volatile uint64_t uv = u * v;
    if (uv / u != v)
        return 1;
    if (uv % u != 0ULL)
        return 1;

    sink = uv ^ acc;
    return 0;
}
