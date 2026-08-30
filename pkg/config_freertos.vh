//////////////////////////////////////////
// config_freertos.vh
//
// Written: David_Harris@hmc.edu 4 January 2021
// Modified: Jordan Carlin jcarlin@hmc.edu 14 May 2024
// Modified: pruned to the minimum feature set that boots FreeRTOS
//
// Purpose: Specify which features of Wally are enabled and set
//          configuration parameters
//
//          This is the FreeRTOS-only parameter set.  Everything the FreeRTOS
//          tier never executes has been turned off; see the notes on each
//          block for why a feature stayed or went.  Select it at compile time
//          with +define+AMOEBA_CONFIG_FREERTOS (sim: make ... MINCONFIG=1);
//          pkg/config.vh remains the full RV64GC configuration used by the
//          baremetal, ISA, and Linux tiers.
//
//          The workload it is cut for is testcode/freertos, built by
//          testcode/freertos/Makefile as -march=rv64imac_zicsr -mabi=lp64,
//          running entirely in machine mode.  Disassembling every tc_*.c image
//          gives the exact instruction set it needs: base I, M (mul/mulw/
//          mulhu/divu/remu), Zaamo (amoadd.w/.d), Zca (c.*), Zicsr, and the
//          bare cbo.flush from Zicbom that syscalls_amoeba.c uses to push
//          tohost out of the write-back D-cache.  Nothing else appears.
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
localparam XLEN = 32'd64;   // required: lp64 ABI

// IEEE 754 compliance
localparam logic IEEE754 = 0;

// RISC-V configuration per specification
// Base instruction set (defaults to I if E is not supported)
localparam logic E_SUPPORTED = 0;   // required: the images use x16-x31

// Integer instruction set extensions
localparam logic ZIFENCEI_SUPPORTED = 0; // no fence.i in the images (plain fence is base I)
localparam logic ZICSR_SUPPORTED    = 1; // required: mstatus/mtvec/mepc/mcause/mie/mhartid
localparam logic ZICCLSM_SUPPORTED  = 0; // no misaligned access is executed
localparam logic ZICOND_SUPPORTED   = 0; // not in -march

// Multiplication & division extensions
// M implies (and in the configuration file requires) Zmmul
localparam logic M_SUPPORTED     = 1;   // required: mul/mulw/mulhu/divu/remu
localparam logic ZMMUL_SUPPORTED = 1;   // required by M

// Atomic extensions
// A extension is Zaamo + Zalrsc
localparam logic ZAAMO_SUPPORTED  = 1;  // required: amoadd.w/.d in the FreeRTOS port
localparam logic ZALRSC_SUPPORTED = 0;  // no lr/sc is executed

// Bit manipulation extensions
// B extension is Zba + Zbb + Zbs
localparam logic ZBA_SUPPORTED = 0;
localparam logic ZBB_SUPPORTED = 0;
localparam logic ZBS_SUPPORTED = 0;
localparam logic ZBC_SUPPORTED = 0;

// Scalar crypto extensions
// Zkn is all 6 of these
localparam logic ZBKB_SUPPORTED = 0;
localparam logic ZBKC_SUPPORTED = 0;
localparam logic ZBKX_SUPPORTED = 0;
localparam logic ZKND_SUPPORTED = 0;
localparam logic ZKNE_SUPPORTED = 0;
localparam logic ZKNH_SUPPORTED = 0;

// Compressed extensions
// C extension is Zca + Zcf (if RV32 and F supported) + Zcd (if D supported)
// All compressed extensions require Zca
localparam logic ZCA_SUPPORTED = 1;  // required: the images are built with C
localparam logic ZCB_SUPPORTED = 0;
localparam logic ZCF_SUPPORTED = 0; // RV32 only, requires F
localparam logic ZCD_SUPPORTED = 0; // requires D

// Floating point extensions
// The whole FPU goes: -mabi=lp64 and no floating point instruction is reachable.
// A build that clears these must also compile with +define+ECE411_NO_FLOAT, or
// rv64_core_wrapper taps soc.core.fpu.fpu.fregfile, which no longer elaborates.
localparam logic F_SUPPORTED   = 0;
localparam logic D_SUPPORTED   = 0;
localparam logic Q_SUPPORTED   = 0;
localparam logic ZFH_SUPPORTED = 0;
localparam logic ZFA_SUPPORTED = 0;

// privilege modes
// FreeRTOS is a flat machine-mode kernel: freertos_crt.S installs mtvec and
// calls main() in M mode, and portASM.S restores mstatus with MPP=M_Mode
// (0x1880) on every context switch, so no task ever leaves M mode.
localparam logic S_SUPPORTED = 0; // Supervisor mode
localparam logic U_SUPPORTED = 0; // User mode

// Supervisor level extensions
localparam logic SSTC_SUPPORTED = 0; // Supervisor-mode timer interrupts

