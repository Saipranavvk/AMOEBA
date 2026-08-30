//////////////////////////////////////////
// config_freertos_keystone.vh
//
// Written: David_Harris@hmc.edu 4 January 2021
// Modified: Jordan Carlin jcarlin@hmc.edu 14 May 2024
// Modified: pruned to the minimum feature set for a Keystone + FreeRTOS image
//
// Purpose: Specify which features of Wally are enabled and set
//          configuration parameters
//
//          This is the Keystone-FreeRTOS parameter set: config_freertos.vh
//          plus everything the Keystone security monitor and the OpenSBI 1.1
//          firmware it rides on actually need.  Select it at compile time with
//          +define+AMOEBA_CONFIG_FREERTOS_KEYSTONE (sim: make ...
//          CONFIG=freertos_keystone).
//
//          UNTESTED.  No Keystone-FreeRTOS image exists yet -- testcode/keystone
//          currently boots Linux 6.6 under the SM -- so nothing has run against
//          this config.  It is sized from the sources of the stack it is meant
//          to carry, and is intended for synthesis area estimates ahead of that
//          image.  The assumed arrangement is the same three-layer stack as the
//          Keystone Linux test, with FreeRTOS in place of Linux:
//
//              M mode  OpenSBI 1.1 + Keystone SM  (testcode/keystone)
//              S mode  FreeRTOS payload
//              U mode  enclave
//
//          Note for whoever builds that image: the in-tree FreeRTOS port
//          (third_party/FreeRTOS-Kernel/portable/GCC/RISC-V, used by
//          testcode/freertos) is machine mode only -- portASM.S drives mtvec,
//          mret, and the CLINT's mtimecmp directly -- and the SM owns M mode.
//          The payload therefore needs an S-mode port driving stvec/sret and
//          taking its tick from the SBI TIME extension.  That is a software
//          problem; it does not change the parameters below.
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
// Zifencei comes back relative to config_freertos.vh: sbi_tlb.c issues a bare
// fence.i to service the SBI remote-fence calls.
localparam logic ZIFENCEI_SUPPORTED = 1; // Instruction-Fetch fence
localparam logic ZICSR_SUPPORTED    = 1; // required throughout M/S/U
// Misaligned accesses trap to M mode, where OpenSBI emulates them
// (lib/sbi/sbi_misaligned_ldst.c).  Correct but slow, so revisit this one if
// the payload turns out to fault often.
localparam logic ZICCLSM_SUPPORTED  = 0;
localparam logic ZICOND_SUPPORTED   = 0;

// Multiplication & division extensions
// M implies (and in the configuration file requires) Zmmul
localparam logic M_SUPPORTED     = 1;
localparam logic ZMMUL_SUPPORTED = 1;

// Atomic extensions
// A extension is Zaamo + Zalrsc
// Both halves are needed here, unlike config_freertos.vh: OpenSBI's spinlocks
// are lr.w.aq/sc.w.rl (lib/sbi/riscv_locks.c) and its atomics are amoswap/
// amoadd (lib/sbi/riscv_atomic.c).
localparam logic ZAAMO_SUPPORTED  = 1;
localparam logic ZALRSC_SUPPORTED = 1;

// Bit manipulation extensions
// B extension is Zba + Zbb + Zbs
localparam logic ZBA_SUPPORTED = 0;
localparam logic ZBB_SUPPORTED = 0;
localparam logic ZBS_SUPPORTED = 0;
localparam logic ZBC_SUPPORTED = 0;

// Scalar crypto extensions
// Zkn is all 6 of these.  Keystone's attestation does SHA-3 and ed25519 in
// software inside the SM, so none of this is on the boot path.
localparam logic ZBKB_SUPPORTED = 0;
localparam logic ZBKC_SUPPORTED = 0;
localparam logic ZBKX_SUPPORTED = 0;
localparam logic ZKND_SUPPORTED = 0;
localparam logic ZKNE_SUPPORTED = 0;
localparam logic ZKNH_SUPPORTED = 0;

// Compressed extensions
// C extension is Zca + Zcf (if RV32 and F supported) + Zcd (if D supported)
// All compressed extensions require Zca
localparam logic ZCA_SUPPORTED = 1;
localparam logic ZCB_SUPPORTED = 0;
localparam logic ZCF_SUPPORTED = 0; // RV32 only, requires F
localparam logic ZCD_SUPPORTED = 0; // requires D

