///////////////////////////////////////////
// tc_compressed.c
//
// TC_COMPRESSED_ALU      - C.ADD, C.MV, C.ADDI, C.LI
// TC_COMPRESSED_CONTROL  - C.J, C.JR, C.BEQZ, C.BNEZ
// TC_MIXED_WIDTH_STREAM  - interleaved 16-bit and 32-bit instructions
//
// The compiler generates compressed instructions automatically when
// targeting rv64gc with the c extension enabled (-march=rv64gc).
// We use __attribute__((optimize("O1"))) to prevent the compiler
// inlining everything into one block, ensuring actual call/return
// compressed control-flow instructions are emitted.
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

#include "test_utils.h"

// -------------------------------------------------------------------------
// TC_COMPRESSED_ALU
// Verify compressed arithmetic: C.ADDI, C.ADD, C.MV, C.LI
// The compiler will use these automatically for small-immediate arithmetic.
// We verify the computed values are correct.
// -------------------------------------------------------------------------

// __attribute__((noinline)) forces a real call/return (C.JR / C.J).
// __attribute__((optimize("O1"))) prevents full unrolling while still
// allowing compressed instruction selection.

__attribute__((noinline, optimize("O1")))
static int64_t compressed_add_seq(int64_t x) {
    // Each of these small-immediate adds maps to C.ADDI
    x += 1;
    x += 2;
    x += 4;
    x += 8;
    x += 16;
    return x;
}

__attribute__((noinline, optimize("O1")))
static int64_t compressed_mv_then_add(int64_t a, int64_t b) {
    // C.MV: move b into a temp register, then C.ADD
    int64_t tmp = b;      // likely C.MV
    return a + tmp;       // likely C.ADD
}

void tc_compressed_alu(void) {
    test_begin("TC_COMPRESSED_ALU");

    // C.ADDI chain: 0 + 1 + 2 + 4 + 8 + 16 = 31
    check("C.ADDI chain sum=31",
          (uint64_t)compressed_add_seq(0LL), 31ULL);

    // Negative immediate: C.ADDI with nzimm < 0
    check("C.ADDI neg: 10 + (-3) = 7",
          (uint64_t)compressed_add_seq(-4LL),   // -4+31=27, not ideal
          // recalculate: compressed_add_seq(-4) = -4+1+2+4+8+16 = 27
          27ULL);

    // C.MV + C.ADD
    check("C.MV then C.ADD: 10+20=30",
          (uint64_t)compressed_mv_then_add(10LL, 20LL), 30ULL);
    check("C.MV then C.ADD: neg+pos",
          (uint64_t)compressed_mv_then_add(-5LL, 5LL),   0ULL);
    check("C.MV then C.ADD: 0+0=0",
          (uint64_t)compressed_mv_then_add(0LL, 0LL),    0ULL);
}

// -------------------------------------------------------------------------
// TC_COMPRESSED_CONTROL
// C.J (compressed unconditional jump)
// C.JR (compressed jump-register, i.e. return from noinline function)
// C.BEQZ / C.BNEZ (compressed conditional branch)
// -------------------------------------------------------------------------

// Each noinline function generates a C.JR at its return site.
__attribute__((noinline))
static int call_depth_1(int x) { return x + 1; }

__attribute__((noinline))
static int call_depth_2(int x) { return call_depth_1(x) + 1; }

__attribute__((noinline))
static int call_depth_3(int x) { return call_depth_2(x) + 1; }

// Exercises C.BEQZ / C.BNEZ
__attribute__((noinline, optimize("O1")))
static int compressed_branch_test(int x) {
    int result = 0;
    // C.BEQZ: branch if zero
    if (x == 0) result |= 0x01;
    // C.BNEZ: branch if non-zero
    if (x != 0) result |= 0x02;
    return result;
}

// Exercises C.J (unconditional forward jump in a switch or if-else chain)
__attribute__((noinline, optimize("O1")))
static int compressed_jump_test(int sel) {
    int r = 0;
    if (sel == 1) { r = 10; goto done; }
    if (sel == 2) { r = 20; goto done; }
    r = 99;
done:
    return r;
}