// Hardware performance counters
// The port takes its tick from the CLINT's memory-mapped mtime, not from any
// counter CSR, and nothing in the images reads cycle/time/instret.
localparam logic ZICNTR_SUPPORTED = 0;
localparam logic ZIHPM_SUPPORTED  = 0;
localparam COUNTERS = 12'd0;

// Cache-management operation extensions
// cbo.flush only.  tohost_exit() in syscalls_amoeba.c writes tohost and then
// flushes the line by hand; without Zicbom that store stays dirty in the
// write-back D-cache, never reaches AHB, and the testbench never sees the
// exit code.
localparam logic ZICBOM_SUPPORTED = 1;
localparam logic ZICBOZ_SUPPORTED = 0;
localparam logic ZICBOP_SUPPORTED = 0;

// Virtual memory extensions
// No satp, no page tables: the images run bare on physical addresses.
localparam logic SV32_SUPPORTED    = 0;
localparam logic SV39_SUPPORTED    = 0;
localparam logic SV48_SUPPORTED    = 0;
localparam logic SV57_SUPPORTED    = 0;
localparam logic SVPBMT_SUPPORTED  = 0;
localparam logic SVNAPOT_SUPPORTED = 0;
localparam logic SVINVAL_SUPPORTED = 0;
localparam logic SVADU_SUPPORTED   = 0;


// LSU microarchitectural Features
// BUS_SUPPORTED is required: the test image lives in the testbench memory
// behind the external AHB port.  The caches are not required to boot, but they
// are kept -- an uncached fetch per instruction through the 3-cycle behavioral
// memory would push the tests past the simulation timeout, and the D-cache is
// what makes the cbo.flush above necessary in the first place.
localparam logic BUS_SUPPORTED = 1;
localparam logic DCACHE_SUPPORTED = 1;
localparam logic ICACHE_SUPPORTED = 1;
localparam logic VECTORED_INTERRUPTS_SUPPORTED = 0; // freertos_crt.S writes mtvec in direct mode
localparam logic BIGENDIAN_SUPPORTED = 0;

// TLB configuration.  Entries should be a power of 2
localparam ITLB_ENTRIES = 32'd0;    // no virtual memory
localparam DTLB_ENTRIES = 32'd0;

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
// PMP only constrains S and U mode, and neither exists here.
localparam PMP_ENTRIES = 32'd0;

// grain size should be a full cache line to avoid problems with accesses within a cache line
// that span grain boundaries but are handled without a spill
localparam PMP_G = 32'd0;  // unused with PMP_ENTRIES = 0

// Address space
localparam logic [63:0] RESET_VECTOR = 64'h0000000080000000;  // _start, per freertos_wally.ld

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
localparam logic BOOTROM_SUPPORTED = 0;  // reset vector is in EXT_MEM, nothing fetches from 0x1000
localparam logic [63:0] BOOTROM_BASE     = 64'h00001000;
localparam logic [63:0] BOOTROM_RANGE    = 64'h00000FFF;
localparam logic BOOTROM_PRELOAD = 1'b0;
localparam logic UNCORE_RAM_SUPPORTED = 0; // AMOEBA: external AHB

localparam logic [63:0] UNCORE_RAM_BASE  = 64'h80000000;
localparam logic [63:0] UNCORE_RAM_RANGE = 64'h07FFFFFF;
localparam logic UNCORE_RAM_PRELOAD = 1'b0;
// required: text, data, heap, stack, and tohost (0x80800000) all live here
localparam logic EXT_MEM_SUPPORTED = 1; // AMOEBA: external AHB
localparam logic [63:0] EXT_MEM_BASE     = 64'h80000000;
localparam logic [63:0] EXT_MEM_RANGE    = 64'h0FFFFFFF;
// required: mtime/mtimecmp drive the 10 kHz tick (FreeRTOSConfig.h) and
// portASM.S takes the software-interrupt path through msip
localparam logic CLINT_SUPPORTED = 1;
localparam logic [63:0] CLINT_BASE       = 64'h02000000;
localparam logic [63:0] CLINT_RANGE      = 64'h0000FFFF;
localparam logic GPIO_SUPPORTED = 0;
localparam logic [63:0] GPIO_BASE        = 64'h10060000;
localparam logic [63:0] GPIO_RANGE       = 64'h000000FF;
// required: printf()/configASSERT() reach the outside world through the
// NS16550 transmit register, which the testbench snoops for the test log
localparam logic UART_SUPPORTED = 1;
localparam logic [63:0] UART_BASE        = 64'h10000000;
localparam logic [63:0] UART_RANGE       = 64'h00000007;
localparam logic PLIC_SUPPORTED = 0;   // no external interrupt source is used
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
// Performance only; a mispredict costs cycles, never correctness.
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
