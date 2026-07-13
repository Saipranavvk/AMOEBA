# FORTE / AMOEBA

**ECE 427 Tapeout – Secure Linux-Capable Processor**

The DUT is an OpenHW CVW `wallypipelinedsoc` core (RV64GC) wrapped in `hdl/rv64_core_wrapper.sv`. Every retired instruction is co-simulated against Spike (the official RISC-V ISA reference) and formally checked by the riscv-formal RVFI monitor.

---

## Repo Layout

```
hdl/                  RTL sources (DUT + CVW submodule)
hvl/                  Testbench sources (common/ + per-simulator/)
  common/spike_dpi.cpp  Spike DPI co-simulation bridge
  common/spike.so       Compiled DPI shared library (auto-built)
pkg/                  Shared SystemVerilog packages (types.sv)
sim/                  Makefile + build artifacts
testcode/             C test programs and compiled ELFs
third_party/          riscv-formal submodule (rvfimon generator)
bin/                  Build helper scripts
```

---

## Quick Start

### 0. Build Spike from source (required once)

Distribution packages for Spike do **not** include `--enable-commitlog` support, which is required for co-simulation. Build from source:

```bash
# Ubuntu/Debian
sudo apt install device-tree-compiler libboost-all-dev build-essential git
# Arch
sudo pacman -S dtc boost base-devel git
# Fedora
sudo dnf install dtc boost-devel gcc-c++ make git

mkdir -p /tmp/spike-build && cd /tmp/spike-build
git clone --depth=1 https://github.com/riscv-software-src/riscv-isa-sim.git
cd riscv-isa-sim && mkdir build && cd build
../configure --prefix=$HOME/.local --enable-commitlog
make -j$(nproc)
```

The DPI layer auto-detects the binary at `/tmp/spike-build/riscv-isa-sim/build/spike`.

### 1. Compile a test program (optional — ELFs are pre-built)

The binary name varies by distribution (`riscv64-elf-gcc` on Arch, `riscv64-unknown-elf-gcc` on Ubuntu, etc.).

```bash
# Substitute your distro's RISC-V bare-metal cross-compiler binary name:
riscv64-elf-gcc -march=rv64gc -mabi=lp64d -O2 -nostdlib \
    -T bin/link.ld bin/startup.s testcode/mytest.c \
    -o testcode/mytest.elf
```

Pre-built ELFs are checked in under `testcode/`. See [TOOLING.md](TOOLING.md) for per-distro install instructions.

### 2. Run with Verilator (recommended for local dev)

```bash
cd sim

# Build Verilator binary and spike.so (one time, ~5 min)
make verilator/build/Vtop_tb

# Run a single test
make run_verilator_top_tb PROG=../testcode/basic_arith.elf

# Run all .elf files in testcode/ as a regression
make regression
```

Outputs:
- `sim/verilator/simulation.log` — full transcript with per-instruction commit log
- `sim/dump.fst` — FST waveform

```bash
gtkwave sim/dump.fst &
```

### 3. Run with VCS + Verdi (EWS / license-gated)

```bash
cd sim
make vcs/top_tb
make run_vcs_top_tb PROG=../testcode/basic_arith.elf
make verdi &           # opens Verdi on the last FSDB dump
```

### 4. Spike reference ISA simulator

```bash
cd sim
make spike ELF=../testcode/basic_arith.elf        # commit log → spike/spike.log
make interactive_spike ELF=../testcode/basic_arith.elf   # interactive -d debugger
```

---

## Verification

Two independent checkers run simultaneously on every retired instruction:

### Spike DPI co-simulation

`hvl/common/spike_dpi.cpp` launches Spike as a subprocess (`--log-commits`) and compares each instruction's register writes, PC update, and memory transaction against the DUT's RVFI output. A mismatch stops simulation immediately with a field-by-field diff:

```
-------begin spike mismatch--------
signal     diff       dut     spike
inst            h00004782 h00004782
rd_addr    --->        15        15
rd_wdata              ...       ...
mem_rmask             ...       ...
...
-------end spike mismatch----------
```

Covers: RV64IMAFDC + Zicsr/Zifencei + Zba/Zbb/Zbc/Zbs (all extensions Spike knows about).

`spike.so` is automatically compiled from `spike_dpi.cpp` before the first Verilator build. It has no external library dependencies and rebuilds on any machine with `g++`.