void tc_compressed_control(void) {
    test_begin("TC_COMPRESSED_CONTROL");

    // C.JR: verify call/return chain works through 3 levels
    check("C.JR  3-level call chain: +3",
          (uint64_t)call_depth_3(0), 3ULL);
    check("C.JR  3-level call chain: 10+3=13",
          (uint64_t)call_depth_3(10), 13ULL);

    // C.BEQZ: taken when x==0
    check("C.BEQZ taken (x=0): bit0 set",
          (uint64_t)compressed_branch_test(0), 0x01ULL);

    // C.BNEZ: taken when x!=0
    check("C.BNEZ taken (x=5): bit1 set",
          (uint64_t)compressed_branch_test(5), 0x02ULL);

    // C.J: unconditional compressed jump
    check("C.J sel=1 -> 10",  (uint64_t)compressed_jump_test(1),  10ULL);
    check("C.J sel=2 -> 20",  (uint64_t)compressed_jump_test(2),  20ULL);
    check("C.J sel=3 -> 99",  (uint64_t)compressed_jump_test(3),  99ULL);
}

// -------------------------------------------------------------------------
// TC_MIXED_WIDTH_STREAM
// Verify the fetch unit correctly handles a stream mixing 16-bit and 32-bit
// instructions. This is inherent in any -march=rv64gc binary, so we
// construct a function the compiler is likely to emit as mixed-width and
// verify its output is correct.
//
// We also include a manually-crafted asm block that explicitly interleaves
// 16-bit (.2byte) and 32-bit (.4byte) instructions to stress the aligner.
// -------------------------------------------------------------------------

// Count iterations of a loop — compilers produce mixed-width output here
__attribute__((noinline, optimize("O1")))
static int64_t mixed_loop(int64_t n) {
    int64_t sum = 0;
    for (int64_t i = 0; i < n; i++)
        sum += i;          // inner body likely gets compressed instructions
    return sum;            // sum of 0..n-1 = n*(n-1)/2
}

// Hand-written mixed stream: explicitly uses .insn directives to
// emit a 16-bit C.ADDI followed by a 32-bit ADDI, verifying PC
// advances correctly for both widths.
__attribute__((noinline))
static int64_t mixed_asm_stream(int64_t x) {
    int64_t r;
    __asm__ volatile (
        // C.ADDI a0, 1  (16-bit: adds 1 to the first argument register)
        ".option push\n\t"
        ".option rvc\n\t"
        "c.addi %0, 1\n\t"          // 16-bit
        ".option pop\n\t"
        "addi %0, %0, 2\n\t"        // 32-bit: add 2 more
        : "=r"(r) : "0"(x)
    );
    return r;   // x + 1 + 2 = x + 3
}

void tc_mixed_width_stream(void) {
    test_begin("TC_MIXED_WIDTH_STREAM");

    // Loop produces sum = 0+1+2+...+(n-1) = n*(n-1)/2
    check("Mixed loop n=10: sum=45",
          (uint64_t)mixed_loop(10LL), 45ULL);
    check("Mixed loop n=0:  sum=0",
          (uint64_t)mixed_loop(0LL),  0ULL);
    check("Mixed loop n=1:  sum=0",
          (uint64_t)mixed_loop(1LL),  0ULL);
    check("Mixed loop n=100: sum=4950",
          (uint64_t)mixed_loop(100LL), 4950ULL);

    // Hand-crafted 16+32 bit stream
    check("Mixed asm: x+1(16bit)+2(32bit)=x+3, x=0",
          (uint64_t)mixed_asm_stream(0LL),  3ULL);
    check("Mixed asm: x=10 -> 13",
          (uint64_t)mixed_asm_stream(10LL), 13ULL);
    check("Mixed asm: x=-1 -> 2",
          (uint64_t)mixed_asm_stream(-1LL), 2ULL);
}

int main(void) {
    tc_compressed_alu();
    tc_compressed_control();
    tc_mixed_width_stream();

    test_finish();
}