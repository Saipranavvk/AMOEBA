///////////////////////////////////////////
// tc_alu_and_shift.c
//
// TC_ALU_BASIC     - ADD, SUB, XOR, OR, AND
// TC_SHIFT_OPERATIONS - SLL, SRL, SRA
//
// Each operation is forced through a volatile barrier so the compiler
// cannot fold it at compile time.  The __asm__ clobber on "memory"
// prevents the optimizer reordering across the check points.
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

#include "test_utils.h"

// Force the compiler to actually emit the instruction by routing
// through inline asm.  This guarantees the RTL sees each operation
// rather than having the compiler constant-fold it away.

static inline int64_t do_add(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("add %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline int64_t do_sub(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("sub %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline int64_t do_xor(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("xor %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline int64_t do_or(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("or %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}
static inline int64_t do_and(int64_t a, int64_t b) {
    int64_t r;
    __asm__ volatile ("and %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

// Shift wrappers
static inline uint64_t do_sll(uint64_t a, int shamt) {
    uint64_t r;
    __asm__ volatile ("sll %0, %1, %2" : "=r"(r) : "r"(a), "r"((uint64_t)shamt));
    return r;
}
static inline uint64_t do_srl(uint64_t a, int shamt) {
    uint64_t r;
    __asm__ volatile ("srl %0, %1, %2" : "=r"(r) : "r"(a), "r"((uint64_t)shamt));
    return r;
}
static inline int64_t do_sra(int64_t a, int shamt) {
    int64_t r;
    __asm__ volatile ("sra %0, %1, %2" : "=r"(r) : "r"(a), "r"((int64_t)shamt));
    return r;
}

// -------------------------------------------------------------------------
// TC_ALU_BASIC
// -------------------------------------------------------------------------
void tc_alu_basic(void) {
    test_begin("TC_ALU_BASIC");

    // Positive + positive
    check("ADD  10+20=30",       (uint64_t)do_add(10, 20),         30ULL);
    // Positive + negative
    check("ADD  10+(-10)=0",     (uint64_t)do_add(10, -10),         0ULL);
    // Zero operand
    check("ADD  0+0=0",          (uint64_t)do_add(0, 0),             0ULL);
    // Large values
    check("ADD  MAX32+1",
          (uint64_t)do_add(0x7FFFFFFFLL, 1LL),
          0x80000000ULL);

    // SUB positive result
    check("SUB  30-10=20",       (uint64_t)do_sub(30, 10),         20ULL);
    // SUB negative result
    check("SUB  5-10=-5",        (uint64_t)do_sub(5, 10),
          (uint64_t)(-5LL));
    // SUB zero
    check("SUB  7-7=0",          (uint64_t)do_sub(7, 7),             0ULL);

    // XOR
    check("XOR  0xFF^0x0F=0xF0", (uint64_t)do_xor(0xFF, 0x0F),   0xF0ULL);
    check("XOR  x^x=0",          (uint64_t)do_xor(0xDEAD, 0xDEAD), 0ULL);
    check("XOR  0^x=x",          (uint64_t)do_xor(0, 0xABCD),  0xABCDULL);

    // OR
    check("OR   0xF0|0x0F=0xFF", (uint64_t)do_or(0xF0, 0x0F),    0xFFULL);
    check("OR   0|0=0",          (uint64_t)do_or(0, 0),              0ULL);
    check("OR   x|x=x",          (uint64_t)do_or(0x5A5A, 0x5A5A),
          0x5A5AULL);

    // AND
    check("AND  0xFF&0x0F=0x0F", (uint64_t)do_and(0xFF, 0x0F),   0x0FULL);
    check("AND  x&0=0",          (uint64_t)do_and(0xDEAD, 0),       0ULL);
    check("AND  x&(-1)=x",       (uint64_t)do_and(0xBEEF, -1LL),
          0xBEEFULL);
}

// -------------------------------------------------------------------------
// TC_SHIFT_OPERATIONS
// -------------------------------------------------------------------------
void tc_shift_operations(void) {
    test_begin("TC_SHIFT_OPERATIONS");

    // SLL
    check("SLL  1<<0  =1",       do_sll(1ULL, 0),             1ULL);
    check("SLL  1<<1  =2",       do_sll(1ULL, 1),             2ULL);
    check("SLL  1<<63 =MSB",     do_sll(1ULL, 63),
          0x8000000000000000ULL);
    check("SLL  0xFF<<8=0xFF00", do_sll(0xFFULL, 8),       0xFF00ULL);
    // Shift a value with MSB set
    check("SLL  MSB<<1 wraps",   do_sll(0x8000000000000000ULL, 1), 0ULL);

    // SRL (logical: MSB filled with 0)
    check("SRL  0xFF>>0  =0xFF", do_srl(0xFFULL, 0),          0xFFULL);
    check("SRL  0xFF>>4  =0xF",  do_srl(0xFFULL, 4),           0xFULL);
    check("SRL  MSB>>1   =pos",
          do_srl(0x8000000000000000ULL, 1),
          0x4000000000000000ULL);
    check("SRL  MSB>>63  =1",
          do_srl(0x8000000000000000ULL, 63), 1ULL);
    check("SRL  x>>XLEN-1=msb",
          do_srl(0xFFFFFFFFFFFFFFFFULL, 63), 1ULL);

    // SRA (arithmetic: MSB sign-extended)
    check("SRA  pos>>1  =pos/2",
          (uint64_t)do_sra(100LL, 1),        50ULL);
    check("SRA  neg>>0  =neg",
          (uint64_t)do_sra(-1LL, 0),
          (uint64_t)(-1LL));
    check("SRA  neg>>1  stays neg",
          (uint64_t)do_sra((int64_t)0x8000000000000000LL, 1),
          (uint64_t)0xC000000000000000ULL);
    check("SRA  -1>>63  =-1",
          (uint64_t)do_sra(-1LL, 63),
          (uint64_t)(-1LL));
    check("SRA  -128>>4 =-8",
          (uint64_t)do_sra(-128LL, 4),
          (uint64_t)(-8LL));
}

int main(void) {
      tc_alu_basic();
      tc_shift_operations();

    test_finish();
}