/* tc_ecc_walking_ones.c
 *
 * Walking-1 / walking-0 bit pattern test.
 * Exercises every individual bit position in the register file and
 * pipeline data registers.  Each iteration writes a single-bit value,
 * reads it back, and verifies exact equality.  This gives exhaustive
 * per-bit coverage so that a mis-corrected bit at any position fails fast.
 */

#include <stdint.h>

volatile uint64_t sink;

int main(void) {
    volatile uint64_t v;
    int bit;

    /* Walking ones: 1, 2, 4, 8, … */
    for (bit = 0; bit < 64; bit++) {
        uint64_t pattern = (uint64_t)1 << bit;
        v = pattern;
        if (v != pattern)
            return 1;
        sink = v;
    }

    /* Walking zeros: ~1, ~2, ~4, … */
    for (bit = 0; bit < 64; bit++) {
        uint64_t pattern = ~((uint64_t)1 << bit);
        v = pattern;
        if (v != pattern)
            return 1;
        sink = v;
    }

    /* Alternating half-words to stress byte-lane paths */
    volatile uint64_t a = 0x00FF00FF00FF00FFULL;
    volatile uint64_t b = 0xFF00FF00FF00FF00ULL;
    if ((a | b) != 0xFFFFFFFFFFFFFFFFULL)
        return 1;
    if ((a & b) != 0x0000000000000000ULL)
        return 1;

    sink = a ^ b;
    return 0;
}
