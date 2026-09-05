/* tc_ecc_all_patterns.c
 *
 * Corner-case data patterns through all 32 registers.
 * Tests all-zeros, all-ones, alternating-bit patterns, and a set of
 * representative 64-bit constants.  Each pattern is stored into a
 * volatile array (forcing register-file writes) then read back.
 */

#include <stdint.h>

volatile uint64_t sink;

static const uint64_t patterns[] = {
    0x0000000000000000ULL,
    0xFFFFFFFFFFFFFFFFULL,
    0xAAAAAAAAAAAAAAAAULL,
    0x5555555555555555ULL,
    0xDEADBEEFCAFEBABEULL,
    0x0123456789ABCDEFULL,
    0xFEDCBA9876543210ULL,
    0x0F0F0F0F0F0F0F0FULL,
    0xF0F0F0F0F0F0F0F0ULL,
    0x00000000FFFFFFFFULL,
    0xFFFFFFFF00000000ULL,
    0x0000FFFF0000FFFFULL,
    0xFFFF0000FFFF0000ULL,
    0x00FF00FF00FF00FFULL,
    0xFF00FF00FF00FF00ULL,
    0x7FFFFFFFFFFFFFFFULL,
    0x8000000000000000ULL,
    0x3FFFFFFFFFFFFFFFULL,
    0xC000000000000000ULL,
    0x0101010101010101ULL,
    0x8080808080808080ULL,
    0x4040404040404040ULL,
    0x2020202020202020ULL,
    0x1010101010101010ULL,
    0x0807060504030201ULL,
    0xF8F7F6F5F4F3F2F1ULL,
    0xA5A5A5A5A5A5A5A5ULL,
    0x5A5A5A5A5A5A5A5AULL,
    0x96969696969696ACULL,
    0x0000000000000001ULL,
    0x8000000000000001ULL,
    0xFFFFFFFFFFFFFF00ULL,
};

#define NPATTERNS (sizeof(patterns) / sizeof(patterns[0]))

int main(void) {
    volatile uint64_t store[NPATTERNS];
    unsigned i;

    for (i = 0; i < NPATTERNS; i++)
        store[i] = patterns[i];

    for (i = 0; i < NPATTERNS; i++) {
        if (store[i] != patterns[i])
            return 1;
        sink = store[i];
    }

    /* Simple arithmetic sanity with corner values */
    volatile uint64_t z  = 0ULL;
    volatile uint64_t ff = 0xFFFFFFFFFFFFFFFFULL;
    if ((z + 1ULL) != 1ULL)       return 1;
    if ((ff + 1ULL) != 0ULL)      return 1;  /* wraps */
    if ((z - 1ULL) != ff)         return 1;

    sink = ff ^ z;
    return 0;
}
