# AMOEBA Verification Tooling Guide

This document covers every tool used in the AMOEBA RV64GC verification flow: what each tool does, how to install it on major Linux distributions, and how the pieces connect.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [RISC-V Cross-Compiler](#risc-v-cross-compiler)
3. [Spike ISA Simulator](#spike-isa-simulator)
4. [Verilator](#verilator)
5. [VCS (EWS only)](#vcs-ews-only)
6. [riscv-formal Submodule](#riscv-formal-submodule)
7. [Spike DPI Co-Simulation](#spike-dpi-co-simulation)
8. [Python Utilities](#python-utilities)
9. [Running Tests](#running-tests)
10. [Adding New Test Programs](#adding-new-test-programs)
11. [Configuration Reference](#configuration-reference)
12. [Scope and Limitations](#scope-and-limitations)

---

## Architecture Overview

```
testcode/*.c
    │
    ▼  riscv64-*-elf-gcc (cross-compile, bare-metal)
testcode/*.elf
    │
    ├──▶ Spike (reference ISA model, --log-commits)
    │         │
    │         ▼ per-instruction commit log
    │   spike_dpi.cpp ──────────────────────────────┐
    │   (popen subprocess, shadow regfile)           │
    │                                                ▼
    └──▶ Verilator / VCS (RTL sim of CVW SoC) → spike_dpi_next() DPI
              │                                      │
              ▼                                      ▼
         monitor.sv ──────── rvfimon.v (riscv-formal)
         (Spike co-sim)      (formal register shadow checker)
```

On every retired instruction the DUT's RVFI output is compared against Spike's reference model. A mismatch stops simulation immediately with a field-by-field diff.

---

## RISC-V Cross-Compiler

A bare-metal RISC-V cross-compiler is needed to compile `testcode/*.c`. The binary name varies by distribution; the key requirement is that the toolchain targets a bare-metal ABI (`*-elf`, not `*-linux-gnu`).

Pre-built ELFs are committed under `testcode/` so you only need the compiler if you are adding new tests.

### Package manager install

**Arch Linux**
```bash
sudo pacman -S riscv64-elf-gcc
# binary: riscv64-elf-gcc
```

**Ubuntu / Debian**
```bash
sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
# binary: riscv64-unknown-elf-gcc
```

**Fedora / RHEL**
```bash
sudo dnf install gcc-riscv64-linux-gnu        # not bare-metal; see note below
```
Fedora's packaged cross-compiler targets Linux ABI. For bare-metal use, build the toolchain from source (see below) or use SiFive's prebuilts.

### Build from source (any distro)

```bash
# Prerequisites
# Ubuntu/Debian: sudo apt install autoconf automake autotools-dev curl python3 libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev
# Arch:          sudo pacman -S autoconf automake curl python3 libmpc mpfr gmp gawk base-devel bison flex texinfo gperf libtool patchutils bc zlib expat
# Fedora:        sudo dnf install autoconf automake curl python3 libmpc-devel mpfr-devel gmp-devel gawk gcc bison flex texinfo gperf libtool patchutils bc zlib-devel expat-devel

git clone https://github.com/riscv-collab/riscv-gnu-toolchain.git
cd riscv-gnu-toolchain
./configure --prefix=$HOME/.local --with-arch=rv64gc --with-abi=lp64d
make -j$(nproc)
# binary: $HOME/.local/bin/riscv64-unknown-elf-gcc
```

### Compiling a test program

Replace `riscv64-elf-gcc` with whatever binary name your distro provides.

```bash
riscv64-elf-gcc -march=rv64gc -mabi=lp64d -O2 -nostdlib \
    -T bin/link.ld bin/startup.s testcode/mytest.c \
    -o testcode/mytest.elf
```

Key flags:
- `-march=rv64gc` — enable I/M/A/F/D/C extensions (matches CVW config)
- `-mabi=lp64d` — 64-bit LP ABI with hardware FP registers
- `-nostdlib` — no libc; `bin/startup.s` provides the CRT
- `-T bin/link.ld` — places `.text` at `0x80000000` (CVW reset vector)

`bin/startup.s` zeros all integer registers, sets up a 16 MB stack at `0x8FF00000`, writes `mtvec`/`mie`, then calls `main`. Programs halt by executing `slti x0, x0, -256` (`0xF0002013`).

---

## Spike ISA Simulator

Spike is the official RISC-V ISA reference simulator. The co-simulation flow uses `spike --log-commits` to produce a per-instruction retirement log that is compared against the DUT in real time.

### Why build from source

Distribution packages for Spike are commonly built **without** `--enable-commitlog`. Running `spike --log-commits` on a package-built binary prints an error and exits. You must build Spike from source.

> If you have a system Spike installed, remove it before installing your source build to avoid confusion:
>
> - Arch: `sudo pacman -Rns spike`
> - Ubuntu/Debian: `sudo apt remove spike`
> - Fedora: `sudo dnf remove spike`

### Build dependencies

**Ubuntu / Debian**
```bash
sudo apt install device-tree-compiler libboost-all-dev build-essential git
```

**Arch Linux**
```bash
sudo pacman -S dtc boost base-devel git
```

**Fedora / RHEL**
```bash
sudo dnf install dtc boost-devel gcc-c++ make git
```

### Build Spike

Use the `main` branch. The `v1.1.0` release tag has a C++17 compatibility issue with GCC ≥ 15 that prevents compilation.

```bash
mkdir -p /tmp/spike-build && cd /tmp/spike-build
git clone --depth=1 https://github.com/riscv-software-src/riscv-isa-sim.git
cd riscv-isa-sim
mkdir build && cd build
../configure --prefix=$HOME/.local --enable-commitlog
make -j$(nproc)
# Binary: /tmp/spike-build/riscv-isa-sim/build/spike
# Optional install (adds to PATH):
make install
```

The DPI layer (`hvl/common/spike_dpi.cpp`) auto-detects the binary in order:
1. `/tmp/spike-build/riscv-isa-sim/build/spike` (the build location above)
2. `spike` in `PATH` (for custom installs)

If you place Spike somewhere else, update the `local` path in `hvl/common/spike_dpi.cpp:57`.

### Running Spike manually

```bash
# Print commit log for every retired instruction
/tmp/spike-build/riscv-isa-sim/build/spike \
    --isa=rv64gc_zicsr_zifencei -m0x80000000:0x10000000 \
    --log-commits testcode/basic_arith.elf

# Via Makefile (dumps to sim/spike/spike.log)
make -C sim spike ELF=../testcode/basic_arith.elf

# Interactive debugger
make -C sim interactive_spike ELF=../testcode/basic_arith.elf
```

### Boot ROM note

Spike executes 5 internal boot ROM instructions at `0x1000` before jumping to `0x80000000`. CVW does not emit RVFI for these (CVW uses its own internal boot ROM). The DPI layer automatically skips all Spike log lines with `PC < program_base` so the two sides stay in sync.

---

## Verilator

Verilator compiles the SystemVerilog RTL to C++ and links a native simulation binary. This is the recommended local flow.

**Minimum version: 5.x** (the Makefile uses `--output-split` and `--threads` flags not available in 4.x).

### Package manager install

**Arch Linux**
```bash
sudo pacman -S verilator
# Currently ships 5.048 — sufficient
```

**Ubuntu / Debian**

Ubuntu 24.04's packaged Verilator is 5.x. Earlier releases ship 4.x and require a source build.
```bash
sudo apt install verilator
verilator --version   # must be ≥ 5.000
```

**Fedora**
```bash
sudo dnf install verilator
verilator --version
```

### Build Verilator from source (any distro, or if package is too old)

```bash
# Dependencies
# Ubuntu/Debian: sudo apt install git perl python3 make autoconf g++ flex bison ccache libgoogle-perftools-dev numactl perl-doc libfl2 libfl-dev zlib1g zlib1g-dev
# Arch:          sudo pacman -S git perl python3 make autoconf gcc flex bison ccache numactl

git clone https://github.com/verilator/verilator.git
cd verilator
git checkout v5.048   # or latest stable tag
autoconf
./configure --prefix=$HOME/.local
make -j$(nproc)
make install
```

### Building the simulation binary

```bash
cd sim
make verilator/build/Vtop_tb
```

`spike.so` (the DPI shared library) is built automatically as a prerequisite:
```makefile
../hvl/common/spike.so: ../hvl/common/spike_dpi.cpp
    g++ -shared -fPIC -O2 $< -o $@
```

`spike.so` has no external library dependencies and compiles with any `g++` ≥ 11.

`spike.so` is **dynamically linked** into `Vtop_tb`. Recompiling `spike.so` takes effect on the next run without relinking `Vtop_tb`.

### Notable Verilator flags used

| Flag | Purpose |
|------|---------|
| `--threads $(nproc)` | Parallel RTL evaluation across all CPU cores |
| `--trace-fst` | Emit FST waveform to `sim/dump.fst` |
| `--output-split 20000` | Split generated C++ to avoid single-TU compile limits |
| `-O3 -march=native -flto` | Aggressive host optimization (passed via `-CFLAGS`/`-LDFLAGS`) |

---

## VCS (EWS only)

Synopsys VCS is available on ECE Engineering Workstations. The flow is identical to Verilator — same RTL sources and testbench, different simulator binary.

```bash
cd sim
make vcs/top_tb                                          # compile
make run_vcs_top_tb PROG=../testcode/basic_arith.elf    # run
make verdi &                                             # open Verdi on FSDB
```

Both `+define+ECE411_NO_FLOAT` and `+define+ECE411_NO_SPIKE_DPI` guards work under VCS. Spike DPI and FP ports compile cleanly.

---

## riscv-formal Submodule

**Path:** `third_party/riscv-formal` (pinned at commit `4f29e83`)

Provides the `rvfimon.v` generator — a formal shadow-register checker that verifies integer register state on every retired instruction, independently of Spike DPI.

### Generating rvfimon.v

```bash
# First generate AMO checker modules (not shipped in submodule at pinned commit):
cd third_party/riscv-formal/insns
python3 gen_amo.py

# Then generate the monitor:
cd ../monitor
python3 generate.py -i rv64imac -a -r 0 -c 1 > ../../../hvl/common/rvfimon.v
```

Flags:
- `-i rv64imac` — RV64 integer + multiply + atomics + compressed
- `-a` — AMO instruction checkers
- `-r 0` — no reorder buffer; in-order single-channel retirement
- `-c 1` — one RVFI retirement channel

`rvfimon.v` is already committed and does not need to be regenerated unless the ISA or channel count changes.

> **SC.W / SC.D**: `spec_valid = 0`. Store-conditional success/failure depends on reservation state, which is not exposed via RVFI, so these cannot be formally checked.

---

## Spike DPI Co-Simulation

`hvl/common/spike_dpi.cpp` is the co-simulation bridge between the CVW RTL and the Spike ISA model. It is compiled to `hvl/common/spike.so` and loaded by Verilator/VCS as a DPI shared library.

### How it works

1. `spike_dpi_init(mem_space, elf_file)` launches:
   ```
   spike --isa=rv64gc_zicsr_zifencei -m0x80000000:0x10000000 --log-commits <elf>
   ```
   via `popen()`. The subprocess runs at native speed and writes its log to a pipe.

2. On each CVW RVFI commit, `monitor.sv` calls `spike_dpi_next(wdata)`, which:
   - Reads lines from the pipe until the PC changes (next instruction)
   - Skips Spike's internal boot ROM (PC < program base)
   - Decodes the instruction to identify source register addresses
   - Reads values from shadow register files (`uint64_t s_iregs[32]`, `s_fregs[32]`)
   - Computes memory mask/data from opcode width and address alignment
   - Fills a 35-word (1120-bit) RVFI packet

3. `monitor.sv` compares the packet field-by-field against the DUT. Any mismatch stops simulation with a diff.

### Spike log format

One line per retired instruction:
```
core   0: 3 0x<pc> (0x<enc>) [effects]
```

`[effects]` combinations:
- *(empty)* — no writes, no memory (e.g., `J` with `rd=x0`)
- `x<n> 0x<val>` — integer register write
- `f<n> 0x<val>` — FP register write
- `x<n> 0x<val> mem 0x<addr>` — integer load (reg write + addr on same line)
- `f<n> 0x<val> mem 0x<addr>` — FP load
- `mem 0x<addr> 0x<data>` — store (data is the written value; DPI computes this from shadow regs)
- `c<name> 0x<val>` — CSR write (parsed but not checked by monitor)

### Memory mask computation

Matches `monitor.sv`'s `funct3_to_mask`:

| funct3[1:0] | Access | Mask |
|-------------|--------|------|
| `00` | byte | `0x01 << byte_offset` |
| `01` | halfword | `0x03 << (offset & ~1)` |
| `10` | word | `0x0F << (offset & ~3)` |
| `11` | doubleword | `0xFF` |

Compressed loads/stores use the same logic with size inferred from the compressed opcode: `C.LW`/`C.SW` → word, `C.LD`/`C.SD`/`C.FLD`/`C.FSD` → doubleword.

### RVFI word layout (35-word packet)

| Words | Field |
|-------|-------|
| [0,1] | `mem_wdata` |
| [2,3] | `mem_rdata` |
| [4] | `mem_wmask` |
| [5] | `mem_rmask` |
| [6,7] | `mem_addr` |
| [8,9] | `pc_wdata` |
| [10,11] | `pc_rdata` |
| [12,13] | `frd_wdata` |
| [14] | `frd_addr` |
| [15,16] | `frs3_rdata` |
| [17,18] | `frs2_rdata` |
| [19,20] | `frs1_rdata` |
| [21] | `frs3_addr` |
| [22] | `frs2_addr` |
| [23] | `frs1_addr` |
| [24,25] | `rd_wdata` |
| [26] | `rd_addr` |
| [27,28] | `rs2_rdata` |
| [29,30] | `rs1_rdata` |
| [31] | `rs2_addr` |
| [32] | `rs1_addr` |
| [33] | `trapped` |
| [34] | `inst` |

---

## Python Utilities

All scripts live in `bin/` and require Python 3.8+.

### `generate_memory_file.py`

Converts an ELF into a flat 8-byte-per-line memory initialization file for `masked_memory.sv`:

```bash
python3 bin/generate_memory_file.py -8 testcode/mytest.elf
# Output: sim/bin/memory_8.lst
```

Called automatically by `make run_verilator_top_tb` and `make run_vcs_top_tb`.

### `rvfi_reference.py`

Reads `hvl/common/rvfi_reference.json` and generates `hvl/common/rvfi_reference.svh`, which maps each RVFI monitor input to the corresponding `dut.monitor_*` signal:

```bash
python3 bin/rvfi_reference.py 1            # with FP (default)
python3 bin/rvfi_reference.py 1 --no_float # without FP
```

Called automatically at build time. Re-run manually if you change `rvfi_reference.json`.

### `get_options.py`

Reads `options.json` and returns individual fields as Makefile-friendly strings:

```bash
python3 bin/get_options.py clock      # → 10000 (ps)
python3 bin/get_options.py arch       # → rv64gc_zicsr_zifencei
python3 bin/get_options.py no_float   # → "" or "+define+ECE411_NO_FLOAT"
```

---

## Running Tests

### One-time build (Verilator)

```bash
cd sim
make verilator/build/Vtop_tb
```

Rerun only when RTL or testbench source changes. `spike.so` rebuilds automatically if `spike_dpi.cpp` is newer.

### Single test

```bash
cd sim
make run_verilator_top_tb PROG=../testcode/basic_arith.elf
```

Output:
- `sim/verilator/simulation.log` — full transcript (commit log + monitor output)
- `sim/dump.fst` — waveform

```bash
gtkwave sim/dump.fst &
```

### Regression (all `testcode/*.elf`)

```bash
cd sim
make regression
```

Runs every `.elf` in `testcode/` in lexicographic order, stopping on first failure. The symlink `sim/bin/spike_dpi.elf` is updated before each test so Spike always runs the correct ELF.

### Overriding cycle timeout

Default is 10,000,000 cycles. For programs that need more time:

```bash
make run_verilator_top_tb PROG=../testcode/sorting_algo.elf TIMEOUT=30000000
```

### VCS (EWS)

```bash
cd sim
make run_vcs_top_tb PROG=../testcode/basic_arith.elf
```

---

## Adding New Test Programs

1. Write a C program that calls `main()` and returns an `int`. The CRT halts on return; no `exit()` call needed.

2. Compile (substitute your distro's GCC binary name):
   ```bash
   riscv64-elf-gcc -march=rv64gc -mabi=lp64d -O2 -nostdlib \
       -T bin/link.ld bin/startup.s testcode/mytest.c \
       -o testcode/mytest.elf
   ```

3. Run:
   ```bash
   cd sim && make run_verilator_top_tb PROG=../testcode/mytest.elf
   ```

Constraints:
- Code and data must fit in `0x80000000–0x8FFFFFFF` (256 MB external AHB window)
- Stack starts at `0x8FF00000` and grows downward; give programs enough headroom
- No OS or syscalls; no external I/O model beyond memory

---

## Configuration Reference

`options.json` at the repo root:

| Key | Value | Meaning |
|-----|-------|---------|
| `clock` | `10000` | Clock period in picoseconds (10 ns = 100 MHz) |
| `xlen` | `64` | RISC-V XLEN |
| `c_ext` | `true` | Compressed (C) extension |
| `f_ext` | `true` | Float (F + D) extension; disabling adds `+define+ECE411_NO_FLOAT` |
| `zicsr` | `true` | CSR instructions |
| `zifencei` | `true` | `FENCE.I` |
| `bmem_0_on_x` | `false` | Return 0 (not X) on uninitialized memory reads |

CVW core features active in `hdl/cvw_config/config.vh` (notable for Linux relevance):

| Feature | Status |
|---------|--------|
| S-mode / U-mode | ✅ enabled |
| Sv39 / Sv48 / Sv57 virtual memory | ✅ enabled |
| CLINT (timer) at `0x02000000` | ✅ enabled |
| PLIC at `0x0C000000` | ✅ enabled |
| UART 16550 at `0x10000000` | ✅ enabled |
| PMP (16 entries) | ✅ enabled |
| Bit manip (Zba/Zbb/Zbc/Zbs) | ✅ enabled |
| Scalar crypto (Zknd/Zkne/Zknh) | ✅ enabled |
| ZFH (half-precision float) | ✅ enabled |

---

## Scope and Limitations

### What this flow verifies

- **Instruction-level correctness**: every retired instruction produces the architecturally correct register writes, PC update, and memory access pattern, matching Spike's reference model.
- **Full ISA coverage**: RV64IMAFDC + Zicsr/Zifencei + Zba/Zbb/Zbc/Zbs via Spike DPI; RV64IMAC formally via `rvfimon.v`.
- **Both integer and FP register files**: source read data and destination write data are compared on every instruction.
- **Memory transactions**: address, byte-enable mask, and masked data for all loads and stores (including compressed variants).

### Gaps versus Linux-boot validation

The current test programs run entirely in **M-mode** with direct physical addressing. Linux boot requires:

| Requirement | CVW hardware | Testbench / test programs |
|-------------|-------------|--------------------------|
| S-mode / U-mode privilege transitions | ✅ implemented | ❌ not exercised |
| Sv39 page-table walks | ✅ implemented (32-entry TLBs) | ❌ `satp` never set |
| `medeleg` / `mideleg` exception delegation | ✅ implemented | ❌ not exercised |
| CLINT timer interrupt delivery | ✅ internally instantiated | ❌ not triggered |
| UART TX observable | ✅ internally instantiated | ❌ TX not captured by testbench |
| PLIC external interrupts | ✅ internally instantiated | ❌ no external IRQ sources wired |
| OpenSBI + Linux image loading | N/A | ❌ no multi-image loader |

**Simulation throughput** is the practical ceiling: 95,593 M-mode instructions take ~31 minutes on a 16-core machine. Linux boot requires tens of billions of instructions — RTL simulation of a full Linux boot is not feasible in Verilator; FPGA prototyping is the standard approach.

**The correct framing**: this flow proves the RTL matches the Spike ISA model instruction-for-instruction on every code path that is actually executed. If you write test programs that exercise S-mode, page-table walks, and interrupt delivery, the flow will validate those paths too. The tooling is complete; the test coverage of privileged features is not.

To validate Linux-boot specifically:
- Use Spike itself to boot Linux first (`spike bbl vmlinux`) — Spike is the authoritative Linux-capable RISC-V reference and boots Linux in seconds.
- This flow proves the RTL matches Spike instruction-for-instruction, so RTL matching Spike ⟹ RTL is Linux-bootable at the instruction level.
- For timing/peripherals/FPGA bring-up, an FPGA prototype remains necessary.
