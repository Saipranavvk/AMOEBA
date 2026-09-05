/* tc_ecc_branch.c
 *
 * Branch-heavy test.
 * Data-dependent branches force the processor to forward values through
 * the pipeline while the branch predictor resolves direction.  ECC
 * injection during forwarding and the D→E register reads must be
 * corrected or the branch will misdirect and produce wrong results.
 */

#include <stdint.h>

volatile uint64_t sink;

/* Recursive-ish computation via many data-dependent branches */
static uint64_t classify(uint64_t v) {
    if (v == 0)                    return 0x0000000000000000ULL;
    if ((v & 1) == 0)              return v >> 1;          /* even */
    if ((v & 3) == 3)              return v ^ 0x5555555555555555ULL;
    if ((v >> 63) & 1)             return ~v;              /* negative */
    return v + 1;
}

static int branch_tree(uint64_t x, uint64_t expected) {
    uint64_t result = 0;
    /* 16 branches interleaved; each depends on x */
    if (x > 0x8000000000000000ULL) result |= (1ULL << 0);
    if (x > 0x4000000000000000ULL) result |= (1ULL << 1);
    if (x > 0x2000000000000000ULL) result |= (1ULL << 2);
    if (x > 0x1000000000000000ULL) result |= (1ULL << 3);
    if (x > 0x0800000000000000ULL) result |= (1ULL << 4);
    if (x > 0x0400000000000000ULL) result |= (1ULL << 5);
    if (x > 0x0200000000000000ULL) result |= (1ULL << 6);
    if (x > 0x0100000000000000ULL) result |= (1ULL << 7);
    if ((x & 0xFF00FF00FF00FF00ULL) != 0) result |= (1ULL << 8);
    if ((x & 0x00FF00FF00FF00FFULL) != 0) result |= (1ULL << 9);
    if ((x & 0xF0F0F0F0F0F0F0F0ULL) != 0) result |= (1ULL << 10);
    if ((x & 0x0F0F0F0F0F0F0F0FULL) != 0) result |= (1ULL << 11);
    if ((x & 0xAAAAAAAAAAAAAAAAULL) != 0) result |= (1ULL << 12);
    if ((x & 0x5555555555555555ULL) != 0) result |= (1ULL << 13);
    if (x != 0)                    result |= (1ULL << 14);
    if (x != 0xFFFFFFFFFFFFFFFFULL) result |= (1ULL << 15);
    return (result == expected) ? 0 : 1;
}

int main(void) {
    /* Each call is done twice; mismatches indicate forwarding ECC failure */
    uint64_t vals[]     = {0xCAFEBABEDEADBEEFULL, 0x0123456789ABCDEFULL,
                            0x0ULL, 0xFFFFFFFFFFFFFFFFULL, 0x1ULL};
    uint64_t expected[] = {0xFFFFULL, 0xFFFFULL, 0x0ULL, 0x7FFFULL, 0x7FFFULL};
    int i;
    for (i = 0; i < 5; i++) {
        if (branch_tree(vals[i], expected[i]))
            return 1;
        if (branch_tree(vals[i], expected[i]))
            return 1;
    }

    /* Verify classify is deterministic under injection */
    uint64_t test_vals[] = {0ULL, 2ULL, 3ULL, 0x8000000000000000ULL, 5ULL};
    for (i = 0; i < 5; i++) {
        if (classify(test_vals[i]) != classify(test_vals[i]))
            return 1;
    }

    /* Loop with data-dependent exit to exercise back-edge branches */
    volatile uint64_t c = 256;
    uint64_t acc = 0;
    while (c > 0) {
        acc += c;
        c--;
    }
    if (acc != (256ULL * 257ULL / 2ULL))
        return 1;

    sink = acc;
    return 0;
}
