/* tc_ecc_stress.c
 *
 * ECC stress test — highest cumulative injection count.
 * Runs 2000 iterations of a mixed workload: ALU ops, loads/stores, branches,
 * and mul/div.  Each iteration writes and reads back multiple registers so
 * that many injection events occur across the full test, all silently
 * corrected by SECDED.  A mismatch on any iteration returns a non-zero
 * error code (mapped to fail by the testbench).
 */

#include <stdint.h>

volatile uint64_t sink;

static uint64_t hash(uint64_t v, uint64_t key) {
    v ^= key;
    v = (v ^ (v >> 30)) * 0xBF58476D1CE4E5B9ULL;
    v = (v ^ (v >> 27)) * 0x94D049BB133111EBULL;
    return v ^ (v >> 31);
}

int main(void) {
    volatile uint64_t data[16];
    uint64_t key = 0xDEADBEEFCAFEBABEULL;
    int iter, i;

    for (iter = 0; iter < 2000; iter++) {
        /* Fill data array with hash-derived values */
        for (i = 0; i < 16; i++) {
            data[i] = hash((uint64_t)iter ^ (uint64_t)i, key);
        }

        /* Arithmetic verification: sum of [i] XOR [15-i] should equal
         * sum of corresponding hash pairs (computed fresh each iteration). */
        uint64_t xor_sum = 0;
        for (i = 0; i < 8; i++) {
            xor_sum ^= data[i] ^ data[15 - i];
        }
        /* Recompute to compare */
        uint64_t xor_sum2 = 0;
        for (i = 0; i < 8; i++) {
            uint64_t h0 = hash((uint64_t)iter ^ (uint64_t)i,          key);
            uint64_t h1 = hash((uint64_t)iter ^ (uint64_t)(15 - i),   key);
            xor_sum2 ^= h0 ^ h1;
        }
        if (xor_sum != xor_sum2)
            return (int)(iter + 1);  /* non-zero = fail, encode iteration */

        /* Mul/div spot-check */
        volatile uint64_t m = data[0] & 0xFFFFFFFFULL;
        volatile uint64_t n = data[1] & 0xFFFFFFFFULL;
        if (n == 0) n = 1;
        volatile uint64_t mn = m * n;
        if (mn / n != m)
            return (int)(iter + 1);

        /* Branch-intensive check */
        uint64_t bits_set = 0;
        uint64_t v = data[2];
        while (v) {
            bits_set++;
            v &= v - 1ULL;
        }
        /* Verify popcount is in [0, 64] */
        if (bits_set > 64ULL)
            return (int)(iter + 1);

        key ^= data[iter & 15];
    }

    sink = key;
    return 0;
}
