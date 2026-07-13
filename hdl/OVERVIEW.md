# hdl/ — RTL Source Overview

This directory contains the synthesizable RTL for the FORTE/AMOEBA project.

---

## Files

### `rv64_core_wrapper.sv` — Top-level DUT

The main design-under-test module instantiated by the testbench. It wraps the CVW `wallypipelinedsoc` and exposes two interfaces:

- **`mem_itf`** — 8-byte-wide masked memory interface (addr/rmask/wmask/rdata/wdata/resp). The AHB bridge converts CVW's AHB-Lite bus to this interface.
- **`monitor_*` ports** — RVFI (RISC-V Formal Interface) signals reported at the W-stage for every retired instruction. Used by `rvfimon.v` to formally check correctness against a shadow register file.

Key internal logic:
- Pipeline registers `Rs1DataM/W`, `Rs2DataM/W` track forwarded rs1/rs2 values from E→M→W.
- An **E-stage stash** (`Rs1DataE_stash`, `Rs2DataE_stash`, `E_stash_valid`) handles the MDU divide stall: CVW only asserts `StallE` (not `StallM`) during integer divide, so `ForwardedSrcAE/BE` are combinational and drift as M/W drain. The stash captures the forwarded values on the first stall cycle while the forwarding source is still in M.

### `ahb_to_memitf.sv` — AHB-Lite to `mem_itf` Bridge

Converts CVW's external AHB-Lite master port to the testbench's `mem_itf_w_mask` interface. Supports single (NONSEQ) read and write transfers only — no bursts. A three-state FSM (IDLE → READ/WRITE → IDLE) gates HREADY low until the memory responds.

`HSIZE` and `HADDR[2:0]` are used to compute the byte-enable mask when `HWSTRB` is zero.

### `cvw/` — CVW Submodule (OpenHW Wally)

Git submodule pointing to the OpenHW `cvw` repository (`wallypipelinedsoc`). This is the actual RV64GC processor implementation. Do not edit files inside this directory.

Key internal paths referenced by `rv64_core_wrapper.sv`:

| Path | Signal | Used for |
|------|--------|----------|
| `soc.core.ieu.ForwardedSrcAE` | Forwarded rs1 at E-stage | rs1_rdata tracking |
| `soc.core.ieu.ForwardedSrcBE` | Forwarded rs2 at E-stage | rs2_rdata tracking |
| `soc.core.ieu.dp.regf.rf[]`  | Register file array | (not used directly — Verilator timing issues) |
| `soc.core.hz.StallE/M/W`     | Hazard unit stalls | Pipeline register enables |
| `soc.core.hz.FlushE/M/W`     | Hazard unit flushes | Pipeline register clears |
| `soc.core.ifu.InstrRawD`     | Raw instruction at D-stage | RVFI `inst` field |

### `cvw_config/` — CVW Configuration

`config.vh` is the Wally parameter file included by CVW at compile time. This project is configured as:

- **RV64GC** — XLEN=64, I+M+A+F+D+C+B+K extensions, S+U privilege modes
- External memory (`EXT_MEM_SUPPORTED=1`) at `0x80000000–0x8FFFFFFF` via AHB-Lite
- Internal caches enabled (I$ and D$, 4-way 16 KiB each)
- Reset vector: `0x80000000`
- `UNCORE_RAM_SUPPORTED=0` — no internal SRAM; all data goes through the AHB bridge

Do not enable `UNCORE_RAM_SUPPORTED` alongside `EXT_MEM_SUPPORTED` for the same address range — they will conflict.