// Floating point extensions
// Nothing in the stack uses floating point: OpenSBI and the SM build lp64, and
// so does FreeRTOS.  This is the single largest area saving in the file, and
// the reason this config cannot boot the existing Keystone *Linux* image --
// that one runs CONFIG_FPU=y and its DTS advertises f/d.  A Keystone-FreeRTOS
// DTS must advertise neither.
// A build that clears these must also compile with +define+ECE411_NO_FLOAT, or
// rv64_core_wrapper taps soc.core.fpu.fpu.fregfile, which no longer elaborates.
localparam logic F_SUPPORTED   = 0;
localparam logic D_SUPPORTED   = 0;
localparam logic Q_SUPPORTED   = 0;
localparam logic ZFH_SUPPORTED = 0;
localparam logic ZFA_SUPPORTED = 0;

// privilege modes
// The whole point of the config: the SM runs in M mode, the payload in S, the
// enclave in U.  config_freertos.vh gets away with M only; this one cannot.
localparam logic S_SUPPORTED = 1; // Supervisor mode
localparam logic U_SUPPORTED = 1; // User mode

// Supervisor level extensions
// Not required: OpenSBI serves S-mode timers through the SBI TIME extension
// backed by the CLINT, which is the path Keystone's own targets take.
localparam logic SSTC_SUPPORTED = 0; // Supervisor-mode timer interrupts

// Hardware performance counters
// Off, and safe here for a reason worth recording.  An S-mode rdtime with no
// Zicntr is an illegal instruction, and OpenSBI 1.1 keeps that trap: its
// delegate_traps() (lib/sbi/sbi_hart.c) delegates misaligned fetch, breakpoint,
// and user ecall to S mode but never CAUSE_ILLEGAL_INSTRUCTION, so the trap
// lands in M mode where sbi_emulate_csr_read() answers CSR_TIME, CSR_CYCLE, and
// CSR_INSTRET (lib/sbi/sbi_emulate_csr.c).  The payload should be taking its
// tick from the SBI TIME extension in any case; a stray rdtime costs a trap
// round trip, not a fault.
//
// Turning Zicntr back on is not free the way it looks: CVW hardcodes the
// counter index at 5 bits (CounterNumM, hdl/core/privileged/csrc.sv:75), so the
// only COUNTERS value that lints clean is 32, and all 32 registers are
// instantiated whether or not Zihpm is set.
localparam logic ZICNTR_SUPPORTED = 0;
localparam logic ZIHPM_SUPPORTED  = 0;
localparam COUNTERS = 12'd0;

// Cache-management operation extensions
// cbo.flush only, and only for the payload: tohost_exit() in
// testcode/freertos/syscalls_amoeba.c needs it to push the exit code out of
// the write-back D-cache.  Drop it if the image reports through the UART tap
// instead, the way the Linux and Keystone tiers do.
localparam logic ZICBOM_SUPPORTED = 1;
localparam logic ZICBOZ_SUPPORTED = 0;
localparam logic ZICBOP_SUPPORTED = 0;

// Virtual memory extensions
// Sv39 only.  The SM walks and validates enclave page tables, and its PMP code
// issues sfence.vma (sm/src/pmp.h), so translation has to be real -- but
// nothing in the stack asks for a deeper walk, and Svpbmt/Svnapot/Svinval are
// Linux-side optimisations this image does not carry.
// Svadu stays on: hardware A/D update means neither the payload nor the enclave
// runtime needs a page-fault handler for the accessed and dirty bits, and
// neither has one.
localparam logic SV32_SUPPORTED    = 0;
localparam logic SV39_SUPPORTED    = 1;
localparam logic SV48_SUPPORTED    = 0;
localparam logic SV57_SUPPORTED    = 0;
localparam logic SVPBMT_SUPPORTED  = 0;
localparam logic SVNAPOT_SUPPORTED = 0;
localparam logic SVINVAL_SUPPORTED = 0;
localparam logic SVADU_SUPPORTED   = 1;


