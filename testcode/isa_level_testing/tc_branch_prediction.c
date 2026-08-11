///////////////////////////////////////////
// tc_branch_prediction.c
//
// TC_TIGHT_LOOP          - heavily taken backward branch (GShare training)
// TC_ALTERNATING_BRANCH  - alternating T/NT pattern (predictor stress)
// TC_CALL_RETURN_PATTERN - deep call stack (BTB + RAS stress)
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

#include "test_utils.h"

// -------------------------------------------------------------------------
// TC_TIGHT_LOOP
//
// A tight decrement-and-branch loop that is taken ~99% of the time.
// The GShare predictor should quickly learn "always taken" for the back edge.
//
// We verify:
//   1. The loop completes (no hang, no wrong path)
//   2. The accumulator equals the expected sum
//   3. Cycle count is measured to give a rough sense of throughput
//      (not a hard pass/fail — just informational)
// -------------------------------------------------------------------------

#define TIGHT_LOOP_N 1000

__attribute__((noinline, optimize("O2")))
static uint64_t tight_loop(uint64_t n) {
    uint64_t sum = 0;
    // volatile prevents the compiler collapsing to a formula
    volatile uint64_t i;
    for (i = 0; i < n; i++)
        sum += i;
    return sum;
}

void tc_tight_loop(void) {
    test_begin("TC_TIGHT_LOOP");

    uint64_t t0 = read_cycle();
    uint64_t result = tight_loop(TIGHT_LOOP_N);
    uint64_t t1 = read_cycle();

    // sum 0..999 = 999*1000/2 = 499500
    check("Tight loop N=1000 sum=499500",
          result, 499500ULL);

    // Secondary: run again (predictor now warm) and verify result is stable
    uint64_t result2 = tight_loop(TIGHT_LOOP_N);
    check("Tight loop second run: same result",
          result2, 499500ULL);

    // Informational cycle count (not a hard check)
    uart_puts("  INFO  cycles for 1000-iter loop: ");
    uart_putu64(t1 - t0);
    uart_puts("\n");

    // Sanity: loop must not take unreasonably long
    // At 100MHz with ~2 CPI that's ~2000 cycles; allow 20x headroom
    check_bool("Tight loop cycle count < 40000",
               (t1 - t0) < 40000ULL);
}

// -------------------------------------------------------------------------
// TC_ALTERNATING_BRANCH
//
// Branch outcome alternates T/NT every iteration.
// This is the worst case for a 1-bit predictor and stresses the GShare
// history register.
//
// After N iterations (N even):
//   taken_count     = N/2
//   not_taken_count = N/2
// -------------------------------------------------------------------------

#define ALT_LOOP_N 200

__attribute__((noinline, optimize("O1")))
static void alternating_branch(int n,
                                volatile int *taken_out,
                                volatile int *not_taken_out) {
    int taken = 0, not_taken = 0;
    int parity = 0;   // 0 = not-taken path, 1 = taken path
    for (int i = 0; i < n; i++) {
        if (parity) {
            taken++;
        } else {
            not_taken++;
        }
        parity ^= 1;
    }
    *taken_out     = taken;
    *not_taken_out = not_taken;
}

void tc_alternating_branch(void) {
    test_begin("TC_ALTERNATING_BRANCH");

    volatile int taken = 0, not_taken = 0;
    alternating_branch(ALT_LOOP_N, &taken, &not_taken);

    check("Alternating N=200: taken=100",
          (uint64_t)taken,     100ULL);
    check("Alternating N=200: not_taken=100",
          (uint64_t)not_taken, 100ULL);
    check("Alternating N=200: total=200",
          (uint64_t)(taken + not_taken), (uint64_t)ALT_LOOP_N);

    // Run again with odd N to check asymmetric case
    alternating_branch(101, &taken, &not_taken);
    check("Alternating N=101: taken=50",
          (uint64_t)taken,     50ULL);
    check("Alternating N=101: not_taken=51",
          (uint64_t)not_taken, 51ULL);
}

