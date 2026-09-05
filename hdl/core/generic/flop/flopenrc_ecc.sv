///////////////////////////////////////////
// flopenrc_ecc.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 4 September 2026
// Modified:
//
// Purpose: SECDED-protected D flip-flop with enable, synchronous reset, and
//          enabled clear.  Drop-in data-path replacement for flopenrc with two
//          additional output ports (sec_err_o, ded_err_o) and one additional
//          input port (inject_en).
//
//          Internal pipeline (purely combinational except the storage FF):
//            d[WIDTH-1:0]
//            → ecc_secded_enc  (XOR tree, no FF)
//            → always_ff       (stores CW_WIDTH bits: WIDTH + R + 1)
//            → ecc_bit_flip    (combinational, clocked LFSR inside)
//            → ecc_secded_dec  (syndrome + correction, no FF)
//            → q[WIDTH-1:0], sec_err_o, ded_err_o
//
//          The encoding/decoding adds combinational delay on either side of
//          the flip-flop but does not insert a pipeline stage.
//
//          When inject_en = 0 the ecc_bit_flip module is a wire, so the
//          decode path sees clean (uncorrupted) codewords.  In this case
//          sec_err_o and ded_err_o will always be 0.
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

module flopenrc_ecc #(parameter int WIDTH = 64) (
  input  logic             clk, reset, clear, en,
  input  logic             inject_en,
  input  logic [WIDTH-1:0] d,
  output logic [WIDTH-1:0] q,
  output logic             sec_err_o,
  output logic             ded_err_o
);

  // Number of Hamming check bits for this data width
  localparam int R = (WIDTH <=   1) ? 2 :
                     (WIDTH <=   4) ? 3 :
                     (WIDTH <=  11) ? 4 :
                     (WIDTH <=  26) ? 5 :
                     (WIDTH <=  57) ? 6 :
                     (WIDTH <= 120) ? 7 : 8;

  localparam int CW_WIDTH = WIDTH + R + 1;  // data + R Hamming bits + 1 overall parity

  // ── Encode ────────────────────────────────────────────────────────────────────
  logic [CW_WIDTH-1:0] cw_enc;
  ecc_secded_enc #(.DATA_WIDTH(WIDTH)) enc (.data_i(d), .codeword_o(cw_enc));

  // ── Storage FF (holds CW_WIDTH bits) ─────────────────────────────────────────
  // All-zeros is the valid codeword for data=0 (Hamming bits and parity all 0).
  logic [CW_WIDTH-1:0] cw_stored;

  always_ff @(posedge clk)
    if (reset)       cw_stored <= '0;
    else if (en)
      if (clear)     cw_stored <= '0;
      else           cw_stored <= cw_enc;

  // ── Error injection (optional, gated by inject_en) ───────────────────────────
  logic [CW_WIDTH-1:0] cw_inj;
  ecc_bit_flip #(.CW_WIDTH(CW_WIDTH)) flip (
    .clk, .reset, .inject_en,
    .codeword_i(cw_stored),
    .codeword_o(cw_inj)
  );

  // ── Decode ────────────────────────────────────────────────────────────────────
  ecc_secded_dec #(.DATA_WIDTH(WIDTH)) dec (
    .codeword_i(cw_inj),
    .data_o    (q),
    .sec_err_o,
    .ded_err_o
  );

endmodule
