#include <memory>
#include <iostream>
#include <sstream>
#include <stdint.h>
#include <limits.h>
#include <stdlib.h>
#include <chrono>

#include <verilated.h>
#include "Vtop_tb.h"
#include <verilated_fst_c.h>

using namespace std;

static uint64_t clk_half_period = 0;

static inline void tick(unique_ptr<VerilatedContext> const& contextp, unique_ptr<Vtop_tb> const& top, unique_ptr<VerilatedFstC> const& tfp, bool dump_en) {
    contextp->timeInc(clk_half_period);
    top->clk = !top->clk;
    top->eval();
    if (dump_en) {
        tfp->dump(contextp->time());
    }
}

static inline void tickn(unique_ptr<VerilatedContext> const& contextp, unique_ptr<Vtop_tb> const& top, unique_ptr<VerilatedFstC> const& tfp, bool dump_en, int cycles) {
    for (int i = 0; i < cycles * 2; i++) {
        tick(contextp, top, tfp, dump_en);
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

    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);
    contextp->fatalOnError(false);

    try {
        clk_half_period = get_int_plusarg(contextp, "CLOCK_PERIOD_PS_ECE411") / 2;
    } catch (const exception& e) {
        cerr << "TB Error: Invalid command line arg" << endl;
        return 1;
    }

    const unique_ptr<Vtop_tb> top{new Vtop_tb{contextp.get(), "vtop"}};

    const unique_ptr<VerilatedFstC> tfp{new VerilatedFstC};
    tfp->dumpvars(INT_MAX, "vtop.top_tb.dut");
    top->trace(tfp.get(), INT_MAX);
    tfp->open("dump.fst");
    bool dump_all = !get_bool_plusarg(contextp, "NO_DUMP_ALL_ECE411");

    uint64_t wall_timeout_sec = get_int_plusarg(contextp, "WALL_TIMEOUT_SEC_ECE411");
    if (wall_timeout_sec == 0) wall_timeout_sec = 600; // default 10 minutes

    top->clk = 1;
    top->rst = 1;

    tickn(contextp, top, tfp, dump_all|top->dump_on, 2);

    top->rst = 0;

    auto wall_start = std::chrono::steady_clock::now();
    bool wall_timeout_hit = false;
    while (!contextp->gotFinish()) {
        tickn(contextp, top, tfp, dump_all|top->dump_on, 1);
        auto wall_now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(wall_now - wall_start).count();
        if ((uint64_t)elapsed > wall_timeout_sec) {
            cerr << "TB Error: wall-clock timeout after " << elapsed << "s (WALL_TIMEOUT_SEC_ECE411=" << wall_timeout_sec << ")" << endl;
            wall_timeout_hit = true;
            break;
        }
    }

    tfp->close();
    top->final();
    contextp->statsPrintSummary();
    return (contextp->gotError() || wall_timeout_hit) ? EXIT_FAILURE : 0;
}
