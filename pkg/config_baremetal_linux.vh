//////////////////////////////////////////
// config_baremetal_linux.vh
//
// Written: David_Harris@hmc.edu 4 January 2021
// Modified: Jordan Carlin jcarlin@hmc.edu 14 May 2024
// Modified: pruned to the minimum feature set that boots a soft-float Linux
//
// Purpose: Specify which features of Wally are enabled and set
//          configuration parameters
//
//          This is the bare-minimum Linux parameter set: the smallest core
//          that still boots OpenSBI + Linux 6.6 to userspace, targeting a
//          kernel and userland built entirely soft-float (Berkeley SoftFloat
//          in place of an FPU).  Select it at compile time with
//          +define+AMOEBA_CONFIG_BAREMETAL_LINUX (sim: make ...
//          CONFIG=baremetal_linux).
//
//          UNTESTED against a real image.  testcode/linux currently builds a
//          hard-float kernel (CONFIG_FPU=y) against a device tree that
//          advertises f/d, so the existing boot.lst will NOT run on this
//          config.  See "What the software side must change" below for the
//          exact deltas that image needs.  What has been checked is that this
//          config elaborates and builds clean under Verilator.
//
//          Everything here is a deliberate subtraction from pkg/config.vh.
//          The reasoning for each one is recorded inline, because most of them
//          are only safe because of something specific about this stack --
//          usually that OpenSBI traps and emulates what the hardware no longer
//          does.  Two facts underpin most of the removals:
//
//            1. OpenSBI's delegate_traps() (lib/sbi/sbi_hart.c) delegates
//               misaligned *fetch*, breakpoint, and user ecall to S mode, and
//               nothing else.  Illegal instruction and misaligned load/store
//               stay in M mode, where OpenSBI emulates them.
//            2. OpenSBI probes optional CSRs by writing them under its own
//               trap handler, so absent CSRs are detected, not fatal.
//
//          What the software side must change, relative to testcode/linux:
//
//            - Kernel: CONFIG_FPU=n, and drop CONFIG_RISCV_ISA_ZICBOM,
//              CONFIG_RISCV_ISA_ZICBOZ, CONFIG_RISCV_ISA_SVNAPOT and
//              CONFIG_RISCV_ISA_SVPBMT from configs/linux_amoeba.config.
//            - Userland: built for the lp64 ABI against a soft-float libc;
//              Berkeley SoftFloat supplies the IEEE operations.
//            - Device tree: riscv,isa = "rv64imac_zicsr_zifencei", with
//              riscv,isa-extensions cut to match.  Advertising f/d to a kernel
//              running on this core makes it enable FS and fault on the first
//              FP context switch.  The dts must also drop the plic node and the
//              uart's interrupts property -- see PLIC_SUPPORTED below.
//
// A component of the Wally configurable RISC-V project.
//
// Copyright (C) 2021 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

