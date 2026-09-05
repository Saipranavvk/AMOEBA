/* tc_ecc_alu_chain.c
 *
 * Long ALU dependency chains.
 * Each chain passes a value through many successive ALU operations so that
 * the result spends multiple clock cycles in D→E, E→M, and M→W pipeline
 * registers.  ECC injection during transit must be corrected or the final
 * accumulated value will differ from the expected constant.
 */

#include <stdint.h>

volatile uint64_t sink;

/* Compute a known result via a sequence of ALU ops. */
static uint64_t alu_chain(uint64_t seed) {
    uint64_t a = seed;
    int i;
    for (i = 0; i < 64; i++) {
        a = (a ^ (a << 7)) + 0x9E3779B97F4A7C15ULL;
        a = (a >> 13) | (a << 51);
        a ^= a >> 17;
        a += a << 3;
    }
    return a;
}

int main(void) {
    /* Run two identical chains; results must match. */
    volatile uint64_t r1 = alu_chain(0xDEADBEEFCAFEBABEULL);
    volatile uint64_t r2 = alu_chain(0xDEADBEEFCAFEBABEULL);

    if (r1 != r2)
        return 1;

    /* Chain that exercises subtract, AND, OR, XOR, shifts */
    volatile uint64_t x = 0xFFFFFFFF00000000ULL;
    volatile uint64_t y = 0x00000000FFFFFFFFULL;
    volatile uint64_t z;

    z = (x - y) ^ (x + y);         /* mix of add, sub, xor */
    z = (z & 0xF0F0F0F0F0F0F0F0ULL) | (z >> 4);
    z = z + (z << 13);
    z ^= (z >> 7);

    volatile uint64_t z2 = (x - y) ^ (x + y);
    z2 = (z2 & 0xF0F0F0F0F0F0F0F0ULL) | (z2 >> 4);
    z2 = z2 + (z2 << 13);
    z2 ^= (z2 >> 7);

    if (z != z2)
        return 1;

    /* 200 iterations of mixed ops to accumulate injection events */
    volatile uint64_t acc = 1ULL;
    int j;
    for (j = 0; j < 200; j++) {
        acc ^= acc << 13;
        acc ^= acc >> 7;
        acc ^= acc << 17;
    }
    volatile uint64_t acc2 = 1ULL;
    for (j = 0; j < 200; j++) {
        acc2 ^= acc2 << 13;
        acc2 ^= acc2 >> 7;
        acc2 ^= acc2 << 17;
    }
    if (acc != acc2)
        return 1;

    sink = acc ^ r1 ^ z;
    return 0;
}
