///////////////////////////////////////////
// regfile.sv
//
// Written: David_Harris@hmc.edu, Sarah.Harris@unlv.edu
// Created: 9 January 2021
// Modified: Saipranavvk saipranavvk@gmail.com 4 September 2026
//           ECC hardening: register storage upgraded to full SECDED codewords.
//           Each entry stores XLEN + R + 1 bits so that a single-bit upset in
//           the array is corrected transparently on the next read.  Two
//           ecc_bit_flip instances (one per read port) inject pseudo-random
//           single-bit errors when inject_en is asserted, allowing the ECC
//           correction path to be exercised in simulation and DFT.
//
// Purpose: 3-port register file with SECDED error correction
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

module regfile #(parameter XLEN, E_SUPPORTED) (
  input  logic             clk, reset,
  input  logic             we3,
  input  logic [4:0]       a1, a2, a3,
  input  logic [XLEN-1:0]  wd3,
  output logic [XLEN-1:0]  rd1, rd2,
  input  logic             inject_en,
  output logic             sec_err_rd1, ded_err_rd1,
  output logic             sec_err_rd2, ded_err_rd2
);

  localparam NUMREGS = E_SUPPORTED ? 16 : 32;

  // SECDED check-bit count and total codeword width
  localparam int R  = (XLEN <=   1) ? 2 :
                      (XLEN <=   4) ? 3 :
                      (XLEN <=  11) ? 4 :
                      (XLEN <=  26) ? 5 :
                      (XLEN <=  57) ? 6 :
                      (XLEN <= 120) ? 7 : 8;
  localparam int CW = XLEN + R + 1;  // e.g. 64+7+1 = 72 for RV64

  // Storage array holds encoded codewords.
  // All-zeros is the valid SECDED codeword for data=0 (Hamming bits and
  // overall parity are all 0 when data is 0), so reset to '0 is correct.
  logic [CW-1:0] rf [NUMREGS-1:1];
  integer i;

  // ── Write path ────────────────────────────────────────────────────────────────
  // Encode wd3 combinationally, then latch the codeword on the falling clock edge.
  logic [CW-1:0] cw_wr3;
  ecc_secded_enc #(.DATA_WIDTH(XLEN)) enc_wr (.data_i(wd3), .codeword_o(cw_wr3));

  always_ff @(negedge clk)
    if (reset) for (i = 1; i < NUMREGS; i++) rf[i] <= '0;
    else       if (we3 & (a3 != '0))          rf[a3] <= cw_wr3;

  // ── Read port 1 ───────────────────────────────────────────────────────────────
  logic [CW-1:0] cw_rd1_raw, cw_rd1_inj;

  assign cw_rd1_raw = (a1 != '0) ? rf[a1] : '0;

  ecc_bit_flip  #(.CW_WIDTH(CW)) inj1 (
    .clk, .reset, .inject_en,
    .codeword_i(cw_rd1_raw),
    .codeword_o(cw_rd1_inj)
  );

  ecc_secded_dec #(.DATA_WIDTH(XLEN)) dec1 (
    .codeword_i(cw_rd1_inj),
    .data_o    (rd1),
    .sec_err_o (sec_err_rd1),
    .ded_err_o (ded_err_rd1)
  );

  // ── Read port 2 ───────────────────────────────────────────────────────────────
  logic [CW-1:0] cw_rd2_raw, cw_rd2_inj;

  assign cw_rd2_raw = (a2 != '0) ? rf[a2] : '0;

  ecc_bit_flip  #(.CW_WIDTH(CW)) inj2 (
    .clk, .reset, .inject_en,
    .codeword_i(cw_rd2_raw),
    .codeword_o(cw_rd2_inj)
  );

  ecc_secded_dec #(.DATA_WIDTH(XLEN)) dec2 (
    .codeword_i(cw_rd2_inj),
    .data_o    (rd2),
    .sec_err_o (sec_err_rd2),
    .ded_err_o (ded_err_rd2)
  );

endmodule