`include "BranchPredictorType.vh"

// RV32 or RV64: XLEN = 32 or 64
localparam XLEN = 32'd64;

// IEEE 754 compliance
localparam logic IEEE754 = 0;

// RISC-V configuration per specification
// Base instruction set (defaults to I if E is not supported)
localparam logic E_SUPPORTED = 0;

// Integer instruction set extensions
localparam logic ZIFENCEI_SUPPORTED = 1; // required: flush_icache_* and OpenSBI's remote fences
localparam logic ZICSR_SUPPORTED    = 1; // required throughout M/S/U
// Misaligned accesses trap to M mode and OpenSBI emulates them
// (lib/sbi/sbi_misaligned_ldst.c); they are not in the delegated set.  Slower
// than hardware, and it removes the LSU's misaligned path entirely.
// Side benefit: the generated riscv-formal monitor hardcodes "a misaligned
// data access traps", which is exactly what this config now does, so the RVFI
// shadow checker no longer trips the false mismatch that forces LINUX_RVFI=0
// on the main config (see sim/Makefile).
localparam logic ZICCLSM_SUPPORTED  = 0;
localparam logic ZICOND_SUPPORTED   = 0;

// Multiplication & division extensions
// M implies (and in the configuration file requires) Zmmul
localparam logic M_SUPPORTED     = 1;
localparam logic ZMMUL_SUPPORTED = 1;

// Atomic extensions
// A extension is Zaamo + Zalrsc
// Both halves: Linux's spinlocks, futexes and refcounts are lr/sc, and its
// atomic_* helpers are amo.  This is also the one place where the tiny caches
// below could have been a correctness problem and are not -- CVW holds the
// reservation in a standalone address register and valid bit (lrsc.sv), not in
// cache-line state, so evicting the line does not clear the reservation and a
// constrained LR/SC sequence still makes forward progress.
localparam logic ZAAMO_SUPPORTED  = 1;
localparam logic ZALRSC_SUPPORTED = 1;

// Bit manipulation extensions
// B extension is Zba + Zbb + Zbs
// The kernel probes these from the device tree; with them absent from the dts
// it never emits them.
localparam logic ZBA_SUPPORTED = 0;
localparam logic ZBB_SUPPORTED = 0;
localparam logic ZBS_SUPPORTED = 0;
localparam logic ZBC_SUPPORTED = 0;

// Scalar crypto extensions
// Zkn is all 6 of these.  The kernel's crypto is generic C on this build.
localparam logic ZBKB_SUPPORTED = 0;
localparam logic ZBKC_SUPPORTED = 0;
localparam logic ZBKX_SUPPORTED = 0;
localparam logic ZKND_SUPPORTED = 0;
localparam logic ZKNE_SUPPORTED = 0;
localparam logic ZKNH_SUPPORTED = 0;

// Compressed extensions
// C extension is Zca + Zcf (if RV32 and F supported) + Zcd (if D supported)
// All compressed extensions require Zca
localparam logic ZCA_SUPPORTED = 1;  // required: the kernel is built with C
localparam logic ZCB_SUPPORTED = 0;
localparam logic ZCF_SUPPORTED = 0; // RV32 only, requires F
localparam logic ZCD_SUPPORTED = 0; // requires D

// Floating point extensions
// The point of this config.  The entire FPU comes out and Berkeley SoftFloat
// does the work in the kernel and userland instead -- by far the largest area
// saving in the file, and the largest performance cost.  It is also the
// removal with the sharpest software coupling: CONFIG_FPU=n and a device tree
// that does not advertise f/d, or the kernel enables FS and faults.
// A build that clears these must also compile with +define+ECE411_NO_FLOAT, or
// rv64_core_wrapper taps soc.core.fpu.fpu.fregfile, which no longer elaborates.
localparam logic F_SUPPORTED   = 0;
localparam logic D_SUPPORTED   = 0;
localparam logic Q_SUPPORTED   = 0;
localparam logic ZFH_SUPPORTED = 0;
localparam logic ZFA_SUPPORTED = 0;

// privilege modes
// Required: the kernel runs in S, userland in U, OpenSBI in M.
localparam logic S_SUPPORTED = 1; // Supervisor mode
localparam logic U_SUPPORTED = 1; // User mode

// Supervisor level extensions
// Not required: without Sstc the kernel sets its timer through the SBI TIME
// extension, which OpenSBI backs with the CLINT's mtimecmp.
localparam logic SSTC_SUPPORTED = 0; // Supervisor-mode timer interrupts

// Hardware performance counters
// Off, and this is the closest call in the file.  Linux leans on the time CSR
// harder than on anything else here: the riscv clocksource reads it on every
// timekeeping call and the vDSO reads it from user mode.  Without Zicntr each
// of those is an illegal instruction -- which OpenSBI keeps, since
// delegate_traps() never delegates CAUSE_ILLEGAL_INSTRUCTION -- and
// sbi_emulate_csr_read() answers CSR_TIME, CSR_CYCLE and CSR_INSTRET
// (lib/sbi/sbi_emulate_csr.c).  Correct, but a trap round trip on a hot path.
//
// It is off anyway because the cost of turning it on is all-or-nothing rather
// than proportional.  CVW hardcodes the counter index at 5 bits (CounterNumM,
// hdl/core/privileged/csrc.sv), so COUNTERS below 32 indexes an array narrower
// than the index and trips a WIDTHTRUNC that Verilator's .vlt cannot waive by
// file (the blanket hdl/core rule does not catch it, and -module is not a
// supported key in 5.026).  That pins COUNTERS at 32, and the register loop
// runs over COUNTERS unconditionally -- Zihpm gates the event sources, not the
// flops -- so Zicntr costs 32 64-bit counters and 32 incrementers whether or
// not Zihpm is set.  In a core whose caches hold 1 KB between them, that is
// not a rounding error.
//
// Turn it back on only together with COUNTERS = 12'd32, and expect to pay for
// all 32.
localparam logic ZICNTR_SUPPORTED = 0;
localparam logic ZIHPM_SUPPORTED  = 0;
localparam COUNTERS = 12'd0;

// Cache-management operation extensions
// No DMA-coherent device exists on this SoC, so nothing needs a cache
// maintenance op.  Requires dropping CONFIG_RISCV_ISA_ZICBOM/ZICBOZ and the
// riscv,cbom-block-size / riscv,cboz-block-size dts properties.
localparam logic ZICBOM_SUPPORTED = 0;
localparam logic ZICBOZ_SUPPORTED = 0;
localparam logic ZICBOP_SUPPORTED = 0;

// Virtual memory extensions
// Sv39 only: it is what mmu-type in the dts asks for and all the kernel needs
// on a 128 MB machine.  Sv48/Sv57 are deeper walks nothing requests.
// Svpbmt and Svnapot are kernel-side optimisations, not requirements.
// Svadu goes too, and this one is worth stating plainly because it looks
// riskier than it is: without hardware A/D update the walker raises a page
// fault when A is clear, or when D is clear on a store, and Linux's RISC-V
// fault handler has always been able to set those bits in software (Svade is
// the architectural fallback, and Linux ran this way on QEMU for years).
localparam logic SV32_SUPPORTED    = 0;
localparam logic SV39_SUPPORTED    = 1;
localparam logic SV48_SUPPORTED    = 0;
localparam logic SV57_SUPPORTED    = 0;
localparam logic SVPBMT_SUPPORTED  = 0;
localparam logic SVNAPOT_SUPPORTED = 0;
localparam logic SVINVAL_SUPPORTED = 0;
localparam logic SVADU_SUPPORTED   = 0;


// LSU microarchitectural Features
// The bus is required -- the image lives in testbench memory behind the
// external AHB port.  The caches are not required to boot, but with them off
// every fetch and every page-table walk becomes an AHB round trip through a
// 3-cycle behavioral memory, and a boot is hundreds of millions of
// instructions.  They stay, at minimum size (see below).
localparam logic BUS_SUPPORTED = 1;
localparam logic DCACHE_SUPPORTED = 1;
localparam logic ICACHE_SUPPORTED = 1;
localparam logic VECTORED_INTERRUPTS_SUPPORTED = 0; // OpenSBI and Linux use direct mtvec/stvec
localparam logic BIGENDIAN_SUPPORTED = 0;

// TLB configuration.  Entries should be a power of 2
// Sizing, not a requirement: any depth boots, and CVW ships tlb2_rv64gc, so 2
// is the sanctioned floor.  8 is a deliberate stop short of it.  A TLB miss
// here is a three-level Sv39 walk, and every one of those walks is served by
// the 512-byte D-cache below -- shrinking both at once compounds, and 2 entries
// would put the walker in the critical path of nearly every access.
localparam ITLB_ENTRIES = 32'd8;
localparam DTLB_ENTRIES = 32'd8;

// Cache configuration.  Sizes should be a power of two
// typical configuration 4 ways, 4096 bytes per way, 256 bit or more lines
//
// Smallest cache CVW sanctions: 1 way x 512 bytes, which is what its own
// synthesis-trimmed derivatives use (syn_rv32e and friends in
// config/derivlist.txt).  512 bytes total per cache, direct mapped.
//
// The line length deliberately does NOT shrink with the capacity, which is the
// counterintuitive part.  Capacity is NUMWAYS x WAYSIZEINBYTES and does not
// depend on the line at all; the line only sets how that capacity is divided.
// At 512-bit lines this is 8 lines of 64 bytes and 8 tags; at 128-bit lines it
// would be 32 lines of 16 bytes and 32 tags, tripling the tag array to hold
// exactly the same data.  Long lines are the cheaper way to be small.
// 512 bits is also the floor for CACHE_SRAMLEN = 128 to divide evenly and for
// the AHB burst to stay at 8 beats of AHBW.
//
// Cost: this is 8 lines of instructions and 8 of data, direct mapped, for a
// kernel whose hot loops do not come close to fitting.  Expect the boot to run
// several times longer than the 212M cycles the main config takes, and raise
// LINUX_TIMEOUT accordingly.  DCACHE/ICACHE_NUMWAYS and WAYSIZEINBYTES are the
// first knobs to turn if that matters more than the area.
localparam DCACHE_NUMWAYS = 32'd1;
localparam DCACHE_WAYSIZEINBYTES = 32'd512;
localparam DCACHE_LINELENINBITS = 32'd512;
localparam ICACHE_NUMWAYS = 32'd1;
localparam ICACHE_WAYSIZEINBYTES = 32'd512;
localparam ICACHE_LINELENINBITS = 32'd512;
localparam CACHE_SRAMLEN = 32'd128;

// Integer Divider Configuration
// IDIV_BITSPERCYCLE must be 1, 2, or 4
localparam IDIV_BITSPERCYCLE = 32'd4;
localparam logic IDIV_ON_FPU = 0;   // must be 0: there is no FPU to share

// Legal number of PMP entries are 0, 16, or 64
// None.  PMP constrains S and U mode, and nothing in this stack asks it to:
// Linux does not use PMP, and OpenSBI treats it as optional -- it detects the
// count by writing pmpaddr0 under its own trap handler, and
// sbi_hart_pmp_configure() returns immediately when the count is zero
// (lib/sbi/sbi_hart.c).  The firmware simply runs unprotected from the kernel,
// which is the correct trade for a bare-minimum boot config and the wrong one
// for anything that cares about isolation -- pkg/config_freertos_keystone.vh is
// where PMP earns its area.
localparam PMP_ENTRIES = 32'd0;

// grain size should be a full cache line to avoid problems with accesses within a cache line
// that span grain boundaries but are handled without a spill
localparam PMP_G = 32'd0;  // unused with PMP_ENTRIES = 0

// Address space
// boot_shim.bin, per testcode/linux/README.md's memory layout.
localparam logic [63:0] RESET_VECTOR = 64'h0000000080000000;

// WFI Timeout Wait
localparam WFI_TIMEOUT_BIT = 32'd16;

// Peripheral Physical Addresses
// Peripheral memory space extends from BASE to BASE+RANGE
// Range should be a thermometer code with 0's in the upper bits and 1s in the lower bits
localparam logic DTIM_SUPPORTED = 0;
localparam logic [63:0] DTIM_BASE        = 64'h80000000;
localparam logic [63:0] DTIM_RANGE       = 64'h007FFFFF;
localparam logic IROM_SUPPORTED = 0;
localparam logic [63:0] IROM_BASE        = 64'h80000000;
localparam logic [63:0] IROM_RANGE       = 64'h007FFFFF;
localparam logic BOOTROM_SUPPORTED = 0;  // reset vector is in EXT_MEM
localparam logic [63:0] BOOTROM_BASE     = 64'h00001000;
localparam logic [63:0] BOOTROM_RANGE    = 64'h00000FFF;
localparam logic BOOTROM_PRELOAD = 1'b0;
localparam logic UNCORE_RAM_SUPPORTED = 0; // AMOEBA: external AHB

localparam logic [63:0] UNCORE_RAM_BASE  = 64'h80000000;
localparam logic [63:0] UNCORE_RAM_RANGE = 64'h07FFFFFF;
localparam logic UNCORE_RAM_PRELOAD = 1'b0;
// required: shim, firmware, kernel and initramfs all live here
localparam logic EXT_MEM_SUPPORTED = 1; // AMOEBA: external AHB
localparam logic [63:0] EXT_MEM_BASE     = 64'h80000000;
localparam logic [63:0] EXT_MEM_RANGE    = 64'h0FFFFFFF;
// required: mtime/mtimecmp behind SBI TIME, and msip for the IPI path
localparam logic CLINT_SUPPORTED = 1;
localparam logic [63:0] CLINT_BASE       = 64'h02000000;
localparam logic [63:0] CLINT_RANGE      = 64'h0000FFFF;
localparam logic GPIO_SUPPORTED = 0;
localparam logic [63:0] GPIO_BASE        = 64'h10060000;
localparam logic [63:0] GPIO_RANGE       = 64'h000000FF;
// required: the console, and the only way a boot reports success -- the
// testbench's pass criterion is a string PID 1 prints here
localparam logic UART_SUPPORTED = 1;
localparam logic [63:0] UART_BASE        = 64'h10000000;
localparam logic [63:0] UART_RANGE       = 64'h00000007;
// Off, and this is the removal that constrains the device tree hardest.  The
// timer and software interrupts Linux needs are core-local (riscv,cpu-intc),
// not PLIC-routed; the PLIC's only client on this SoC is the UART's receive
// interrupt.  Drop the plic node and the uart's interrupts property and the
// 8250 driver falls back to polling, which is enough for a console that only
// has to print.  Leave them in and the kernel drives a PLIC that is not here.
localparam logic PLIC_SUPPORTED = 0;
localparam logic [63:0] PLIC_BASE        = 64'h0C000000;
localparam logic [63:0] PLIC_RANGE       = 64'h03FFFFFF;
localparam logic SDC_SUPPORTED = 0;
localparam logic [63:0] SDC_BASE         = 64'h00013000;
localparam logic [63:0] SDC_RANGE        = 64'h00000FFF;
localparam logic SPI_SUPPORTED = 0;
localparam logic [63:0] SPI_BASE         = 64'h10040000;
localparam logic [63:0] SPI_RANGE        = 64'h00000FFF;

// Bus Interface width
localparam AHBW = (XLEN);

// Test modes

// AHB
localparam RAM_LATENCY = 32'b0;
localparam logic BURST_EN = 1;   // required in practice: 8-beat line fills

// Tie GPIO outputs back to inputs
localparam logic GPIO_LOOPBACK_TEST = 1;
localparam logic SPI_LOOPBACK_TEST  = 1;

// Hardware configuration
localparam UART_PRESCALE = 32'd1;

// Interrupt configuration
// Unused with PLIC_SUPPORTED = 0, but parameter-defs.vh still reads them.
localparam PLIC_NUM_SRC = 32'd10;
// comment out the following if >=32 sources
localparam PLIC_NUM_SRC_LT_32 = (PLIC_NUM_SRC < 32);
localparam PLIC_GPIO_ID = 32'd3;
localparam PLIC_UART_ID = 32'd10;
localparam PLIC_SPI_ID = 32'd6;
localparam PLIC_SDC_ID = 32'd9;

// Branch prediction
// Performance only, never correctness.  Off here for the same reason as the
// caches, and it stacks with them: no predictor and an 8-line I-cache means
// most taken branches cost both a mispredict and a miss.
localparam logic BPRED_SUPPORTED = 0;
localparam BPRED_TYPE = `BP_GSHARE; // BP_GSHARE_BASIC, BP_GLOBAL, BP_GLOBAL_BASIC, BP_TWOBIT
localparam BPRED_SIZE = 32'd10;
localparam BPRED_NUM_LHR = 32'd6;
localparam BTB_SIZE = 32'd10;
localparam RAS_SIZE = 32'd16;
localparam INSTR_CLASS_PRED = 0;

// FPU division architecture
// Unused with IDIV_ON_FPU = 0, but config-shared.vh derives DIVb and friends
// from them regardless.
localparam RADIX = 32'd4;
localparam DIVCOPIES = 32'd4;

// Memory synthesis configuration
localparam logic USE_SRAM = 0;

`include "config-shared.vh"
