///////////////////////////////////////////
// ecc_dected_enc.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 26 August 2026
// Modified:
//
// Purpose: Parameterizable DECTED (Double Error Correction, Triple Error
//          Detection) encoder using a BCH(2) code over GF(2^M).  Appends
//          2*M+1 check bits; output is {data_i, overall_parity, s3, s1}
//          (check bits in LSB).
//
// BCH(2) parity-check matrix:
//   H1[k][i] = bit k of alpha^(i+1)         -- first M parity rows (s1)
//   H3[k][i] = bit k of alpha^(3*(i+1)%N)   -- second M parity rows (s3)
//
// Alpha powers are computed as a cascaded assign chain (shift-reduce by POLY).
// Each s1[k]/s3[k] bit is an XOR reduction driven by genvar-indexed assigns,
// so Verilator can resolve constant array-element dependencies without
// flagging false circular paths.
//
// Overall parity covers all codeword bits so total parity = 0 for valid words.
//
// M breakpoints from 2^M - 1 - 2*M >= DATA_WIDTH:
//   M=3->1, M=4->7, M=5->21, M=6->51, M=7->113, M=8->239, M=9->493
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

module ecc_dected_enc #(
  parameter int DATA_WIDTH = 64,
  // smallest M s.t. 2^M - 1 - 2*M >= DATA_WIDTH
  parameter int M = (DATA_WIDTH <=   1) ? 3 :
                    (DATA_WIDTH <=   7) ? 4 :
                    (DATA_WIDTH <=  21) ? 5 :
                    (DATA_WIDTH <=  51) ? 6 :
                    (DATA_WIDTH <= 113) ? 7 :
                    (DATA_WIDTH <= 239) ? 8 :
                    (DATA_WIDTH <= 493) ? 9 : 10,
  // primitive polynomial lower M bits (x^M term implicit)
  parameter int POLY = (M == 3) ?  3 : (M == 4) ?  3 : (M == 5) ?  5 :
                       (M == 6) ?  3 : (M == 7) ?  9 : (M == 8) ? 29 :
                       (M == 9) ? 17 : 9   // M==10
) (
  input  logic [DATA_WIDTH-1:0]    data_i,
  // layout MSB->LSB: data_i | overall_parity | s3[M-1:0] | s1[M-1:0]
  output logic [DATA_WIDTH+2*M:0]  codeword_o
);

  localparam int N = (1 << M) - 1;

  // ── GF(2^M) alpha power table ──────────────────────────────────────────────
  // alpha_pow[k] = alpha^k for k = 0..N-1.  Each entry is one shift-and-reduce
  // of the previous.  This forms a feedforward chain; Verilator conservatively
  // reports UNOPTFLAT because it treats the whole array as one signal node.
  /* verilator lint_off UNOPTFLAT */
  logic [M-1:0] alpha_pow [0:N-1];

  assign alpha_pow[0] = M'(1);

  for (genvar ai = 0; ai < N - 1; ai++) begin : gen_alpha
    assign alpha_pow[ai+1] =
        {alpha_pow[ai][M-2:0], 1'b0} ^
        ({M{alpha_pow[ai][M-1]}} & M'(POLY));
  end
  /* verilator lint_on UNOPTFLAT */

  // ── s1 parity bits ──────────────────────────────────────────────────────────
  // s1[k] = XOR over all data bits di where alpha^(di+1) has bit k set.
  // Both k and di are genvars, so alpha_pow[di+1][k] is a constant-indexed bit.
  logic [M-1:0] s1;

  for (genvar k = 0; k < M; k++) begin : gen_s1
    logic [DATA_WIDTH-1:0] s1_bits;
    for (genvar di = 0; di < DATA_WIDTH; di++) begin : gen_s1_di
      assign s1_bits[di] = alpha_pow[di + 1][k] & data_i[di];
    end
    assign s1[k] = ^s1_bits;
  end

  // ── s3 parity bits ──────────────────────────────────────────────────────────
  // s3[k] = XOR over all data bits di where alpha^(3*(di+1) mod N) has bit k set.
  logic [M-1:0] s3;

  for (genvar k = 0; k < M; k++) begin : gen_s3
    logic [DATA_WIDTH-1:0] s3_bits;
    for (genvar di = 0; di < DATA_WIDTH; di++) begin : gen_s3_di
      localparam int IDX3 = (3 * (di + 1)) % N;
      assign s3_bits[di] = alpha_pow[IDX3][k] & data_i[di];
    end
    assign s3[k] = ^s3_bits;
  end

  // Overall parity covers all codeword bits; total codeword parity = 0 for
  // a valid word (required by decoder's no-error condition: syn1==0, P==0).
  logic overall_parity;
  assign overall_parity = ^data_i ^ ^s1 ^ ^s3;

  assign codeword_o = {data_i, overall_parity, s3, s1};

endmodule
