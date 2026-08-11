///////////////////////////////////////////
// tc_zbkb_and_smc.c
//
// TC_ZBKB_INSTRUCTIONS   - REV8, PACK, PACKH, BREV8, PACKW
// TC_SELF_MODIFYING_CODE - write new instruction, FENCE.I, re-execute
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

#include "test_utils.h"
#include <stdint.h>

// -------------------------------------------------------------------------
// ZBKB inline-asm wrappers
// Encoding note: Zbkb is enabled with -march=rv64gc_zbkb
// If your toolchain doesn't accept the mnemonic directly, use
// .insn r with the correct funct7/funct3 fields.
// -------------------------------------------------------------------------

static inline uint64_t do_rev8(uint64_t a) {
    uint64_t r;
    // REV8 rd,rs: funct12=0x6B8, opcode=OP-IMM (0x13), funct3=5
    // Encoding: 0110101 00000 rs 101 rd 0010011
    __asm__ volatile ("rev8 %0, %1" : "=r"(r) : "r"(a));
    return r;
}

static inline uint64_t do_pack(uint64_t a, uint64_t b) {
    uint64_t r;
    // PACK rd,rs1,rs2: funct7=0x04, funct3=4, opcode=OP (0x33)
    __asm__ volatile ("pack %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

static inline uint64_t do_packh(uint64_t a, uint64_t b) {
    uint64_t r;
    // PACKH rd,rs1,rs2: funct7=0x04, funct3=7, opcode=OP (0x33)
    __asm__ volatile ("packh %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

static inline uint64_t do_brev8(uint64_t a) {
    uint64_t r;
    // BREV8 rd,rs: reverses bits within each byte
    __asm__ volatile ("brev8 %0, %1" : "=r"(r) : "r"(a));
    return r;
}

static inline uint32_t do_packw(uint32_t a, uint32_t b) {
    uint64_t r;
    // PACKW rd,rs1,rs2 (RV64 only): packs lower 16 bits of each
    __asm__ volatile ("packw %0, %1, %2"
                      : "=r"(r)
                      : "r"((uint64_t)a), "r"((uint64_t)b));
    return (uint32_t)r;
}

// -------------------------------------------------------------------------
// TC_ZBKB_INSTRUCTIONS
// -------------------------------------------------------------------------
void tc_zbkb_instructions(void) {
    test_begin("TC_ZBKB_INSTRUCTIONS");

    // REV8: reverse byte order of 64-bit value
    // 0x0102030405060708 -> 0x0807060504030201
    check("REV8 0x0102030405060708",
          do_rev8(0x0102030405060708ULL),
          0x0807060504030201ULL);
    // REV8 of 0 = 0
    check("REV8 0=0",
          do_rev8(0ULL), 0ULL);
    // REV8 of 0xFFFFFFFFFFFFFFFF = 0xFFFFFFFFFFFFFFFF
    check("REV8 all-ones=all-ones",
          do_rev8(0xFFFFFFFFFFFFFFFFULL),
          0xFFFFFFFFFFFFFFFFULL);
    // REV8 known-answer vector
    check("REV8 0xDEADBEEFCAFEBABE",
          do_rev8(0xDEADBEEFCAFEBABEULL),
          0xBEBAFECAEFBEADDEULL);

    // PACK: lower 32 bits of rs1 into [31:0], lower 32 of rs2 into [63:32]
    // pack(0x11223344, 0xAABBCCDD) -> 0xAABBCCDD_11223344
    check("PACK 0x11223344, 0xAABBCCDD",
          do_pack(0x11223344ULL, 0xAABBCCDDULL),
          0xAABBCCDD11223344ULL);
    check("PACK 0, 0 = 0",
          do_pack(0ULL, 0ULL), 0ULL);
    check("PACK all-ones, all-ones = all-ones",
          do_pack(0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL),
          0xFFFFFFFFFFFFFFFFULL);
    // Upper 32 bits of rs1/rs2 are ignored
    check("PACK ignores upper 32 of src",
          do_pack(0xDEADBEEF11223344ULL, 0xCAFEBABEAABBCCDDULL),
          0xAABBCCDD11223344ULL);

    // PACKH: byte 0 of rs1 into [7:0], byte 0 of rs2 into [15:8], rest zero
    // packh(0x...AB, 0x...CD) -> 0x000000000000CDAB
    check("PACKH 0xAB, 0xCD -> 0xCDAB",
          do_packh(0xABULL, 0xCDULL),
          0x000000000000CDABULL);
    check("PACKH 0, 0 = 0",
          do_packh(0ULL, 0ULL), 0ULL);
    check("PACKH 0xFF, 0xFF -> 0xFFFF",
          do_packh(0xFFULL, 0xFFULL),
          0x000000000000FFFFULL);
    // Upper bytes of source ignored
    check("PACKH ignores upper bytes",
          do_packh(0xDEAD00ABULL, 0xBEEF00CDULL),
          0x000000000000CDABULL);

    // BREV8: reverse bits within each byte
    // 0b00000001 -> 0b10000000 per byte
    // 0x0102040810204080 ->
    // 0x80402010080402018 per byte reversal... let's use 0x01->0x80
    check("BREV8 0x01 per byte -> 0x80 per byte",
          do_brev8(0x0101010101010101ULL),
          0x8080808080808080ULL);
    check("BREV8 0xFF -> 0xFF (palindrome)",
          do_brev8(0xFFFFFFFFFFFFFFFFULL),
          0xFFFFFFFFFFFFFFFFULL);
    check("BREV8 0x00 -> 0x00",
          do_brev8(0x0000000000000000ULL),
          0x0000000000000000ULL);

    // PACKW (RV64 only): packs lower 16 of rs1 into [15:0],
    // lower 16 of rs2 into [31:16], sign-extend to 64 bits
    // packw(0x1234, 0x5678) -> 0xFFFFFFFF56781234 if bit31=1, else positive
    // For 0x1234, 0x5678: result = 0x56781234, sign bit [31]=0 -> zero-ext
    check("PACKW 0x1234, 0x5678 -> 0x56781234",
          (uint64_t)do_packw(0x1234U, 0x5678U),
          0x0000000056781234ULL);
    // With result bit[31]=1 -> sign-extended negative
    // packw(0xFFFF, 0x8000) -> 0x8000FFFF -> bit31=1 -> 0xFFFFFFFF8000FFFF
    check("PACKW 0xFFFF, 0x8000 -> sign-ext neg",
          (uint64_t)(int32_t)do_packw(0xFFFFU, 0x8000U),
          0xFFFFFFFF8000FFFFULL);
}

// -------------------------------------------------------------------------
// TC_SELF_MODIFYING_CODE
//
// Procedure:
//   1. Call target_function() -> it returns VALUE_BEFORE (0xAA)
//   2. Overwrite the first instruction of target_function with one that
//      loads VALUE_AFTER (0xBB) instead
//   3. Execute FENCE.I
//   4. Call target_function() again -> must now return VALUE_AFTER (0xBB)
//
// The function body is a simple "li a0, <value>; ret".
// We overwrite the "li a0, 0xAA" (addi a0, x0, 0xAA) with
//                                 addi a0, x0, 0xBB.
//
// RISC-V encoding:
//   addi rd, rs1, imm -> [imm(11:0) | rs1(5) | 000 | rd(5) | 0010011]
//   addi a0, x0, 0xAA = 0x0AA00513
//   addi a0, x0, 0xBB = 0x0BB00513
// -------------------------------------------------------------------------

// Marked noinline so the compiler doesn't inline and optimize away our patch
__attribute__((noinline))
static int smc_target(void) {
    int r;
    // "li a0, 0xAA" expands to "addi a0, x0, 0xAA"
    // We return via a0 (the C return register on RV64)
    __asm__ volatile (
        "addi a0, x0, 0xAA\n\t"
        "mv %0, a0"
        : "=r"(r) :: "a0"
    );
    return r;
}

void tc_self_modifying_code(void) {
    test_begin("TC_SELF_MODIFYING_CODE");

    // Step 1: verify initial behaviour
    int before = smc_target();
    check("SMC step 1: initial return = 0xAA",
          (uint64_t)before, 0xAAULL);

    // Step 2: patch the first instruction of smc_target
    // Get a writable pointer to the function body
    uint32_t *fn_ptr = (uint32_t *)(void *)smc_target;

    // The first instruction should be "addi a0, x0, 0xAA" = 0x0AA00513
    // Sanity check before patching (optional display, not a hard failure)
    if (*fn_ptr != 0x0AA00513U) {
        uart_puts("  NOTE: first instr = ");
        uart_puthex64((uint64_t)*fn_ptr);
        uart_puts(" (may be a compressed form or prologue; patch still applied)\n");
    }

    // Write "addi a0, x0, 0xBB" = 0x0BB00513
    *fn_ptr = 0x0BB00513U;

    // Step 3: synchronize instruction cache
    fence_i();

    // Step 4: re-execute
    int after = smc_target();
    check("SMC step 4: after FENCE.I return = 0xBB",
          (uint64_t)after, 0xBBULL);
}

int main(void) {
    tc_zbkb_instructions();
    tc_self_modifying_code();
    
    test_finish();
}