// -------------------------------------------------------------------------
// TC_CALL_RETURN_PATTERN
//
// Stresses the Return Address Stack (RAS) and Branch Target Buffer (BTB).
//
// Three sub-tests:
//   A. Linear call chain (call f1->f2->f3->...->fN, each returns)
//      RAS must correctly predict each return address.
//
//   B. Repeated calls to the same function (BTB training for the call site)
//
//   C. Indirect call (function pointer) to stress BTB indirect prediction
// -------------------------------------------------------------------------

// --- Sub-test A: linear call chain ---
// Each function calls the next and accumulates a depth counter.
// We use 10 levels, which should stress a typical 4-8 entry RAS.

__attribute__((noinline)) static int chain10(int d);
__attribute__((noinline)) static int chain9(int d);
__attribute__((noinline)) static int chain8(int d);
__attribute__((noinline)) static int chain7(int d);
__attribute__((noinline)) static int chain6(int d);
__attribute__((noinline)) static int chain5(int d);
__attribute__((noinline)) static int chain4(int d);
__attribute__((noinline)) static int chain3(int d);
__attribute__((noinline)) static int chain2(int d);
__attribute__((noinline)) static int chain1(int d);

static int chain10(int d) { return d + 1; }
static int chain9(int d)  { return chain10(d)  + 1; }
static int chain8(int d)  { return chain9(d)   + 1; }
static int chain7(int d)  { return chain8(d)   + 1; }
static int chain6(int d)  { return chain7(d)   + 1; }
static int chain5(int d)  { return chain6(d)   + 1; }
static int chain4(int d)  { return chain5(d)   + 1; }
static int chain3(int d)  { return chain4(d)   + 1; }
static int chain2(int d)  { return chain3(d)   + 1; }
static int chain1(int d)  { return chain2(d)   + 1; }

// --- Sub-test B: repeated calls to one function ---
__attribute__((noinline))
static int64_t increment(int64_t x) { return x + 1; }

// --- Sub-test C: indirect call via function pointer ---
typedef int64_t (*int_fn_t)(int64_t);

__attribute__((noinline))
static int64_t call_indirect(int_fn_t fn, int64_t x, int n) {
    for (int i = 0; i < n; i++)
        x = fn(x);
    return x;
}

void tc_call_return_pattern(void) {
    test_begin("TC_CALL_RETURN_PATTERN");

    // Sub-test A: 10-deep call chain, RAS must unwind correctly
    check("RAS 10-deep chain from 0 = 10",
          (uint64_t)chain1(0), 10ULL);
    check("RAS 10-deep chain from 5 = 15",
          (uint64_t)chain1(5), 15ULL);

    // Call the chain multiple times so the BTB gets trained
    int64_t ras_sum = 0;
    for (int i = 0; i < 20; i++)
        ras_sum += chain1(0);
    check("RAS 10-deep x20 iterations: sum=200",
          (uint64_t)ras_sum, 200ULL);

    // Sub-test B: 500 calls to the same target (BTB training)
    int64_t val = 0;
    for (int i = 0; i < 500; i++)
        val = increment(val);
    check("BTB 500 calls to increment: val=500",
          (uint64_t)val, 500ULL);

    // Sub-test C: indirect call via function pointer (BTB indirect)
    int64_t indirect_result = call_indirect(increment, 0LL, 100);
    check("BTB indirect call x100: result=100",
          (uint64_t)indirect_result, 100ULL);

    // Mix: interleave chain calls and direct calls to stress BTB aliasing
    int64_t mix = 0;
    for (int i = 0; i < 10; i++) {
        mix += chain1(0);       // deep chain
        mix += increment(0);    // single call
    }
    // chain1(0)=10, increment(0)=1, sum per iter=11, x10 = 110
    check("BTB mixed call pattern x10: mix=110",
          (uint64_t)mix, 110ULL);
}

int main(void) {
    tc_tight_loop();
    tc_alternating_branch();
    tc_call_return_pattern();

    test_finish();
}