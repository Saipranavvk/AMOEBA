///////////////////////////////////////////
// csr_harden_tb.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 28 August 2026
// Modified: 29 August 2026 — Updated for TMR + redundant-check-bit hardening
//
// Purpose: Self-checking testbench for csrharden (combinational) and
//          privmode (FSM + TMR hardening), including adversarial fault
//          injection via Verilator force/release.
//
// A component of the AMOEBA RISC-V project.
//
// Copyright (C) 2026 Saipranavvk
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License"); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps

module csr_harden_tb;

  import cvw::*;

  // ── Clock ─────────────────────────────────────────────────────────────────────
  logic clk;
  initial clk = 0;
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // ── cvw_t parameter struct ────────────────────────────────────────────────────
  // Only the fields consumed by privmode need to be non-zero.
  // M_MODE=2'b11, S_MODE=2'b01, U_MODE=2'b00 — as in the RISC-V privileged spec.
  localparam cvw_t P = '{
    M_MODE        : 2'b11,
    S_MODE        : 2'b01,
    U_MODE        : 2'b00,
    U_SUPPORTED   : 1'b1,
    S_SUPPORTED   : 1'b1,
    // All remaining fields zeroed out; they are not used by privmode/csrharden.
    default       : '0
  };

  // ── csrharden DUT ─────────────────────────────────────────────────────────────
  logic       ch_PrivModeSecFaultW;
  logic       ch_PrivModeUncorrectableFaultW;
  logic       ch_MppReservedM;
  logic       ch_IllegalCSRAccessM;
  logic       ch_InstrValidM;
  logic [6:0] ch_SecFaultM;

  csrharden dut_csrharden (
    .PrivModeSecFaultW           (ch_PrivModeSecFaultW),
    .PrivModeUncorrectableFaultW (ch_PrivModeUncorrectableFaultW),
    .MppReservedM                (ch_MppReservedM),
    .IllegalCSRAccessM           (ch_IllegalCSRAccessM),
    .InstrValidM                 (ch_InstrValidM),
    .SecFaultM                   (ch_SecFaultM)
  );

  // ── privmode DUT ──────────────────────────────────────────────────────────────
  logic       pm_reset;
  logic       pm_StallW;
  logic       pm_TrapM;
  logic       pm_mretM, pm_sretM;
  logic       pm_DelegateM;
  logic [1:0] pm_STATUS_MPP;
  logic       pm_STATUS_SPP;
  logic [1:0] pm_NextPrivilegeModeM;
  logic [1:0] pm_PrivilegeModeW;
  logic       pm_PrivModeSecFaultW;
  logic       pm_PrivModeUncorrectableFaultW;

  privmode #(.P(P)) dut_privmode (
    .clk                         (clk),
    .reset                       (pm_reset),
    .StallW                      (pm_StallW),
    .TrapM                       (pm_TrapM),
    .mretM                       (pm_mretM),
    .sretM                       (pm_sretM),
    .DelegateM                   (pm_DelegateM),
    .STATUS_MPP                  (pm_STATUS_MPP),
    .STATUS_SPP                  (pm_STATUS_SPP),
    .NextPrivilegeModeM          (pm_NextPrivilegeModeM),
    .PrivilegeModeW              (pm_PrivilegeModeW),
    .PrivModeSecFaultW           (pm_PrivModeSecFaultW),
    .PrivModeUncorrectableFaultW (pm_PrivModeUncorrectableFaultW)
  );

  // ── Helpers ───────────────────────────────────────────────────────────────────
  int fail_count;

  task automatic check(input string label, input bit cond);
    if (!cond) begin
      $display("FAIL: %s", label);
      fail_count++;
    end
  endtask

  // Drive all privmode control inputs to a known idle state.
  task automatic pm_idle();
    pm_TrapM      = 0;
    pm_mretM      = 0;
    pm_sretM      = 0;
    pm_DelegateM  = 0;
    pm_STATUS_MPP = P.M_MODE;
    pm_STATUS_SPP = 1'b0;
    pm_StallW     = 0;
  endtask

  // Rising-edge helper: wait for the next positive clock edge then settle.
  task automatic tick();
    @(posedge clk);
    #1; // let combinational logic settle after edge
  endtask

  // Apply reset for two cycles.
  task automatic do_reset();
    pm_reset = 1;
    @(posedge clk); #1;
    @(posedge clk); #1;
    pm_reset = 0;
  endtask

  // ── Part 1: csrharden combinational tests ─────────────────────────────────────
  task automatic test_csrharden;
    // All inputs zero → all SecFaultM bits zero
    ch_PrivModeSecFaultW = 0; ch_PrivModeUncorrectableFaultW = 0;
    ch_MppReservedM = 0; ch_IllegalCSRAccessM = 0; ch_InstrValidM = 0;
    #1;
    check("csrharden all-zero [0]",   ch_SecFaultM[0] == 0);
    check("csrharden all-zero [1]",   ch_SecFaultM[1] == 0);
    check("csrharden all-zero [2]",   ch_SecFaultM[2] == 0);
    check("csrharden all-zero [3]",   ch_SecFaultM[3] == 0);
    check("csrharden all-zero [6:4]", ch_SecFaultM[6:4] == 3'b0);

    // PrivModeSecFaultW=1 → SecFaultM[0]=1, others 0
    ch_PrivModeSecFaultW = 1; ch_PrivModeUncorrectableFaultW = 0;
    ch_MppReservedM = 0; ch_IllegalCSRAccessM = 0; ch_InstrValidM = 0;
    #1;
    check("csrharden PrivModeSecFaultW→[0]",    ch_SecFaultM[0] == 1);
    check("csrharden PrivModeSecFaultW→[1]=0",  ch_SecFaultM[1] == 0);
    check("csrharden PrivModeSecFaultW→[2]=0",  ch_SecFaultM[2] == 0);
    check("csrharden PrivModeSecFaultW→[3]=0",  ch_SecFaultM[3] == 0);
    check("csrharden PrivModeSecFaultW→[6:4]=0",ch_SecFaultM[6:4] == 3'b0);

    // PrivModeUncorrectableFaultW=1 → SecFaultM[3]=1, others 0
    ch_PrivModeSecFaultW = 0; ch_PrivModeUncorrectableFaultW = 1;
    ch_MppReservedM = 0; ch_IllegalCSRAccessM = 0; ch_InstrValidM = 0;
    #1;
    check("csrharden UncorrFault→[0]=0",  ch_SecFaultM[0] == 0);
    check("csrharden UncorrFault→[3]",    ch_SecFaultM[3] == 1);
    check("csrharden UncorrFault→[6:4]=0",ch_SecFaultM[6:4] == 3'b0);

    // MppReservedM=1 → SecFaultM[1]=1, others 0
    ch_PrivModeSecFaultW = 0; ch_PrivModeUncorrectableFaultW = 0;
    ch_MppReservedM = 1; ch_IllegalCSRAccessM = 0; ch_InstrValidM = 0;
    #1;
    check("csrharden MppReserved→[0]=0",   ch_SecFaultM[0] == 0);
    check("csrharden MppReserved→[1]",     ch_SecFaultM[1] == 1);
    check("csrharden MppReserved→[2]=0",   ch_SecFaultM[2] == 0);
    check("csrharden MppReserved→[3]=0",   ch_SecFaultM[3] == 0);
    check("csrharden MppReserved→[6:4]=0", ch_SecFaultM[6:4] == 3'b0);

    // IllegalCSRAccess=1 & InstrValid=1 → SecFaultM[2]=1
    ch_PrivModeSecFaultW = 0; ch_PrivModeUncorrectableFaultW = 0;
    ch_MppReservedM = 0; ch_IllegalCSRAccessM = 1; ch_InstrValidM = 1;
    #1;
    check("csrharden IllegalCSR+Valid→[2]",   ch_SecFaultM[2] == 1);
    check("csrharden IllegalCSR+Valid→[0]=0", ch_SecFaultM[0] == 0);
    check("csrharden IllegalCSR+Valid→[1]=0", ch_SecFaultM[1] == 0);
    check("csrharden IllegalCSR+Valid→[3]=0", ch_SecFaultM[3] == 0);

    // IllegalCSRAccess=1 & InstrValid=0 → SecFaultM[2]=0 (gate works)
    ch_PrivModeSecFaultW = 0; ch_PrivModeUncorrectableFaultW = 0;
    ch_MppReservedM = 0; ch_IllegalCSRAccessM = 1; ch_InstrValidM = 0;
    #1;
    check("csrharden IllegalCSR+!Valid→[2]=0", ch_SecFaultM[2] == 0);

    // All faults simultaneously → SecFaultM[3:0]=4'b1111
    ch_PrivModeSecFaultW = 1; ch_PrivModeUncorrectableFaultW = 1;
    ch_MppReservedM = 1; ch_IllegalCSRAccessM = 1; ch_InstrValidM = 1;
    #1;
    check("csrharden all-fault [3:0]=4'b1111",  ch_SecFaultM[3:0] == 4'b1111);
    check("csrharden all-fault [6:4]=0",         ch_SecFaultM[6:4] == 3'b0);

    // SecFaultM[6:4] must always be 0
    ch_PrivModeSecFaultW = 1; ch_PrivModeUncorrectableFaultW = 0;
    ch_MppReservedM = 0; ch_IllegalCSRAccessM = 0; ch_InstrValidM = 1;
    #1;
    check("csrharden reserved bits 1", ch_SecFaultM[6:4] == 3'b0);

    ch_PrivModeSecFaultW = 0; ch_PrivModeUncorrectableFaultW = 1;
    ch_MppReservedM = 1; ch_IllegalCSRAccessM = 1; ch_InstrValidM = 1;
    #1;
    check("csrharden reserved bits 2", ch_SecFaultM[6:4] == 3'b0);

    // Restore to zero
    ch_PrivModeSecFaultW = 0; ch_PrivModeUncorrectableFaultW = 0;
    ch_MppReservedM = 0; ch_IllegalCSRAccessM = 0; ch_InstrValidM = 0;
  endtask

  // ── Part 2: privmode functional path tests ────────────────────────────────────
  task automatic test_privmode_functional;

    // ------------------------------------------------------------------
    // Test 1: Reset → M_MODE, no fault
    // ------------------------------------------------------------------
    pm_idle();
    do_reset();
    check("reset: PrivilegeModeW == M_MODE",     pm_PrivilegeModeW == P.M_MODE);
    check("reset: PrivModeSecFaultW == 0",       pm_PrivModeSecFaultW == 0);
    check("reset: PrivModeUncorrFaultW == 0",    pm_PrivModeUncorrectableFaultW == 0);

    // ------------------------------------------------------------------
    // Test 2: Normal hold — mode holds across multiple clocks
    // ------------------------------------------------------------------
    pm_idle();
    tick(); check("hold clk1: still M_MODE",   pm_PrivilegeModeW == P.M_MODE);
    tick(); check("hold clk2: still M_MODE",   pm_PrivilegeModeW == P.M_MODE);
    tick(); check("hold clk3: still M_MODE",   pm_PrivilegeModeW == P.M_MODE);
    check("hold: no fault",                    pm_PrivModeSecFaultW == 0);
    check("hold: no uncorr fault",             pm_PrivModeUncorrectableFaultW == 0);

    // ------------------------------------------------------------------
    // Test 3: TrapM + no DelegateM → next cycle M_MODE
    // ------------------------------------------------------------------
    pm_idle();
    pm_TrapM     = 1;
    pm_DelegateM = 0;
    tick();
    pm_TrapM = 0;
    check("trap no-deleg: M_MODE",    pm_PrivilegeModeW == P.M_MODE);
    check("trap no-deleg: no fault",  pm_PrivModeSecFaultW == 0);

    // ------------------------------------------------------------------
    // Test 4: TrapM + DelegateM=1 → next cycle S_MODE
    // ------------------------------------------------------------------
    pm_idle();
    pm_TrapM     = 1;
    pm_DelegateM = 1;
    tick();
    pm_TrapM     = 0;
    pm_DelegateM = 0;
    check("trap deleg: S_MODE",   pm_PrivilegeModeW == P.S_MODE);
    check("trap deleg: no fault", pm_PrivModeSecFaultW == 0);

    // ------------------------------------------------------------------
    // Test 5: mretM with STATUS_MPP=M_MODE → M_MODE
    // ------------------------------------------------------------------
    pm_idle();
    pm_mretM      = 1;
    pm_STATUS_MPP = P.M_MODE;
    tick();
    pm_mretM = 0;
    check("mret MPP=M: M_MODE",   pm_PrivilegeModeW == P.M_MODE);
    check("mret MPP=M: no fault", pm_PrivModeSecFaultW == 0);

    // ------------------------------------------------------------------
    // Test 6: mretM with STATUS_MPP=S_MODE → S_MODE
    // ------------------------------------------------------------------
    pm_idle();
    pm_mretM      = 1;
    pm_STATUS_MPP = P.S_MODE;
    tick();
    pm_mretM = 0;
    check("mret MPP=S: S_MODE",   pm_PrivilegeModeW == P.S_MODE);
    check("mret MPP=S: no fault", pm_PrivModeSecFaultW == 0);

    // ------------------------------------------------------------------
    // Test 7: mretM with STATUS_MPP=U_MODE → U_MODE
    // ------------------------------------------------------------------
    pm_idle();
    pm_mretM      = 1;
    pm_STATUS_MPP = P.U_MODE;
    tick();
    pm_mretM = 0;
    check("mret MPP=U: U_MODE",   pm_PrivilegeModeW == P.U_MODE);
    check("mret MPP=U: no fault", pm_PrivModeSecFaultW == 0);

    // ------------------------------------------------------------------
    // Test 8: mretM with STATUS_MPP=2'b10 (reserved) → must be M_MODE
    //         The IllegalNextPriv filter forces M_MODE before storing.
    // ------------------------------------------------------------------
    pm_idle();
    pm_mretM      = 1;
    pm_STATUS_MPP = 2'b10;   // reserved encoding
    tick();
    pm_mretM = 0;
    check("mret MPP=reserved: not 2'b10",    pm_PrivilegeModeW != 2'b10);
    check("mret MPP=reserved: is M_MODE",    pm_PrivilegeModeW == P.M_MODE);
    check("mret MPP=reserved: no fault",     pm_PrivModeSecFaultW == 0);

    // ------------------------------------------------------------------
    // Test 9: sretM with STATUS_SPP=0 → U_MODE (2'b00)
    // ------------------------------------------------------------------
    pm_idle();
    do_reset();
    pm_sretM      = 1;
    pm_STATUS_SPP = 1'b0;
    tick();
    pm_sretM = 0;
    check("sret SPP=0: U_MODE",   pm_PrivilegeModeW == P.U_MODE);
    check("sret SPP=0: no fault", pm_PrivModeSecFaultW == 0);

    // ------------------------------------------------------------------
    // Test 10: sretM with STATUS_SPP=1 → S_MODE (2'b01)
    // ------------------------------------------------------------------
    pm_idle();
    do_reset();
    pm_sretM      = 1;
    pm_STATUS_SPP = 1'b1;
    tick();
    pm_sretM = 0;
    check("sret SPP=1: S_MODE",   pm_PrivilegeModeW == P.S_MODE);
    check("sret SPP=1: no fault", pm_PrivModeSecFaultW == 0);

    // ------------------------------------------------------------------
    // Test 11: StallW=1 — mode holds even if TrapM would change it
    // ------------------------------------------------------------------
    // Get to U_MODE first
    pm_idle();
    do_reset();
    pm_mretM      = 1;
    pm_STATUS_MPP = P.U_MODE;
    tick();
    pm_mretM = 0;
    check("stall setup: U_MODE", pm_PrivilegeModeW == P.U_MODE);

    // Now stall; apply TrapM — should NOT transition
    pm_StallW = 1;
    pm_TrapM  = 1;
    tick();
    pm_TrapM  = 0;
    pm_StallW = 0;
    check("stall+trap: still U_MODE",  pm_PrivilegeModeW == P.U_MODE);
    check("stall: no fault",           pm_PrivModeSecFaultW == 0);

    // ------------------------------------------------------------------
    // Test 12: PrivModeSecFaultW=0 throughout normal operation (final sweep)
    // ------------------------------------------------------------------
    pm_idle();
    do_reset();
    pm_mretM = 1; pm_STATUS_MPP = P.S_MODE; tick(); pm_mretM = 0;
    check("normal seq S: no corr fault",   pm_PrivModeSecFaultW == 0);
    check("normal seq S: no uncorr fault", pm_PrivModeUncorrectableFaultW == 0);
    pm_mretM = 1; pm_STATUS_MPP = P.U_MODE; tick(); pm_mretM = 0;
    check("normal seq U: no corr fault",   pm_PrivModeSecFaultW == 0);
    check("normal seq U: no uncorr fault", pm_PrivModeUncorrectableFaultW == 0);
    pm_TrapM = 1; pm_DelegateM = 0; tick(); pm_TrapM = 0; pm_DelegateM = 0;
    check("normal seq trap: no corr fault",   pm_PrivModeSecFaultW == 0);
    check("normal seq trap: no uncorr fault", pm_PrivModeUncorrectableFaultW == 0);

  endtask

  // ── Part 3: Adversarial fault injection ────────────────────────────────────────
  task automatic test_fault_injection;

    // ------------------------------------------------------------------
    // Test A: Single-copy data corruption (S_MODE encoding in U_MODE copy)
    //   System is in U_MODE. Force priv_mode_a to 2'b01 (S_MODE).
    //   priv_chk_a still holds 2'b00 (U_MODE) → data != check → copy A invalid.
    //   Copies B and C are valid and agree on U_MODE → correctable fault.
    //   PrivilegeModeW = U_MODE (previous correct state, NOT M_MODE).
    // ------------------------------------------------------------------

    pm_idle();
    do_reset();
    pm_mretM      = 1;
    pm_STATUS_MPP = P.U_MODE;
    tick();
    pm_mretM = 0;
    tick(); // extra settle cycle
    check("single-copy setup: U_MODE", pm_PrivilegeModeW == P.U_MODE);

    force dut_privmode.privmode.priv_mode_a = 2'b01;
    #1;
    check("single-copy fault: PrivModeSecFaultW=1",            pm_PrivModeSecFaultW == 1);
    check("single-copy fault: UncorrFaultW=0",                 pm_PrivModeUncorrectableFaultW == 0);
    check("single-copy fault: PrivilegeModeW=U_MODE",          pm_PrivilegeModeW == P.U_MODE);
    check("single-copy fault: not reserved",                   pm_PrivilegeModeW != 2'b10);

    // Release and let self-correction fire — all three copies restore to U_MODE
    release dut_privmode.privmode.priv_mode_a;
    @(posedge clk); #1;
    check("single-copy corrected: no fault",   pm_PrivModeSecFaultW == 0);
    check("single-copy corrected: U_MODE",     pm_PrivilegeModeW == P.U_MODE);

    // ------------------------------------------------------------------
    // Test B: U→M blind-spot attack (THIS WAS UNDETECTABLE WITH XOR PARITY)
    //   Flip both bits of copy A from 2'b00 (U_MODE) to 2'b11 (M_MODE).
    //   XOR parity: both have parity 0 — this attack was invisible before.
    //   With redundant check bits: priv_chk_a still holds 2'b00,
    //   priv_mode_a = 2'b11 → data != check → copy A invalid → B+C win.
    //   PrivilegeModeW = U_MODE — attacker gets nothing.
    // ------------------------------------------------------------------

    pm_idle();
    do_reset();
    pm_mretM      = 1;
    pm_STATUS_MPP = P.U_MODE;
    tick();
    pm_mretM = 0;
    tick();
    check("U->M attack setup: U_MODE", pm_PrivilegeModeW == P.U_MODE);

    force dut_privmode.privmode.priv_mode_a = 2'b11;   // M_MODE value, parity=0 same as U_MODE
    #1;
    check("U->M attack: PrivModeSecFaultW=1",    pm_PrivModeSecFaultW == 1);
    check("U->M attack: UncorrFaultW=0",         pm_PrivModeUncorrectableFaultW == 0);
    check("U->M attack: PrivilegeModeW=U_MODE",  pm_PrivilegeModeW == P.U_MODE); // attacker fails
    check("U->M attack: NOT M_MODE",             pm_PrivilegeModeW != P.M_MODE);

    release dut_privmode.privmode.priv_mode_a;
    @(posedge clk); #1;
    check("U->M attack corrected: no fault", pm_PrivModeSecFaultW == 0);
    check("U->M attack corrected: U_MODE",   pm_PrivilegeModeW == P.U_MODE);

    // ------------------------------------------------------------------
    // Test C: Reserved encoding glitch on one copy
    //   Force priv_mode_a to 2'b10 (reserved). priv_chk_a holds U_MODE.
    //   data != check AND data == 2'b10 → copy A invalid.
    //   B+C vote U_MODE → correctable fault, output = U_MODE.
    // ------------------------------------------------------------------

    pm_idle();
    do_reset();
    pm_mretM      = 1;
    pm_STATUS_MPP = P.U_MODE;
    tick();
    pm_mretM = 0;
    tick();
    check("reserved-glitch setup: U_MODE", pm_PrivilegeModeW == P.U_MODE);

    force dut_privmode.privmode.priv_mode_a = 2'b10;
    #1;
    check("reserved-glitch: PrivModeSecFaultW=1",    pm_PrivModeSecFaultW == 1);
    check("reserved-glitch: UncorrFaultW=0",         pm_PrivModeUncorrectableFaultW == 0);
    check("reserved-glitch: PrivilegeModeW=U_MODE",  pm_PrivilegeModeW == P.U_MODE);
    check("reserved-glitch: never reserved",         pm_PrivilegeModeW != 2'b10);

    release dut_privmode.privmode.priv_mode_a;
    @(posedge clk); #1;
    check("reserved-glitch corrected: no fault", pm_PrivModeSecFaultW == 0);
    check("reserved-glitch corrected: U_MODE",   pm_PrivilegeModeW == P.U_MODE);

    // ------------------------------------------------------------------
    // Test D: Single-copy fault while in S_MODE
    //   System in S_MODE. Force priv_mode_a to 2'b00 (U_MODE).
    //   priv_chk_a holds S_MODE (2'b01) → data != check → invalid.
    //   B+C vote S_MODE → correctable fault, output = S_MODE (not M_MODE).
    // ------------------------------------------------------------------

    pm_idle();
    do_reset();
    pm_mretM      = 1;
    pm_STATUS_MPP = P.S_MODE;
    tick();
    pm_mretM = 0;
    tick();
    check("S_MODE fault setup: S_MODE", pm_PrivilegeModeW == P.S_MODE);

    force dut_privmode.privmode.priv_mode_a = 2'b00;
    #1;
    check("S_MODE fault: PrivModeSecFaultW=1",    pm_PrivModeSecFaultW == 1);
    check("S_MODE fault: UncorrFaultW=0",         pm_PrivModeUncorrectableFaultW == 0);
    check("S_MODE fault: PrivilegeModeW=S_MODE",  pm_PrivilegeModeW == P.S_MODE);
    check("S_MODE fault: never reserved",         pm_PrivilegeModeW != 2'b10);

    release dut_privmode.privmode.priv_mode_a;
    @(posedge clk); #1;
    check("S_MODE fault corrected: no fault", pm_PrivModeSecFaultW == 0);
    check("S_MODE fault corrected: S_MODE",   pm_PrivilegeModeW == P.S_MODE);

    // ------------------------------------------------------------------
    // Test E: Uncorrectable fault — all three copies simultaneously corrupted
    //   Force all three data copies to reserved/wrong values.
    //   No valid copies → no majority → UncorrectableFaultW=1.
    //   Fallback output = U_MODE (minimum privilege, not M_MODE).
    // ------------------------------------------------------------------

    pm_idle();
    do_reset();
    pm_mretM      = 1;
    pm_STATUS_MPP = P.U_MODE;
    tick();
    pm_mretM = 0;
    tick();
    check("uncorr setup: U_MODE", pm_PrivilegeModeW == P.U_MODE);

    // Force all three data copies to reserved encoding (check flops hold U_MODE)
    force dut_privmode.privmode.priv_mode_a = 2'b10;
    force dut_privmode.privmode.priv_mode_b = 2'b10;
    force dut_privmode.privmode.priv_mode_c = 2'b10;
    #1;
    check("uncorr fault: PrivModeUncorrFaultW=1",    pm_PrivModeUncorrectableFaultW == 1);
    check("uncorr fault: PrivModeSecFaultW=0",       pm_PrivModeSecFaultW == 0);
    check("uncorr fault: fallback=U_MODE",           pm_PrivilegeModeW == P.U_MODE);
    check("uncorr fault: never reserved",            pm_PrivilegeModeW != 2'b10);

    release dut_privmode.privmode.priv_mode_a;
    release dut_privmode.privmode.priv_mode_b;
    release dut_privmode.privmode.priv_mode_c;

  endtask

  // ── Main ──────────────────────────────────────────────────────────────────────
  initial begin
    fail_count = 0;

    // Initialize all inputs
    ch_PrivModeSecFaultW           = 0;
    ch_PrivModeUncorrectableFaultW = 0;
    ch_MppReservedM                = 0;
    ch_IllegalCSRAccessM           = 0;
    ch_InstrValidM                 = 0;

    pm_reset      = 0;
    pm_StallW     = 0;
    pm_TrapM      = 0;
    pm_mretM      = 0;
    pm_sretM      = 0;
    pm_DelegateM  = 0;
    pm_STATUS_MPP = 2'b11;
    pm_STATUS_SPP = 1'b0;

    #1;

    test_csrharden();
    test_privmode_functional();
    test_fault_injection();

    if (fail_count == 0) begin
      $display("CSR HARDENING SELF-TEST PASSED");
      $finish(0);
    end else begin
      $display("CSR HARDENING SELF-TEST FAILED (%0d failures)", fail_count);
      $fatal(1);
    end
  end

endmodule