### riscv-formal RVFI monitor

`hvl/common/rvfimon.v` is a formal shadow-register checker generated from the riscv-formal submodule. It independently tracks integer register state and validates every write on retirement.

To regenerate (already committed, only needed after ISA changes):

```bash
cd third_party/riscv-formal/insns && python3 gen_amo.py
cd ../monitor && python3 generate.py -i rv64imac -a -r 0 -c 1 > ../../../hvl/common/rvfimon.v
```

The field mapping from RVFI monitor inputs to `dut.monitor_*` signals is in `hvl/common/rvfi_reference.json`. `bin/rvfi_reference.py` auto-generates `hvl/common/rvfi_reference.svh` from it at build time.

---

## Makefile Targets (sim/)

| Target | Description |
|--------|-------------|
| `verilator/build/Vtop_tb` | Compile Verilator binary (incremental; also builds `spike.so`) |
| `run_verilator_top_tb` | Run Verilator simulation (`PROG=` required) |
| `vcs/top_tb` | Compile VCS binary |
| `run_vcs_top_tb` | Run VCS simulation (`PROG=` required) |
| `regression` | Run all `testcode/*.elf` through Verilator in sequence |
| `spike` | Run Spike ISA sim, dump commit log (`ELF=` required) |
| `interactive_spike` | Run Spike interactive debugger (`ELF=` required) |
| `verdi` | Open Verdi on last VCS waveform dump |
| `clean` | Remove all build artifacts |

Override cycle timeout (default 10,000,000):

```bash
make run_verilator_top_tb PROG=../testcode/sorting_algo.elf TIMEOUT=20000000
```

---

## CVW Configuration

The CVW core is configured in `hdl/cvw_config/config.vh`. Notable settings:

- **XLEN = 64**, reset vector `0x80000000`
- Extensions: RV64IMAFDCBK + Zicsr/Zifencei/Zicond + ZFH/ZFA + scalar crypto (Zkn)
- Privilege: S-mode + U-mode enabled; Sv39/48/57 MMU; 32-entry I/D TLBs; 16 PMP entries
- External memory via AHB-Lite: `EXT_MEM_SUPPORTED = 1`, `0x80000000–0x8FFFFFFF` (256 MB)
- Internal peripherals: CLINT (`0x02000000`), PLIC (`0x0C000000`), UART (`0x10000000`), GPIO, SPI
- I-cache and D-cache: 4-way, 4 KiB/way, 512-bit lines
- Integer divider: 4 bits/cycle; branch predictor: GShare 10-bit

---

## Toolchain Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| `verilator` | ≥ 5.000 | RTL simulation |
| `g++` | ≥ 11 | Compiles `spike.so` and Verilator C++ |
| `spike` (source build) | main branch | ISA reference co-simulation |
| `riscv64-*-elf-gcc` | any recent | Bare-metal cross-compiler for test ELFs |
| `python3` | ≥ 3.8 | Build helper scripts |
| `vcs` / `verdi` | — | EWS-only VCS simulation + waveform |
| `gtkwave` | any | FST waveform viewer (Verilator) |

See [TOOLING.md](TOOLING.md) for per-distribution install commands and build instructions.

---

## Test Programs

| File | RVFI commits | Description |
|------|-------------|-------------|
| `testcode/basic_arith.elf` | 219 | Arithmetic smoke test |
| `testcode/sorting_algo.elf` | 95,593 | Iterative quicksort, N=1000 (~31 min in Verilator) |

Programs terminate with `slti x0, x0, -256` (encoding `0xF0002013`), which the testbench detects as the halt instruction.

---

## Linux-Bootability

CVW's hardware is fully Linux-capable: S/U privilege modes, Sv39/48/57 MMU, CLINT, PLIC, UART, and PMP are all enabled. The **current test programs** exercise only M-mode bare-metal arithmetic and do not exercise privilege transitions, page tables, or interrupts.

The Spike DPI flow proves RTL ≡ Spike instruction-for-instruction on every executed code path. Since Spike can boot Linux, a DUT that matches Spike on a complete Linux boot trace would be validated Linux-bootable. Exercising that in Verilator RTL simulation is not practical (tens of billions of cycles); FPGA prototyping is the standard next step.

See [TOOLING.md § Scope and Limitations](TOOLING.md#scope-and-limitations) for a detailed gap analysis.
