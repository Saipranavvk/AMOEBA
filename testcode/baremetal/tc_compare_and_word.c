///////////////////////////////////////////
// tc_compare_and_word.c
//
// TC_COMPARE_BRANCH  - SLT, SLTU, BEQ, BNE, BLT, BGE
// TC_RV64_WORD_OPS   - ADDW, SUBW, SLLW, SRLW, SRAW
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

#include "test_utils.h"

// -------------------------------------------------------------------------
// Inline-asm wrappers so the compiler emits the exact instructions
// -------------------------------------------------------------------------

static inline int64_t do_slt(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("slt %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline uint64_t do_sltu(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ volatile ("sltu %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

// Branch tests: use asm goto so the compiler emits the actual branch
// instruction.  Each macro sets a result variable to 1 if taken, 0 if not.
// #define BRANCH_TAKEN(insn, a, b)  ({            
//     int _t = 0;                                 
//     __asm__ goto (insn " %0, %1, %l2"           
//                   :: "r"(a), "r"(b)             
//                   : : _taken);                  
//     goto _done;                                 
//     _taken: _t = 1;                             
//     _done: _t;                                  
// })


#define BRANCH_TAKEN(insn, a, b) ({               \
    int _t;                                       \
    __asm__ volatile (                            \
        "li %0, 0\n\t"                            \
        insn " %1, %2, 1f\n\t"                    \
        "j 2f\n\t"                                \
        "1:\n\t"                                 \
        "li %0, 1\n\t"                            \
        "2:\n\t"                                 \
        : "=&r"(_t)                              \
        : "r"(a), "r"(b)                          \
        : "memory"                               \
    );                                            \
    _t;                                           \
})
// RV64 word-operation wrappers
static inline int64_t do_addw(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("addw %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline int64_t do_subw(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("subw %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline int64_t do_sllw(int64_t a, int shamt) {
    int64_t r;
    __asm__ volatile ("sllw %0, %1, %2" : "=r"(r) : "r"(a), "r"((int64_t)shamt));
    return r;
}
static inline int64_t do_srlw(int64_t a, int shamt) {
    int64_t r;
    __asm__ volatile ("srlw %0, %1, %2" : "=r"(r) : "r"(a), "r"((int64_t)shamt));
    return r;
}
static inline int64_t do_sraw(int64_t a, int shamt) {
    int64_t r;
    __asm__ volatile ("sraw %0, %1, %2" : "=r"(r) : "r"(a), "r"((int64_t)shamt));
    return r;
}

// -------------------------------------------------------------------------
// TC_COMPARE_BRANCH
// -------------------------------------------------------------------------
void tc_compare_branch(void) {
    test_begin("TC_COMPARE_BRANCH");

    // SLT  (signed less-than)
    check("SLT   -1 < 5  = 1",  (uint64_t)do_slt(-1LL,  5LL),  1ULL);
    check("SLT    5 < -1 = 0",  (uint64_t)do_slt( 5LL, -1LL),  0ULL);
    check("SLT    5 < 5  = 0",  (uint64_t)do_slt( 5LL,  5LL),  0ULL);
    check("SLT  MIN < 0  = 1",
          (uint64_t)do_slt((int64_t)0x8000000000000000LL, 0LL), 1ULL);

    // SLTU (unsigned less-than)
    check("SLTU  5 < MAXU = 1",
          do_sltu(5ULL, 0xFFFFFFFFFFFFFFFFULL), 1ULL);
    check("SLTU  MAXU < 5 = 0",
          do_sltu(0xFFFFFFFFFFFFFFFFULL, 5ULL), 0ULL);
    check("SLTU  0 < 1    = 1",
          do_sltu(0ULL, 1ULL), 1ULL);
    // -1 unsigned is MAXUINT, larger than 5
    check("SLTU  (uint)-1 > 5",
          do_sltu((uint64_t)(-1LL), 5ULL), 0ULL);

    // BEQ
    check_bool("BEQ   5==5  taken",
               BRANCH_TAKEN("beq", 5L, 5L));
    check_bool("BEQ   5==6  not taken",
               !BRANCH_TAKEN("beq", 5L, 6L));
    check_bool("BEQ   0==0  taken",
               BRANCH_TAKEN("beq", 0L, 0L));

    // BNE
    check_bool("BNE   5!=6  taken",
               BRANCH_TAKEN("bne", 5L, 6L));
    check_bool("BNE   5!=5  not taken",
               !BRANCH_TAKEN("bne", 5L, 5L));

    // BLT (signed)
    check_bool("BLT  -1 < 5  taken",
               BRANCH_TAKEN("blt", -1L, 5L));
    check_bool("BLT   5 < -1 not taken",
               !BRANCH_TAKEN("blt", 5L, -1L));
    check_bool("BLT   5 < 5  not taken",
               !BRANCH_TAKEN("blt", 5L, 5L));

    // BGE (signed)
    check_bool("BGE   5 >= -1 taken",
               BRANCH_TAKEN("bge", 5L, -1L));
    check_bool("BGE   5 >=  5 taken",
               BRANCH_TAKEN("bge", 5L, 5L));
    check_bool("BGE  -1 >=  5 not taken",
               !BRANCH_TAKEN("bge", -1L, 5L));
}

// -------------------------------------------------------------------------
// TC_RV64_WORD_OPS
// All results must be sign-extended from 32 bits to 64 bits.
// -------------------------------------------------------------------------
void tc_rv64_word_ops(void) {
    test_begin("TC_RV64_WORD_OPS");

    // ADDW: overflow wraps at 32 bits, then sign-extends
    // 0x7FFFFFFF + 1 = 0x80000000 (32-bit) -> sign-extended to neg
    check("ADDW  MAX32+1 sign-ext",
          (uint64_t)do_addw(0x7FFFFFFFLL, 1LL),
          0xFFFFFFFF80000000ULL);

    // ADDW positive no overflow
    check("ADDW  10+20=30",
          (uint64_t)do_addw(10LL, 20LL), 30ULL);

    // ADDW negative + positive = 0
    check("ADDW  -1+1=0",
          (uint64_t)do_addw(-1LL, 1LL), 0ULL);

    // SUBW: result sign-extended
    // 1 - 2 = -1 as 32-bit -> 0xFFFFFFFFFFFFFFFF
    check("SUBW  1-2=-1 sign-ext",
          (uint64_t)do_subw(1LL, 2LL),
          0xFFFFFFFFFFFFFFFFULL);

    // SUBW zero result
    check("SUBW  5-5=0",
          (uint64_t)do_subw(5LL, 5LL), 0ULL);

    // SUBW underflow: 0 - 0x80000000 = 0x80000000 (stays neg after sign-ext)
    check("SUBW  0-MIN32 sign-ext",
          (uint64_t)do_subw(0LL, 0x80000000LL),
          0xFFFFFFFF80000000ULL);

    // SLLW: shift left within 32 bits, sign-extend result
    // 0x40000000 << 1 = 0x80000000 -> sign-extended negative
    check("SLLW  0x40000000<<1 sign-ext",
          (uint64_t)do_sllw(0x40000000LL, 1),
          0xFFFFFFFF80000000ULL);

    // SLLW positive result
    check("SLLW  1<<4=16",
          (uint64_t)do_sllw(1LL, 4), 16ULL);

    // SRLW: logical right shift on 32-bit value, zero-extended into 64
    // 0x80000000 >> 1 = 0x40000000 (zero-fill, not sign-fill)
    check("SRLW  0x80000000>>1=0x40000000",
          (uint64_t)do_srlw((int64_t)0x80000000LL, 1),
          0x40000000ULL);

    // SRLW shift by 0
    check("SRLW  x>>0=x (zero-ext)",
          (uint64_t)do_srlw(0x12345678LL, 0),
          0x12345678ULL);

    // SRAW: arithmetic right shift on 32-bit value, sign-extended
    // 0x80000000 >> 1 = 0xC0000000 (sign-fill), then sign-extended
    check("SRAW  0x80000000>>1 sign-fill+ext",
          (uint64_t)do_sraw((int64_t)0x80000000LL, 1),
          0xFFFFFFFFC0000000ULL);

    // SRAW positive value: same as SRL
    check("SRAW  0x7FFFFFFF>>1=0x3FFFFFFF",
          (uint64_t)do_sraw(0x7FFFFFFFLL, 1),
          0x3FFFFFFFULL);

    // SRAW by 31: propagates sign bit across all 32 bits
    check("SRAW  neg>>31 = -1 sign-ext",
          (uint64_t)do_sraw((int64_t)0x80000000LL, 31),
          0xFFFFFFFFFFFFFFFFULL);
}

int main(void) {
    tc_compare_branch();
    tc_rv64_word_ops();

    return 0;
}