///////////////////////////////////////////
// privmode.sv
//
// Written: David_Harris@hmc.edu 12 May 2022
// Modified:
//
// Purpose: Track privilege mode.  Change on traps and returns.
//
// Documentation: RISC-V System on Chip Design
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// https://github.com/openhwgroup/cvw
//
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
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

module privmode import cvw::*;  #(parameter cvw_t P) (
  input  logic             clk, reset,
  input  logic             StallW,
  input  logic             TrapM,               // Trap
  input  logic             mretM, sretM,        // return instruction
  input  logic             DelegateM,           // trap delegated to supervisor mode
  input  logic [1:0]       STATUS_MPP,          // machine trap previous privilege mode
  input  logic             STATUS_SPP,          // supervisor trap previous privilege mode
  output logic [1:0]       NextPrivilegeModeM,  // next privilege mode, used when updating STATUS CSR on a trap
  output logic [1:0]       PrivilegeModeW,      // current privilege mode
  output logic             PrivModeSecFaultW,           // TMR correctable fault detected
  output logic             PrivModeUncorrectableFaultW  // TMR uncorrectable fault: no majority consensus
);

  if (P.U_SUPPORTED) begin : privmode
    logic [1:0] NextPrivValid;
    logic [1:0] priv_mode_a, priv_mode_b, priv_mode_c;  // TMR data copies
    logic [1:0] priv_chk_a,  priv_chk_b,  priv_chk_c;   // redundant check copies (written identically)
    logic       valid_a, valid_b, valid_c;
    logic       majority_ab, majority_ac, majority_bc, has_majority, all_ok;
    logic [1:0] voted_mode;
    logic       IllegalNextPriv;

    // PrivilegeMode FSM — hold path uses PrivilegeModeW (voted output) so a TMR
    // fault self-corrects on the next clock edge without escalating privilege.
    always_comb begin
      if (TrapM) begin // Change privilege based on DELEG registers (see 3.1.8)
        if (P.S_SUPPORTED & DelegateM) NextPrivilegeModeM = P.S_MODE;
        else                           NextPrivilegeModeM = P.M_MODE;
      end else if (mretM)              NextPrivilegeModeM = STATUS_MPP;
      else     if (sretM)              NextPrivilegeModeM = {1'b0, STATUS_SPP};
      else                             NextPrivilegeModeM = PrivilegeModeW;
    end

    // Filter reserved encoding 2'b10 before storing
    assign IllegalNextPriv = (NextPrivilegeModeM == 2'b10);
    assign NextPrivValid   = IllegalNextPriv ? P.M_MODE : NextPrivilegeModeM;

    // TMR: three independent data flops + three independent check flops.
    // Check flops are written identically to data flops every cycle.
    // A corrupted copy is detected when data != check (requires 4-bit simultaneous
    // flip to forge a consistent valid-looking copy — blocks U→M 2-bit glitch attacks
    // that bypass XOR parity, since U_MODE and M_MODE share XOR parity = 0).
    flopenl #(2) privmodereg_a(clk, reset, ~StallW, NextPrivValid, P.M_MODE, priv_mode_a);
    flopenl #(2) privmodereg_b(clk, reset, ~StallW, NextPrivValid, P.M_MODE, priv_mode_b);
    flopenl #(2) privmodereg_c(clk, reset, ~StallW, NextPrivValid, P.M_MODE, priv_mode_c);
    flopenl #(2) privchkreg_a (clk, reset, ~StallW, NextPrivValid, P.M_MODE, priv_chk_a);
    flopenl #(2) privchkreg_b (clk, reset, ~StallW, NextPrivValid, P.M_MODE, priv_chk_b);
    flopenl #(2) privchkreg_c (clk, reset, ~StallW, NextPrivValid, P.M_MODE, priv_chk_c);

    // Per-copy validity: data matches check AND not reserved encoding
    assign valid_a = (priv_mode_a == priv_chk_a) & (priv_mode_a != 2'b10);
    assign valid_b = (priv_mode_b == priv_chk_b) & (priv_mode_b != 2'b10);
    assign valid_c = (priv_mode_c == priv_chk_c) & (priv_mode_c != 2'b10);

    // Majority pairs: both copies valid AND they agree on the value
    assign majority_ab  = valid_a & valid_b & (priv_mode_a == priv_mode_b);
    assign majority_ac  = valid_a & valid_c & (priv_mode_a == priv_mode_c);
    assign majority_bc  = valid_b & valid_c & (priv_mode_b == priv_mode_c);
    assign has_majority = majority_ab | majority_ac | majority_bc;
    assign all_ok       = valid_a & valid_b & valid_c &
                          (priv_mode_a == priv_mode_b) & (priv_mode_b == priv_mode_c);

    // Majority voter — returns previous correct state, not M_MODE
    always_comb begin
      if      (majority_ab) voted_mode = priv_mode_a;
      else if (majority_ac) voted_mode = priv_mode_a;
      else if (majority_bc) voted_mode = priv_mode_b;
      else if (valid_a)     voted_mode = priv_mode_a;  // single valid copy
      else if (valid_b)     voted_mode = priv_mode_b;
      else if (valid_c)     voted_mode = priv_mode_c;
      else                  voted_mode = P.U_MODE;     // 0 valid: minimum privilege
    end

    // Correctable: majority consensus exists but something was wrong
    // Uncorrectable: no majority (0/1 valid copies, or valid copies disagree)
    assign PrivModeSecFaultW           = has_majority & ~all_ok;
    assign PrivModeUncorrectableFaultW = ~has_majority;

    // Corrected output — always voted_mode (previous correct state on fault)
    assign PrivilegeModeW = voted_mode;

  end else begin  // only machine mode supported
    assign NextPrivilegeModeM          = P.M_MODE;
    assign PrivilegeModeW              = P.M_MODE;
    assign PrivModeSecFaultW           = 1'b0;
    assign PrivModeUncorrectableFaultW = 1'b0;
  end
endmodule