// LSU microarchitectural Features
// As in config_freertos.vh: the bus is required, the caches are not, but an
// uncached fetch per instruction would make a boot-length run untenable.
localparam logic BUS_SUPPORTED = 1;
localparam logic DCACHE_SUPPORTED = 1;
localparam logic ICACHE_SUPPORTED = 1;
localparam logic VECTORED_INTERRUPTS_SUPPORTED = 0; // OpenSBI and the SM use direct mtvec
localparam logic BIGENDIAN_SUPPORTED = 0;

// TLB configuration.  Entries should be a power of 2
// Sizing, not a requirement -- 32 is what the proven Keystone Linux boot runs
// with.  8 or 16 are legal downsizes if the area matters more than the walk
// rate on a multi-hundred-million-cycle boot.
localparam ITLB_ENTRIES = 32'd32;
localparam DTLB_ENTRIES = 32'd32;

// Cache configuration.  Sizes should be a power of two
// typical configuration 4 ways, 4096 bytes per way, 256 bit or more lines
localparam DCACHE_NUMWAYS = 32'd4;
localparam DCACHE_WAYSIZEINBYTES = 32'd4096;
localparam DCACHE_LINELENINBITS = 32'd512;
localparam ICACHE_NUMWAYS = 32'd4;
localparam ICACHE_WAYSIZEINBYTES = 32'd4096;
localparam ICACHE_LINELENINBITS = 32'd512;
localparam CACHE_SRAMLEN = 32'd128;

// Integer Divider Configuration
// IDIV_BITSPERCYCLE must be 1, 2, or 4
localparam IDIV_BITSPERCYCLE = 32'd4;
localparam logic IDIV_ON_FPU = 0;   // must be 0: there is no FPU to share

// Legal number of PMP entries are 0, 16, or 64
// This is the hardware Keystone is: the SM's isolation is nothing but PMP.
// Its generic platform asks for PMP_N_REG = 8
// (sm/src/platform/generic/platform.h), and 16 is the smallest legal CVW value
// that covers 8 while leaving OpenSBI its own root-domain entries.
localparam PMP_ENTRIES = 32'd16;

// grain size should be a full cache line to avoid problems with accesses within a cache line
// that span grain boundaries but are handled without a spill
// Keystone's regions are page aligned or larger, so a 64-byte grain costs it
// nothing.
localparam PMP_G = 32'd4;  //e.g. 4 for 64-byte grains (512-bit cache lines)

// Address space
// OpenSBI firmware base.  Keystone's secure-boot patch pins the Sanctum key
// page at 0x801ff000 and the payload at 0x80200000, so this cannot move and
// there is no room for a boot shim on the reset vector.
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
// required: firmware, payload, and the enclave private memory all live here
localparam logic EXT_MEM_SUPPORTED = 1; // AMOEBA: external AHB
localparam logic [63:0] EXT_MEM_BASE     = 64'h80000000;
localparam logic [63:0] EXT_MEM_RANGE    = 64'h0FFFFFFF;
// required: OpenSBI's timer and IPI services are backed by mtime/mtimecmp/msip
localparam logic CLINT_SUPPORTED = 1;
localparam logic [63:0] CLINT_BASE       = 64'h02000000;
localparam logic [63:0] CLINT_RANGE      = 64'h0000FFFF;
localparam logic GPIO_SUPPORTED = 0;
localparam logic [63:0] GPIO_BASE        = 64'h10060000;
localparam logic [63:0] GPIO_RANGE       = 64'h000000FF;
// required: the SM's [SM] banner and every console byte OpenSBI prints
localparam logic UART_SUPPORTED = 1;
localparam logic [63:0] UART_BASE        = 64'h10000000;
localparam logic [63:0] UART_RANGE       = 64'h00000007;
// Off, and it constrains the device tree: OpenSBI's generic platform probes an
// interrupt controller out of the DTS and would drive a PLIC that is not here.
// The Keystone-FreeRTOS DTS must therefore omit the plic node -- it cannot
// share testcode/linux/dts/amoeba.dts, which declares one.  A FreeRTOS payload
// has no use for external interrupts; set this back to 1 if that stops being
// true.
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
localparam logic BURST_EN = 1;

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
// Performance only, never correctness -- but this is the config where that
// costs the most.  The Keystone Linux boot is 213M cycles with the predictor
// on; turning it off is the largest single lever on how long the eventual
// FreeRTOS boot test takes, in exchange for the gshare tables, the BTB, and
// the RAS.
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
