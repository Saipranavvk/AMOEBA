#include <memory>
#include <iostream>
#include <sstream>
#include <stdint.h>
#include <limits.h>
#include <stdlib.h>

#include <verilated.h>
#ifndef ECE411_NO_TRACE
#include <verilated_fst_c.h>
#endif

using namespace std;

// ECE411_NO_TRACE (defined via -CFLAGS by the build_linux target) compiles the
// FST tracer out of the harness.  Verilator's trace hooks cost roughly 50x in
// wall time and hundreds of GB of disk over a Linux boot, so the Linux tier
// cannot merely disable them at runtime -- they must not be built in.
#ifdef ECE411_NO_TRACE
#define TRACE_ARG
#define TRACE_PASS
#else
#define TRACE_ARG   unique_ptr<VerilatedFstC> const& tfp,
#define TRACE_PASS  tfp,
#endif

#include "Vtop_tb.h"

static uint64_t clk_half_period = 0;

static inline void tick(unique_ptr<VerilatedContext> const& contextp, unique_ptr<Vtop_tb> const& top, TRACE_ARG bool dump_en) {
    contextp->timeInc(clk_half_period);
    top->clk = !top->clk;
    top->eval();
#ifndef ECE411_NO_TRACE
    if (dump_en) {
        tfp->dump(contextp->time());
    }
#else
    (void)dump_en;
#endif
}

static inline void tickn(unique_ptr<VerilatedContext> const& contextp, unique_ptr<Vtop_tb> const& top, TRACE_ARG bool dump_en, int cycles) {
    for (int i = 0; i < cycles * 2; i++) {
        tick(contextp, top, TRACE_PASS dump_en);
    }
}

static inline bool get_bool_plusarg(unique_ptr<VerilatedContext> const& contextp, string arg) {
    string s(contextp->commandArgsPlusMatch(arg.c_str()));
    return s.length() != 0;
}

static inline uint64_t get_int_plusarg(unique_ptr<VerilatedContext> const& contextp, string arg) {
    string s(contextp->commandArgsPlusMatch(arg.c_str()));
    replace(s.begin(), s.end(), '=', ' ');
    stringstream ss(s);
    string p;
    uint64_t retval;
    ss >> p;
    ss >> retval;
    return retval;
}

int main(int argc, char** argv, char** env) {
    const unique_ptr<VerilatedContext> contextp{new VerilatedContext};

#ifndef ECE411_NO_TRACE
    contextp->traceEverOn(true);
#endif
    contextp->commandArgs(argc, argv);
    contextp->fatalOnError(false);

    try {
        clk_half_period = get_int_plusarg(contextp, "CLOCK_PERIOD_PS_ECE411") / 2;
    } catch (const exception& e) {
        cerr << "TB Error: Invalid command line arg" << endl;
        return 1;
    }

    const unique_ptr<Vtop_tb> top{new Vtop_tb{contextp.get(), "vtop"}};

#ifndef ECE411_NO_TRACE
    const unique_ptr<VerilatedFstC> tfp{new VerilatedFstC};
    tfp->dumpvars(INT_MAX, "vtop.top_tb.dut");
    top->trace(tfp.get(), INT_MAX);
    tfp->open("dump.fst");
    bool dump_all = !get_bool_plusarg(contextp, "NO_DUMP_ALL_ECE411");
#else
    bool dump_all = false;
#endif

    top->clk = 1;
    top->rst = 1;

    tickn(contextp, top, TRACE_PASS dump_all|top->dump_on, 2);

    top->rst = 0;

    while (!contextp->gotFinish()) {
        tickn(contextp, top, TRACE_PASS dump_all|top->dump_on, 1);
    }

#ifndef ECE411_NO_TRACE
    tfp->close();
#endif
    top->final();
    contextp->statsPrintSummary();
    return contextp->gotError() ? EXIT_FAILURE : 0;
}
