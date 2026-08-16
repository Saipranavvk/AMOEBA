///////////////////////////////////////////
// tc_mul_div.c
//
// TC_MUL_OPERATIONS  - MUL, MULH, MULHU, MULHSU
// TC_DIV_OPERATIONS  - DIV, DIVU, REM, REMU
//                      Corner cases: div-by-zero, INT64_MIN/-1
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

#include "test_utils.h"

// -------------------------------------------------------------------------
// Inline-asm wrappers
// -------------------------------------------------------------------------

static inline int64_t do_mul(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("mul %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline int64_t do_mulh(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("mulh %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline uint64_t do_mulhu(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ volatile ("mulhu %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline int64_t do_mulhsu(int64_t a, uint64_t b) {
    int64_t r;
    __asm__ volatile ("mulhsu %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

static inline int64_t do_div(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("div %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline uint64_t do_divu(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ volatile ("divu %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline int64_t do_rem(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("rem %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline uint64_t do_remu(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ volatile ("remu %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

// -------------------------------------------------------------------------
// TC_MUL_OPERATIONS
// -------------------------------------------------------------------------
void tc_mul_operations(void) {
    test_begin("TC_MUL_OPERATIONS");

    // MUL: lower 64 bits of product
    check("MUL   3*4=12",
          (uint64_t)do_mul(3LL, 4LL), 12ULL);
    check("MUL   (-3)*4=-12",
          (uint64_t)do_mul(-3LL, 4LL), (uint64_t)(-12LL));
    check("MUL   (-3)*(-4)=12",
          (uint64_t)do_mul(-3LL, -4LL), 12ULL);
    check("MUL   0*MAX=0",
          (uint64_t)do_mul(0LL, (int64_t)0x7FFFFFFFFFFFFFFFLL), 0ULL);

    // MUL overflow: lower 64 of large product
    // 0x100000000 * 0x100000000 = 0x10000000000000000 -> lower 64 = 0
    check("MUL   2^32 * 2^32 lower=0",
          (uint64_t)do_mul(0x100000000LL, 0x100000000LL), 0ULL);

    // MULH: upper 64 bits, signed * signed
    // Small positive values: upper bits are 0
    check("MULH  3*4 upper=0",
          (uint64_t)do_mulh(3LL, 4LL), 0ULL);
    // Large * large: upper bits non-zero
    // 0x7FFFFFFFFFFFFFFF * 0x7FFFFFFFFFFFFFFF:
    // upper 64 = 0x3FFFFFFFFFFFFFFF
    check("MULH  MAX64s*MAX64s upper",
          (uint64_t)do_mulh(0x7FFFFFFFFFFFFFFFLL,
                            0x7FFFFFFFFFFFFFFFLL),
          0x3FFFFFFFFFFFFFFFULL);
    // (-1) * (-1) = 1, upper = 0
    check("MULH  (-1)*(-1) upper=0",
          (uint64_t)do_mulh(-1LL, -1LL), 0ULL);
    // (-1) * 1 = -1, upper = -1 (all ones)
    check("MULH  (-1)*1 upper=-1",
          (uint64_t)do_mulh(-1LL, 1LL),
          (uint64_t)(-1LL));

    // MULHU: upper 64 bits, unsigned * unsigned
    check("MULHU small*small upper=0",
          do_mulhu(100ULL, 200ULL), 0ULL);
    // MAXUINT * MAXUINT upper = MAXUINT - 1
    check("MULHU MAXU*MAXU upper",
          do_mulhu(0xFFFFFFFFFFFFFFFFULL,
                   0xFFFFFFFFFFFFFFFFULL),
          0xFFFFFFFFFFFFFFFEULL);

    // MULHSU: upper 64, signed * unsigned
    // Positive * unsigned, small: upper = 0
    check("MULHSU 3*(u)4 upper=0",
          (uint64_t)do_mulhsu(3LL, 4ULL), 0ULL);
    // (-1) * MAXUINT: signed=-1 means 0xFFFF... unsigned.
    // (-1)*(MAXUINT) = -MAXUINT = -(2^64-1),
    // lower 64 = 1, upper = -1
    check("MULHSU (-1)*MAXU upper=-1",
          (uint64_t)do_mulhsu(-1LL,
                              0xFFFFFFFFFFFFFFFFULL),
          (uint64_t)(-1LL));
}

// -------------------------------------------------------------------------
// TC_DIV_OPERATIONS
// -------------------------------------------------------------------------
void tc_div_operations(void) {
    test_begin("TC_DIV_OPERATIONS");

    // Normal cases
    check("DIV   100/7=14",
          (uint64_t)do_div(100LL, 7LL), 14ULL);
    check("DIV   -100/7=-14",
          (uint64_t)do_div(-100LL, 7LL), (uint64_t)(-14LL));
    check("DIV   100/(-7)=-14",
          (uint64_t)do_div(100LL, -7LL), (uint64_t)(-14LL));
    check("DIV   (-100)/(-7)=14",
          (uint64_t)do_div(-100LL, -7LL), 14ULL);
    check("DIV   1/1=1",
          (uint64_t)do_div(1LL, 1LL), 1ULL);

    // Corner case: divide by zero
    // RISC-V spec: DIV x/0 = -1 (all ones)
    check("DIV   x/0=-1",
          (uint64_t)do_div(42LL, 0LL),
          0xFFFFFFFFFFFFFFFFULL);

    // Corner case: INT64_MIN / -1 = INT64_MIN (overflow)
    check("DIV   INT64_MIN/(-1)=INT64_MIN",
          (uint64_t)do_div((int64_t)0x8000000000000000LL, -1LL),
          0x8000000000000000ULL);

    // DIVU normal
    check("DIVU  100/7=14",
          do_divu(100ULL, 7ULL), 14ULL);
    check("DIVU  MAXU/2=half",
          do_divu(0xFFFFFFFFFFFFFFFFULL, 2ULL),
          0x7FFFFFFFFFFFFFFFULL);

    // DIVU divide by zero: result = MAXUINT
    check("DIVU  x/0=MAXUINT",
          do_divu(42ULL, 0ULL),
          0xFFFFFFFFFFFFFFFFULL);

    // REM normal
    check("REM   100%7=2",
          (uint64_t)do_rem(100LL, 7LL), 2ULL);
    check("REM   (-100)%7=-2",
          (uint64_t)do_rem(-100LL, 7LL), (uint64_t)(-2LL));
    check("REM   100%(-7)=2",
          (uint64_t)do_rem(100LL, -7LL), 2ULL);

    // REM divide by zero: result = dividend
    check("REM   42%0=42",
          (uint64_t)do_rem(42LL, 0LL), 42ULL);

    // REM of INT64_MIN / -1 = 0 (exact division, remainder 0)
    check("REM   INT64_MIN%(-1)=0",
          (uint64_t)do_rem((int64_t)0x8000000000000000LL, -1LL), 0ULL);

    // REMU normal
    check("REMU  100%7=2",
          do_remu(100ULL, 7ULL), 2ULL);

    // REMU divide by zero: result = dividend
    check("REMU  42%0=42",
          do_remu(42ULL, 0ULL), 42ULL);
}

int main(void) {
    tc_mul_operations();
    tc_div_operations();

    test_finish();
}