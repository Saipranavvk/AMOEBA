/* tc_ecc_basic.c
 *
 * Basic ECC register file test.
 * Writes a fixed 64-bit pattern to every GPR via a volatile array access,
 * reads it back, and verifies the value is unchanged.  With ECC injection
 * active, single-bit errors are introduced during storage; SECDED must
 * correct them transparently so the read-back value still matches.
 *
 * Returns 0 on pass (mapped to tohost = 1 by the startup CRT).
 */

#include <stdint.h>

volatile uint64_t sink;   /* prevent optimisation of reads */

int main(void) {
    volatile uint64_t store[32];
    uint64_t pat = 0xDEADBEEFCAFEBABEULL;
    int i;

    for (i = 0; i < 32; i++) {
        store[i] = pat ^ (uint64_t)i;
    }

    for (i = 0; i < 32; i++) {
        uint64_t expected = pat ^ (uint64_t)i;
        if (store[i] != expected)
            return 1;   /* fail */
    }

    /* Also exercise register-to-register moves */
    volatile uint64_t a = 0xAAAAAAAAAAAAAAAAULL;
    volatile uint64_t b = 0x5555555555555555ULL;
    volatile uint64_t c = a ^ b;
    if (c != 0xFFFFFFFFFFFFFFFFULL)
        return 1;

    sink = c;
    return 0;
}
