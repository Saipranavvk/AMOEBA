/* tc_ecc_load_store.c
 *
 * Load/store heavy test.
 * Stresses the WriteDataM and ReadDataW pipeline register paths by
 * performing many stack spill/reload cycles, struct field accesses,
 * and array traversals.  Data flowing through the memory stage pipeline
 * registers must be ECC-corrected before writeback.
 */

#include <stdint.h>

volatile uint64_t sink;

typedef struct {
    uint64_t a, b, c, d;
    uint64_t e, f, g, h;
} quad_t;

static void fill_quad(quad_t *q, uint64_t base) {
    q->a = base;
    q->b = base ^ 0xAAAAAAAAAAAAAAAAULL;
    q->c = base + 1ULL;
    q->d = base - 1ULL;
    q->e = ~base;
    q->f = base << 1;
    q->g = base >> 1;
    q->h = base ^ (base << 32);
}

static int check_quad(const quad_t *q, uint64_t base) {
    if (q->a != base)                              return 1;
    if (q->b != (base ^ 0xAAAAAAAAAAAAAAAAULL))    return 1;
    if (q->c != (base + 1ULL))                     return 1;
    if (q->d != (base - 1ULL))                     return 1;
    if (q->e != (~base))                           return 1;
    if (q->f != (base << 1))                       return 1;
    if (q->g != (base >> 1))                       return 1;
    if (q->h != (base ^ (base << 32)))             return 1;
    return 0;
}

int main(void) {
    quad_t arr[8];
    uint64_t base = 0x0123456789ABCDEFULL;
    int i;

    /* Fill and check — exercises many store/load pairs */
    for (i = 0; i < 8; i++) {
        fill_quad(&arr[i], base + (uint64_t)(i * 16));
    }
    for (i = 0; i < 8; i++) {
        if (check_quad(&arr[i], base + (uint64_t)(i * 16)))
            return 1;
    }

    /* Array sum — exercises sequential loads */
    uint64_t sum = 0;
    for (i = 0; i < 8; i++) sum += arr[i].a;
    uint64_t expected_sum = 0;
    for (i = 0; i < 8; i++) expected_sum += base + (uint64_t)(i * 16);
    if (sum != expected_sum)
        return 1;

    /* Stack spill pattern: force many variables live at once */
    volatile uint64_t v0  = 0x0000000000000001ULL;
    volatile uint64_t v1  = 0x0000000000000002ULL;
    volatile uint64_t v2  = 0x0000000000000004ULL;
    volatile uint64_t v3  = 0x0000000000000008ULL;
    volatile uint64_t v4  = 0x0000000000000010ULL;
    volatile uint64_t v5  = 0x0000000000000020ULL;
    volatile uint64_t v6  = 0x0000000000000040ULL;
    volatile uint64_t v7  = 0x0000000000000080ULL;
    volatile uint64_t v8  = 0x0000000000000100ULL;
    volatile uint64_t v9  = 0x0000000000000200ULL;
    volatile uint64_t v10 = 0x0000000000000400ULL;
    volatile uint64_t v11 = 0x0000000000000800ULL;

    uint64_t s = v0 | v1 | v2 | v3 | v4 | v5 | v6 | v7 | v8 | v9 | v10 | v11;
    if (s != 0x0000000000000FFFULL)
        return 1;

    sink = s ^ sum;
    return 0;
}
