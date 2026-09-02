# FORTE / AMOEBA

**ECE 427 Tapeout – Secure Linux-Capable Processor**

The DUT is an OpenHW CVW `wallypipelinedsoc` core (RV64GC + scalar crypto) wrapped in `hdl/rv64_core_wrapper.sv`. Every retired instruction is co-simulated against Spike (the official RISC-V ISA reference) and formally checked by the riscv-formal RVFI monitor — two independent checkers, one per committed instruction.

---

## Table of Contents

1. [Repository Layout](#repository-layout)
2. [Prerequisites & Installation](#prerequisites--installation)
3. [Quick Start](#quick-start)
4. [Compiling Test Programs](#compiling-test-programs)
5. [Simulation](#simulation)
6. [FreeRTOS Tests](#freertos-tests)
7. [Makefile Reference](#makefile-reference)
8. [Verification Architecture](#verification-architecture)
9. [Hardware Configuration](#hardware-configuration)
10. [Test Programs](#test-programs)
11. [Linux-Bootability & Scope](#linux-bootability--scope)
12. [CI/CD](#cicd)
13. [Toolchain Requirements](#toolchain-requirements)

---

## Repository Layout

```
hdl/                  RTL sources
  rv64_core_wrapper.sv    Top-level wrapper; taps pipeline signals for RVFI
  ahb_to_memitf.sv        AHB-Lite → testbench memory interface bridge
  core/                   Working copy of CVW RTL (created by make generate-rtl)
  cvw/                    Pristine CVW copy (refreshed from third_party; never edit)
hvl/                  Testbench sources
  common/               Shared verification IP
    top_tb.svh            Main testbench body (included by both Verilator and VCS)
    spike_dpi.cpp         Spike ISA reference DPI bridge
    spike.so              Compiled DPI library (auto-built before first Verilator compile)
    rvfimon.v             RVFI formal monitor (auto-generated; committed)
    rvfi_reference.svh    RVFI signal wiring (auto-generated at build time)
    monitor.sv            Halt detection + IPC counter
    masked_memory.sv      Behavioral byte-masked SRAM (3-cycle delay)
    mem_itf.sv / mon_itf.sv  SystemVerilog interfaces
  verilator/            Verilator-specific harness (verilator_harness.cpp, top_tb.sv)
  vcs/                  VCS-specific harness
pkg/                  Shared SystemVerilog packages and includes
sim/                  Simulation Makefile + build artifacts
  Makefile              All sim targets (Verilator, VCS, Spike, regression)
  verilator/            Verilator build directory (Vtop_tb binary, dump.fst)
  vcs/                  VCS build directory (top_tb binary, dump.fsdb)
  spike/                Spike co-sim output logs
synth/                Synthesis (Synopsys Design Compiler, EWS-only)
  Makefile              synth, power_verilator, power_vcs, dv targets
  synthesis.tcl / power.tcl / dv.tcl
  reports/              Synthesis, power, area reports
  outputs/              synth.ddc gate-level netlist
lint/                 Lint (Synopsys Spyglass, EWS-only)
  Makefile              lint target
  lint.tcl
  reports/              lint.rpt
bin/                  Build helper scripts
  startup.s             Bare-metal CRT (initializes x1–x31, jumps to main)
  link.ld               Linker script (entry at 0x80000000, stack at 0x8ff00000)
  generate_rtl.sh       Refreshes hdl/cvw/ and creates hdl/core/ from CVW submodule
  generate_memory_file.py  ELF → byte-addressed .lst memory image
  rvfi_reference.py     Generates hvl/common/rvfi_reference.svh from JSON config
  get_options.py        Reads options.json fields for Makefile use
testcode/             C test programs
  baremetal/            Bare-metal tests (basic_arith.c, sorting_algo.c, exit_test.c)
  freertos/             FreeRTOS tests and build infrastructure
third_party/          Git submodules
  cvw/                  OpenHW CORE-V Wally processor (source of hdl/cvw + hdl/core)
  riscv-formal/         riscv-formal RVFI monitor generator
  FreeRTOS-Kernel/      FreeRTOS kernel (used by testcode/freertos/)
sram/                 SRAM compiler outputs (config/, output/*.v *.db, sram.py)
options.json          Project configuration (clock, ISA switches, synthesis settings)
```

---

## Prerequisites & Installation

### 1. System Packages

Install the required tools for your distribution. The only mandatory tools for local Verilator simulation are: `verilator`, `g++`, `riscv64-*-elf-gcc`, `python3`, and `gtkwave`.

**Arch Linux**
```bash
sudo pacman -S verilator gcc python python-pip gtkwave git base-devel
sudo pacman -S riscv64-elf-gcc dtc boost   # cross-compiler + Spike build deps
```

**Ubuntu / Debian**
```bash
sudo apt update
sudo apt install verilator g++ python3 gtkwave git make
sudo apt install gcc-riscv64-unknown-elf         # cross-compiler
sudo apt install device-tree-compiler libboost-all-dev build-essential  # Spike build deps
```

**Fedora**
```bash
sudo dnf install verilator gcc-c++ python3 gtkwave git make
sudo dnf install gcc-riscv64-linux-gnu           # cross-compiler (or build from source)
sudo dnf install dtc boost-devel                 # Spike build deps
```

> **EWS-only tools** (VCS, Verdi, Design Compiler `dc_shell`, Spyglass `sg_shell`) are license-gated and only available on ECE EWS machines. Verilator covers all local development.

---

### 2. Build Spike from Source (required once)

Distribution packages for Spike **do not** include `--enable-commitlog` support, which is required for co-simulation. Build from source:

```bash
mkdir -p /tmp/spike-build && cd /tmp/spike-build
git clone --depth=1 https://github.com/riscv-software-src/riscv-isa-sim.git
cd riscv-isa-sim && mkdir build && cd build
../configure --prefix=$HOME/.local --enable-commitlog
make -j$(nproc)
```

The DPI bridge auto-detects the binary at `/tmp/spike-build/riscv-isa-sim/build/spike`. No install step is needed.

---

### 3. Clone and Initialize Submodules

After cloning the repo, initialize the `third_party/` submodules:

```bash
git submodule update --init --recursive
```

This clones:
- `third_party/cvw` — OpenHW CORE-V Wally processor RTL
- `third_party/riscv-formal` — RVFI monitor generator
- `third_party/FreeRTOS-Kernel` — FreeRTOS kernel (used by `testcode/freertos/`)

---

### 4. Generate RTL

Populate `hdl/cvw/` (pristine CVW copy) and `hdl/core/` (working copy you can patch):

```bash
cd sim
make generate-rtl
```

Or directly:
```bash
bash bin/generate_rtl.sh
```

- **Stage 1** — refreshes `hdl/cvw/` verbatim from `third_party/cvw/src/`. Never edit this directory.
- **Stage 2** — creates `hdl/core/` from `hdl/cvw/` on first run only; subsequent runs skip it to preserve AMOEBA-specific patches. Pass `--reset` to wipe and recreate.

`hdl/core/` must exist before any compile target will succeed.

---

## Quick Start

After completing the four installation steps above:

```bash
cd sim

# Build the Verilator binary (one time, ~5 min)
make verilator/build/Vtop_tb

# Run the arithmetic smoke test
make run_verilator_top_tb PROG=../testcode/baremetal/basic_arith.elf

# Run all tests as a regression
make regression
```

Outputs:
- `sim/verilator/<testname>/simulation.log` — full instruction commit log
- `sim/verilator/dump.fst` — FST waveform (view with `gtkwave`)

```bash
gtkwave sim/verilator/dump.fst &
```

---

## Compiling Test Programs

Pre-built ELFs are checked in under `testcode/baremetal/`. Recompile if you modify a test.

The RISC-V bare-metal cross-compiler binary name varies by distribution:

| Distribution | Binary name |
|---|---|
| Arch Linux | `riscv64-elf-gcc` |
| Ubuntu / Debian | `riscv64-unknown-elf-gcc` |
| Fedora | `riscv64-linux-gnu-gcc` (or toolchain from source) |

**Bare-metal compile command:**
```bash
riscv64-elf-gcc -march=rv64gc -mabi=lp64d -O2 -nostdlib \
    -T bin/link.ld bin/startup.s testcode/baremetal/mytest.c \
    -o testcode/baremetal/mytest.elf
```

Test programs must terminate with the halt instruction `slti x0, x0, -256` (encoding `0xF0002013`). The testbench detects this and ends simulation cleanly. See `testcode/baremetal/basic_arith.c` for a minimal example.

---

## Simulation

All simulation targets are driven from `sim/Makefile`. Run them from the `sim/` directory.

### Verilator (Recommended for Local Dev)

```bash
cd sim

# Compile (incremental; also builds spike.so if missing)
make verilator/build/Vtop_tb

# Run a single test
make run_verilator_top_tb PROG=../testcode/baremetal/sorting_algo.elf

# Override the cycle timeout (default: 10,000,000 cycles)
make run_verilator_top_tb PROG=../testcode/baremetal/sorting_algo.elf TIMEOUT=20000000

# Run all .c files in testcode/baremetal/ as a regression suite
make regression
```

Outputs per run:
- `sim/verilator/<testname>/simulation.log` — instruction trace + pass/fail
- `sim/verilator/<testname>/dump.fst` — FST waveform copy

---

### VCS + Verdi (EWS / License-Gated)

```bash
cd sim
make vcs/top_tb
make run_vcs_top_tb PROG=../testcode/baremetal/basic_arith.elf
make verdi &           # opens Verdi on the last FSDB dump
make covrep            # generate coverage report from top_tb.vdb
```

Output: `sim/vcs/simulation.log`, `sim/vcs/dump.fsdb`

---

### Spike ISA Reference

Run Spike standalone to generate a golden commit log, or debug interactively:

```bash
cd sim
make spike ELF=../testcode/baremetal/basic_arith.elf       # → spike/spike.log
make interactive_spike ELF=../testcode/baremetal/basic_arith.elf  # interactive -d debugger
```

---

### Simulation Plusargs Reference

These are passed automatically by the Makefile, but can be set manually when running the binary directly:

| Plusarg | Default | Description |
|---|---|---|
| `+TIMEOUT_ECE411` | `10000000` | Cycle count before simulation abort |
| `+WALL_TIMEOUT_SEC_ECE411` | `600` | Wall-clock seconds before abort (Verilator only) |
| `+CLOCK_PERIOD_PS_ECE411` | from `options.json` | Clock period in picoseconds |
| `+BRAM_0_ON_X_ECE411` | from `options.json` | Whether undefined BRAM bits read as 0 |
| `+MEMLST_ECE411` | `sim/bin/memory_8.lst` | Path to byte-addressed memory image |
| `+ELF_ECE411` | `sim/bin/spike_dpi.elf` | Path to ELF (used by Spike DPI subprocess) |

---

## FreeRTOS Tests

FreeRTOS tests compile the kernel + a userland workload and run in the no-spike Verilator binary (Spike DPI co-simulation is disabled — CLINT interrupt-driven scheduling is not modeled by Spike in commit-log mode). Correctness is checked via FreeRTOS task assertions that write to the HTif `tohost` address; the testbench treats any non-zero `tohost` value as a test failure.

### Prerequisites

The FreeRTOS kernel is included as a submodule at `third_party/FreeRTOS-Kernel`. Initialize it with:

```bash
git submodule update --init third_party/FreeRTOS-Kernel
```

(Or initialize all submodules at once: `git submodule update --init --recursive`)

### Build and Run

```bash
cd sim

# Build the no-spike Verilator binary (shared with ISA-level tests)
make build_isa_tests

# Run the default sorting workload (sorting_algo_app.c)
make freertos

# Run all tc_*.c FreeRTOS test programs
make freertos_regression

# Same tests against the pruned FreeRTOS-only hardware config
# (pkg/config_freertos.vh -- see Pruned Configurations)
make freertos_regression CONFIG=freertos

# Run a single tc_*.c test (e.g., tc_task_queue):
make -C ../testcode/freertos build PROG=tc_task_queue.c
make run_verilator_top_tb_no_spike PROG=../testcode/freertos/freertos_wally.elf
```

To run a custom workload, define `int app_main(void)` in your source file and pass it:
```bash
cd testcode/freertos
make build PROG=/absolute/path/to/my_app.c
cd ../../sim
make run_verilator_top_tb_no_spike PROG=../testcode/freertos/freertos_wally.elf
```

### Writing FreeRTOS Tests

Each FreeRTOS test implements `int app_main(void)`:

```c
#include "FreeRTOS.h"
#include "task.h"
#include "test_utils_freertos.h"

int app_main(void) {
    // For simple tests: do work, check result, return exit code
    check(2 + 2 == 4, 1);  // exits with code 1 if false
    return 0;               // 0 = pass

    // For task-based tests: create tasks, suspend self
    // Tasks call tohost_exit(0) on success or check(cond, code) on failure
}
```

The `check(cond, code)` macro and the `tohost_exit()` declaration are in `testcode/freertos/test_utils_freertos.h`. The actual `tohost_exit()` implementation (with the `cbo.flush` required for CVW's write-back D-cache) is in `syscalls_amoeba.c`.

Exit code conventions used by the harness:

| Code | Meaning |
|---|---|
| 0 | Test passed |
| 1–N | Test-defined failure (check which assertion failed) |
| 2 | Heap exhausted (`vApplicationMallocFailedHook`) |
| 3 | Stack overflow (`vApplicationStackOverflowHook`) |
| 4 | Root task creation failed |

Outputs: `sim/verilator/freertos_wally/simulation.log`, `sim/verilator/dump.fst`

---

## Makefile Reference

### `sim/` Targets

**Build targets**

| Target | Simulator binary | Description |
|---|---|---|
| `build` | `verilator/build/Vtop_tb` | Spike DPI simulator (baremetal co-simulation) |
| `build_isa_tests` | `verilator/build_no_spike/Vtop_tb` | No-Spike simulator (ISA-level + FreeRTOS tests) |
| `build_freertos` | `verilator/build_no_spike/Vtop_tb` | Alias for `build_isa_tests` |

**Run targets**

| Target | Description |
|---|---|
| `run_verilator_top_tb` | Run baremetal simulation (`PROG=` required — `.c` or `.elf`) |
| `run_verilator_top_tb_no_spike` | Run ISA/FreeRTOS simulation (`PROG=` required) |
| `run_isa_level` | Alias for `run_verilator_top_tb_no_spike` |
| `run_verilator_top_tb_freertos` | Alias for `run_verilator_top_tb_no_spike` |
| `freertos` | Build + run default FreeRTOS workload (`sorting_algo_app.c`) |
| `run_vcs_top_tb` | Run VCS simulation (`PROG=` required) |

**Regression targets**

| Target | Description |
|---|---|
| `baremetal_regression` | All `testcode/baremetal/*.c` with Spike DPI co-simulation |
| `isa_regression` | All `testcode/isa_level_testing/*.c` without co-sim |
| `freertos_regression` | All `testcode/freertos/tc_*.c` without co-sim |
| `regression` | Runs all three tiers in order |

**Utility targets**

| Target | Description |
|---|---|
| `vcs/top_tb` | Compile VCS binary |
| `spike` | Run Spike ISA sim, dump commit log (`ELF=` required) |
| `interactive_spike` | Run Spike interactive debugger (`ELF=` required) |
| `generate-rtl` | Run `bin/generate_rtl.sh` (refreshes hdl/cvw/ and creates hdl/core/) |
| `generated-files` | Regenerate `hvl/common/rvfimon.v` and `hvl/common/rvfi_reference.svh` |
| `check-generated` | Verify generated files match current scripts (CI gate) |
| `verdi` | Open Verdi on last VCS waveform dump |
| `covrep` | Generate coverage report from `vcs/top_tb.vdb` |
| `clean` | Remove all build artifacts (`bin/`, `vcs/`, `verdi/`, `verilator/`, `spike/`) |

---

### `synth/` Targets (EWS / License-Gated)

Run from the `synth/` directory. Requires Synopsys Design Compiler (`dc_shell`) and `FREEPDK45` standard cell library.

| Target | Description |
|---|---|
| `synth` | Full synthesis via DC (`outputs/synth.ddc`, `reports/synthesis.log`) |
| `power_verilator` | Power analysis using Verilator SAIF (`reports/power.log`) — needs a prior Verilator run |
| `power_vcs` | Power analysis using VCS FSDB (`reports/power.log`) — needs a prior VCS run |
| `dv` | Open Design Vision GUI on the synthesized netlist |
| `clean` | Remove synthesis artifacts |

Power analysis extracts switching activity from the ROI window (`slti x0, x0, 1` → `slti x0, x0, 2`) and annotates the gate-level netlist for power estimation.

---

### `lint/` Targets (EWS / License-Gated)

Run from the `lint/` directory. Requires Synopsys Spyglass (`sg_shell`).

| Target | Description |
|---|---|
| `lint` | Run Spyglass lint checks (`reports/lint.rpt`) |
| `clean` | Remove lint artifacts |

---

## Verification Architecture

### Three-Tier Test Architecture

| Tier | Build target | Spike DPI | Correctness checks | Pass/fail mechanism |
|---|---|---|---|---|
| **Baremetal** | `make build` | ✓ lock-step | Spike field-by-field + RVFI formal | `tohost` write |
| **ISA-level** | `make build_isa_tests` | ✗ | RVFI formal + `test_utils.h` assertions | `tohost` write |
| **FreeRTOS** | `make build_isa_tests` | ✗ | RVFI formal + task assertions | `tohost` write |

ISA-level and FreeRTOS tests share one compiled binary (`ECE411_NO_SPIKE_DPI`). Baremetal tests use a separate binary with full Spike DPI co-simulation.

MMIO accesses (UART at `0x10000000`, CLINT at `0x02000000`) are not logged by Spike's `--log-commits` output, so any test that uses UART or CLINT interrupts would cause spurious Spike divergences. Baremetal tests are therefore pure arithmetic/memory code; OS and peripheral tests use the no-spike tiers.

Two independent checkers validate every retired instruction simultaneously:

### Spike DPI Co-Simulation

`hvl/common/spike_dpi.cpp` launches Spike as a subprocess (`--log-commits`) and compares each instruction's register writes, PC update, and memory transaction against the DUT's RVFI output. A mismatch stops simulation immediately with a field-by-field diff:

```
-------begin spike mismatch--------
signal     diff       dut     spike
inst            h00004782 h00004782
rd_addr    --->        14        15
rd_wdata        h00000000 h00004782
mem_rmask             0x00      0x00
...
-------end spike mismatch----------
```

`spike.so` is automatically compiled from `spike_dpi.cpp` before the first Verilator build. It has no external library dependencies and rebuilds on any machine with `g++`.

---

### RVFI Formal Monitor

`hvl/common/rvfimon.v` is a formal shadow-register checker generated from the riscv-formal submodule. It maintains a shadow integer register file and validates every write on retirement. It calls `$error` on field mismatches and `$fatal` on a halt.

The field mapping from monitor inputs to `dut.monitor_*` signals is in `hvl/common/rvfi_reference.json`. `bin/rvfi_reference.py` auto-generates `hvl/common/rvfi_reference.svh` from it at build time.

---

### Regenerating Generated Files

Both `rvfimon.v` and `rvfi_reference.svh` are auto-generated and committed. Regenerate them after any ISA change or riscv-formal submodule update:

```bash
cd sim
make generated-files
```

To verify that committed files are up to date (this is also the CI gate):
```bash
make check-generated
```

Individual commands:
```bash
# Regenerate rvfimon.v (rv64imac + atomics, 1 channel, 0 shadow read ports)
cd third_party/riscv-formal/insns && python3 gen_amo.py
cd ../monitor && python3 generate.py -i rv64imac -a -r 0 -c 1 > ../../../hvl/common/rvfimon.v

# Regenerate rvfi_reference.svh
python3 bin/rvfi_reference.py 1
```

---

### IPC Measurement & Waveform ROI

The testbench marks a measurement window using two special instructions:

| Instruction | Encoding | Meaning |
|---|---|---|
| `slti x0, x0, 1` | `0x0010_2013` | ROI start (IPC timer begins) |
| `slti x0, x0, 2` | `0x0020_2013` | ROI end (IPC timer stops, IPC printed) |
| `slti x0, x0, -256` | `0xF000_2013` | Halt (simulation ends) |

Insert these markers in your C code with:
```c
asm volatile ("slti x0, x0, 1");   // start
// ... workload ...
asm volatile ("slti x0, x0, 2");   // end
```

`hvl/common/monitor.sv` prints the IPC to the simulation log on halt. The same ROI window is used by `synth/Makefile` to extract switching activity for power analysis (`time.txt` records the start/end timestamps).

---

## Hardware Configuration

### `options.json`

The top-level configuration file read by `bin/get_options.py`:

```json
{
  "clock": 10000,          // Clock period in ps (10 ns = 100 MHz)
  "c_ext": true,           // Compressed (C) extension
  "f_ext": true,           // Single-precision FP (F/D)
  "zicsr": true,           // CSR access instructions
  "zifencei": true,        // fence.i instruction
  "bmem_0_on_X": false,    // Behavioral SRAM: drive 0 on undefined (vs. X)
  "dw_ip": [],             // Synopsys DesignWare IP file list (empty = unused)
  "synth": {
    "compile_ultra": true, // Use compile_ultra (vs. compile)
    "ungroup": true,       // Flatten hierarchy before synthesis
    "gate_clock": true,    // Enable clock gating
    "retime": false,       // Pipeline retiming
    "min_power": false,    // Power-driven synthesis
    "inc_iter": 0          // Incremental compile iterations
  }
}
```

### CVW Core Configuration (`hdl/cvw_config/config.vh`)

Notable settings (see the file for the full parameter list):

| Parameter | Value | Description |
|---|---|---|
| `XLEN` | 64 | 64-bit ISA |
| Reset vector | `0x80000000` | Entry point |
| Extensions | RV64IMAFDCBK + Zicsr/Zifencei/Zicond + ZFH/ZFA + Zkn | Full ISA |
| Privilege | M + S + U | Supervisor and user modes |
| MMU | Sv39/Sv48/Sv57 | Virtual memory with SVPBMT, SVINVAL, SVADU |
| I/D TLBs | 32 entries | Per-cache TLBs |
| PMP | 16 entries | Physical memory protection |
| I-cache | 4-way, 4 KiB/way, 512-bit lines | |
| D-cache | 4-way, 4 KiB/way, 512-bit lines | |
| Branch predictor | GShare, 10-bit index, 6-bit LHR, 16-entry RAS | |
| Integer divider | 4 bits/cycle | Multi-cycle, stalls E-stage |

### Pruned Configurations

`pkg/config.vh` is the full RV64GC parameter set and the default for every
tier. Three pruned alternates live beside it, selected by `CONFIG=` on the sim
and synth Makefiles:

| `CONFIG=` | File | For |
|---|---|---|
| *(unset)* | `pkg/config.vh` | baremetal, ISA, Linux, Keystone-Linux |
| `freertos` | `pkg/config_freertos.vh` | only what `testcode/freertos` executes |
| `freertos_keystone` | `pkg/config_freertos_keystone.vh` | that, plus the Keystone SM and OpenSBI |
| `baremetal_linux` | `pkg/config_baremetal_linux.vh` | smallest core that boots a soft-float Linux |

```bash
make -C sim freertos_regression CONFIG=freertos    # 5/5 pass
make -C sim linux_boot          CONFIG=baremetal_linux
make -C synth synth CONFIG=freertos_keystone       # area estimate
```

Each file carries per-parameter notes on why a feature stayed or went. The
headline deltas against `pkg/config.vh`:

| | `freertos` | `freertos_keystone` | `baremetal_linux` |
|---|---|---|---|
| ISA | RV64IM + Zaamo + Zca + Zicsr + Zicbom | + Zalrsc, Zifencei | RV64IMAC + Zicsr + Zifencei |
| Privilege | M only | M + S + U | M + S + U |
| MMU | none | Sv39 + Svadu | Sv39, software A/D |
| PMP | 0 entries | 16 entries | 0 entries |
| FPU | removed | removed | removed (SoftFloat) |
| B / Zkn / Zcb / Zicond | removed | removed | removed |
| Counters | none | none | none |
| Zicbom / Zicboz | Zicbom only | Zicbom only | none |
| I/D cache | 4-way, 4 KiB/way | 4-way, 4 KiB/way | **1-way, 512 B/way** |
| I/D TLB | n/a | 32 entries | 8 entries |
| Branch predictor | off | off | off |
| Peripherals | CLINT + UART | CLINT + UART | CLINT + UART |

All three drop the FPU, so they compile with `ECE411_NO_FLOAT` — the Makefiles
add it automatically.

Two of the three are **untested against a real image**, and both are sized from
the sources of the stack they are meant to carry rather than measured:

- `pkg/config_freertos_keystone.vh` — no Keystone-FreeRTOS image exists yet.
- `pkg/config_baremetal_linux.vh` — `testcode/linux` currently builds a
  hard-float kernel (`CONFIG_FPU=y`) against a device tree advertising `f`/`d`,
  so the existing `boot.lst` will **not** run on it. Its header lists the exact
  kernel-config, ABI and device-tree deltas a soft-float image needs.

Both also set `PLIC_SUPPORTED = 0`, which constrains the device tree — see
their headers before building an image.

### Memory Map

| Address range | Peripheral |
|---|---|
| `0x80000000–0x8FFFFFFF` | External RAM (256 MB, AHB-Lite) |
| `0x02000000` | CLINT (core-local interrupt controller) |
| `0x0C000000` | PLIC (platform-level interrupt controller) |
| `0x10000000` | UART |
| `0x10040000` | SPI |
| `0x10060000` | GPIO |

---

## Test Programs

| File | RVFI commits | Description | Verilator runtime |
|---|---|---|---|
| `testcode/baremetal/basic_arith.elf` | 219 | Arithmetic smoke test | < 1 s |
| `testcode/baremetal/sorting_algo.elf` | 95,593 | Iterative quicksort, N=1000 | ~31 min |
| `testcode/baremetal/exit_test.elf` | minimal | Exit-code validation | < 1 s |

Programs terminate with `slti x0, x0, -256` (encoding `0xF0002013`), which the testbench detects as the halt instruction.

---

## Linux-Bootability & Scope

CVW's hardware is fully Linux-capable: S/U privilege modes, Sv39/48/57 MMU, CLINT, PLIC, UART, and PMP are all enabled and configured. The **current test programs** exercise only M-mode bare-metal arithmetic and do not exercise privilege transitions, page tables, or interrupts.

**What is verified:**
- Instruction-level correctness vs. Spike for every retired instruction (RV64GC + crypto)
- Integer and FP register file state via RVFI shadow checker (RV64IMAC)
- Memory read/write correctness including byte-enable masks
- Exception and trap routing (on executed paths)

**What is not yet exercised:**
- Supervisor/user privilege transitions
- Page table walks (Sv39/Sv48/Sv57)
- External interrupts (PLIC, CLINT timer)
- Linux kernel boot (requires tens of billions of cycles — not practical in RTL simulation)

The Spike DPI flow proves RTL ≡ Spike instruction-for-instruction on every executed code path. Since Spike can boot Linux, a DUT that matches Spike on a complete Linux boot trace would be validated Linux-bootable. FPGA prototyping is the standard next step for full OS validation.

---

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`) runs a three-tier matrix pipeline on every push/PR:

| Job | Depends on | What it does |
|---|---|---|
| `ci-build-spike` | — | Compiles `verilator/build/Vtop_tb` (Spike DPI); checks generated files |
| `ci-build-no-spike` | — | Compiles `verilator/build_no_spike/Vtop_tb` (ISA + FreeRTOS) |
| `ci-build-spike-exe` | — | Builds Spike v1.1.0 from source; cached across runs |
| `ci-discover-tests` | — | Discovers `testcode/baremetal/*.c` → matrix |
| `ci-discover-isa-tests` | — | Discovers `testcode/isa_level_testing/*.c` → matrix |
| `ci-discover-freertos-tests` | — | Discovers `testcode/freertos/tc_*.c` → matrix |
| `ci-baremetal` (matrix) | build-spike, build-spike-exe | Runs each baremetal test with Spike DPI co-sim |
| `ci-isa-level` (matrix) | build-no-spike | Runs each ISA-level test; exit via `tohost` |
| `ci-freertos` (matrix) | build-no-spike, ci-baremetal, ci-isa-level | Builds each `tc_*.c` ELF; runs; exit via `tohost` |

Each FreeRTOS and ISA test appears as an independent check in the PR status panel. Pass/fail is determined entirely by the `tohost` exit code — no UART output scraping.

**If CI fails on `check-generated`:** run `make generated-files` locally and commit `hvl/common/rvfimon.v` and `hvl/common/rvfi_reference.svh`.

**If CI fails on compilation:** check `sim/verilator/build/compile.log` (Spike DPI) or `sim/verilator/build_no_spike/compile.log` (no-spike).

**If a baremetal CI job fails:** check `sim/verilator/<testname>/simulation.log` for the Spike mismatch diff or RVFI `$error`.

**If a FreeRTOS CI job fails:** the exit code in the simulation log indicates which `check()` assertion failed.

---

## Toolchain Requirements

| Tool | Version | Purpose |
|---|---|---|
| `verilator` | ≥ 5.000 | RTL simulation (primary local tool) |
| `g++` | ≥ 11 | Compiles `spike.so` DPI bridge and Verilator C++ harness |
| `spike` (source build) | main branch | ISA reference co-simulation (`--enable-commitlog` required) |
| `riscv64-*-elf-gcc` | any recent | Bare-metal cross-compiler for test ELFs |
| `python3` | ≥ 3.8 | Build helper scripts (`get_options.py`, `rvfi_reference.py`, `generate_memory_file.py`) |
| `gtkwave` | any | FST waveform viewer (Verilator) |
| `vcs` / `verdi` | — | EWS-only: commercial simulation + waveform viewer |
| `dc_shell` | — | EWS-only: Synopsys Design Compiler (synthesis + power) |
| `sg_shell` | — | EWS-only: Synopsys Spyglass (lint) |
| `fsdb2saif` / `vcd2saif` | — | EWS-only: FSDB/VCD → SAIF conversion for power analysis |
