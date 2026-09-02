///////////////////////////////////////////
// ecc_dected_dec.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 26 August 2026
// Modified:
//
// Purpose: Parameterizable DECTED (Double Error Correction, Triple Error
//          Detection) decoder for the BCH(2) code produced by
//          ecc_dected_enc.  Recomputes syndromes, classifies the error
//          pattern, and corrects up to two bit errors via parallel Chien
//          search and a MUX.
//
// Classification (S1=syn1, P=overall parity):
//   S1==0, P==0: no error
//   S1==0, P==1: overall-parity-bit error (data intact)
//   S1!=0, S3==S1^3, P==1: single error -> SEC (correct)
//   S1!=0, S3!=S1^3, P==0: double error -> DEC (correct)
//   S1!=0, S3==S1^3, P==0: triple error -> TED (detect only)
//   S1!=0, S3!=S1^3, P==1: triple error -> TED (detect only)
//
// All GF(2^M) runtime arithmetic uses always_comb blocks with local
// variables — no arrays used as intermediate nodes — avoiding Verilator's
// UNOPTFLAT false-positive on feedforward chains.  The alpha_pow array
// itself is the only residual feedforward chain; it is suppressed with a
// targeted lint_off.
//
// No user-defined functions, no automatic, no tasks.
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

module ecc_dected_dec #(
  parameter int DATA_WIDTH = 64,
  parameter int M = (DATA_WIDTH <=   1) ? 3 :
                    (DATA_WIDTH <=   7) ? 4 :
                    (DATA_WIDTH <=  21) ? 5 :
                    (DATA_WIDTH <=  51) ? 6 :
                    (DATA_WIDTH <= 113) ? 7 :
                    (DATA_WIDTH <= 239) ? 8 :
                    (DATA_WIDTH <= 493) ? 9 : 10,
  parameter int POLY = (M == 3) ?  3 : (M == 4) ?  3 : (M == 5) ?  5 :
                       (M == 6) ?  3 : (M == 7) ?  9 : (M == 8) ? 29 :
                       (M == 9) ? 17 : 9
) (
  input  logic [DATA_WIDTH+2*M:0]   codeword_i,
  output logic [DATA_WIDTH-1:0]     data_o,
  output logic                      sec_err_o,
  output logic                      dec_err_o,
  output logic                      ted_err_o
);

  localparam int N          = (1 << M) - 1;
  localparam int CHECK_BITS = 2 * M + 1;
  localparam int CW_WIDTH   = DATA_WIDTH + CHECK_BITS;

  // ── Unpack received codeword ───────────────────────────────────────────────
  logic [M-1:0]          s1_rx, s3_rx;
  logic [DATA_WIDTH-1:0] data_rx;

  assign s1_rx   = codeword_i[M-1:0];
  assign s3_rx   = codeword_i[2*M-1:M];
  assign data_rx = codeword_i[CW_WIDTH-1 : CHECK_BITS];

  // ── GF(2^M) alpha power table ──────────────────────────────────────────────
  // alpha_pow[k] = alpha^k, k = 0..N-1.  Feedforward chain; Verilator
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

  // ── Recompute s1_exp, s3_exp from received data ────────────────────────────
  // Genvar-indexed assigns: alpha_pow[constant][constant] per bit — no runtime
  // array access, so Verilator can resolve each element dependency precisely.
  logic [M-1:0] s1_exp, s3_exp;

  for (genvar k = 0; k < M; k++) begin : gen_s1e
    logic [DATA_WIDTH-1:0] s1e_bits;
    for (genvar di = 0; di < DATA_WIDTH; di++) begin : gen_s1e_di
      assign s1e_bits[di] = alpha_pow[di + 1][k] & data_rx[di];
    end
    assign s1_exp[k] = ^s1e_bits;
  end

  for (genvar k = 0; k < M; k++) begin : gen_s3e
    logic [DATA_WIDTH-1:0] s3e_bits;
    for (genvar di = 0; di < DATA_WIDTH; di++) begin : gen_s3e_di
      localparam int IDX3 = (3 * (di + 1)) % N;
      assign s3e_bits[di] = alpha_pow[IDX3][k] & data_rx[di];
    end
    assign s3_exp[k] = ^s3e_bits;
  end

  // ── Net syndromes and overall parity ──────────────────────────────────────
  logic [M-1:0] syn1, syn3;
  logic         parity;

  assign syn1   = s1_rx ^ s1_exp;
  assign syn3   = s3_rx ^ s3_exp;
  assign parity = ^codeword_i;

  // ── syn1^2 = syn1 * syn1 ──────────────────────────────────────────────────
  // Shift-accumulate GF multiply: sh starts at syn1; for each bit of the
  // multiplier that is set, XOR sh into the result; then advance sh by alpha.
  logic [M-1:0] syn1_sq;
  always_comb begin
    logic [M-1:0] r, sh;
    r = '0; sh = syn1;
    for (int bi = 0; bi < M; bi++) begin
      if (syn1[bi]) r = r ^ sh;
      sh = {sh[M-2:0], 1'b0} ^ ({M{sh[M-1]}} & M'(POLY));
    end
    syn1_sq = r;
  end

  // ── syn1^3 = syn1_sq * syn1 ───────────────────────────────────────────────
  logic [M-1:0] syn1_cb;
  always_comb begin
    logic [M-1:0] r, sh;
    r = '0; sh = syn1_sq;
    for (int bi = 0; bi < M; bi++) begin
      if (syn1[bi]) r = r ^ sh;
      sh = {sh[M-2:0], 1'b0} ^ ({M{sh[M-1]}} & M'(POLY));
    end
    syn1_cb = r;
  end

  // ── Error classification ───────────────────────────────────────────────────
  logic syn1_zero, syn3_eq_syn1cb;

  assign syn1_zero      = (syn1 == '0);
  assign syn3_eq_syn1cb = (syn3 == syn1_cb);

  assign sec_err_o = ~syn1_zero &  syn3_eq_syn1cb &  parity;
  assign dec_err_o = ~syn1_zero & ~syn3_eq_syn1cb & ~parity;
  assign ted_err_o = ~syn1_zero & ((syn3_eq_syn1cb & ~parity) |
                                   (~syn3_eq_syn1cb &  parity));

  // ── SEC Chien search ───────────────────────────────────────────────────────
  // Error at data bit di when syn1 == alpha^(di+1).
  logic [DATA_WIDTH-1:0] corr_mask_sec;

  for (genvar di = 0; di < DATA_WIDTH; di++) begin : gen_chien_sec
    assign corr_mask_sec[di] = (syn1 == alpha_pow[di + 1]);
  end

  // ── GF inverse of syn1 via Fermat: syn1^(2^M - 2) ─────────────────────────
  // Recurrence: r = syn1; for M-2 iterations: r = r^2 * syn1; result = r^2.
  // After round i: r = syn1^(2^(i+2) - 1).  After M-2 rounds: syn1^(2^M-1 - 1).
  // Final square: syn1^(2^M - 2) = syn1^(-1) by Fermat's little theorem.
  logic [M-1:0] inv_syn1;
  always_comb begin
    logic [M-1:0] r, sq, sq_sh, ml, ml_sh;
    r = syn1;
    for (int i = 0; i < M - 2; i++) begin
      // sq = r^2
      sq = '0; sq_sh = r;
      for (int bi = 0; bi < M; bi++) begin
        if (r[bi]) sq = sq ^ sq_sh;
        sq_sh = {sq_sh[M-2:0], 1'b0} ^ ({M{sq_sh[M-1]}} & M'(POLY));
      end
      // r = sq * syn1
      ml = '0; ml_sh = sq;
      for (int bi = 0; bi < M; bi++) begin
        if (syn1[bi]) ml = ml ^ ml_sh;
        ml_sh = {ml_sh[M-2:0], 1'b0} ^ ({M{ml_sh[M-1]}} & M'(POLY));
      end
      r = ml;
    end
    // final square: inv_syn1 = r^2
    inv_syn1 = '0;
    sq_sh = r;
    for (int bi = 0; bi < M; bi++) begin
      if (r[bi]) inv_syn1 = inv_syn1 ^ sq_sh;
      sq_sh = {sq_sh[M-2:0], 1'b0} ^ ({M{sq_sh[M-1]}} & M'(POLY));
    end
  end

  // ── sigma2 = (syn3 XOR syn1^3) * inv_syn1 ─────────────────────────────────
  logic [M-1:0] sigma2;
  always_comb begin
    logic [M-1:0] r, sh;
    r = '0; sh = syn3 ^ syn1_cb;
    for (int bi = 0; bi < M; bi++) begin
      if (inv_syn1[bi]) r = r ^ sh;
      sh = {sh[M-2:0], 1'b0} ^ ({M{sh[M-1]}} & M'(POLY));
    end
    sigma2 = r;
  end

  // ── DEC Chien search ───────────────────────────────────────────────────────
  // Evaluate sigma(x) = 1 + syn1*x + sigma2*x^2  at x = alpha^(-(dj+1)).
  // A root means bit dj is in error.
  //
  // Multiply of constant c = alpha^A1_IDX by runtime v: accumulate sh = v
  // whenever the corresponding bit of c is set, advancing sh by one alpha
  // step each iteration.  A1_IDX and A2_IDX are localparams per generate
  // iteration, so alpha_pow[A1_IDX] and alpha_pow[A2_IDX] are constant-
  // indexed reads — no UNOPTFLAT.
  logic [DATA_WIDTH-1:0] corr_mask_dec;

  for (genvar dj = 0; dj < DATA_WIDTH; dj++) begin : gen_chien_dec
    localparam int A1_IDX = N - (dj + 1);
    localparam int A2_IDX = N - ((2 * (dj + 1)) % N);

    always_comb begin
      logic [M-1:0] t1, t1_sh, t2, t2_sh;
      // t1 = syn1 * alpha^(-(dj+1))
      t1 = '0; t1_sh = syn1;
      for (int bi = 0; bi < M; bi++) begin
        if (alpha_pow[A1_IDX][bi]) t1 = t1 ^ t1_sh;
        t1_sh = {t1_sh[M-2:0], 1'b0} ^ ({M{t1_sh[M-1]}} & M'(POLY));
      end
      // t2 = sigma2 * alpha^(-2*(dj+1))
      t2 = '0; t2_sh = sigma2;
      for (int bi = 0; bi < M; bi++) begin
        if (alpha_pow[A2_IDX][bi]) t2 = t2 ^ t2_sh;
        t2_sh = {t2_sh[M-2:0], 1'b0} ^ ({M{t2_sh[M-1]}} & M'(POLY));
      end
      corr_mask_dec[dj] = ((M'(1) ^ t1 ^ t2) == '0);
    end
  end

  // ── Correction MUX ────────────────────────────────────────────────────────
  logic [DATA_WIDTH-1:0] corrected_data;

  always_comb begin
    if (sec_err_o)
      corrected_data = data_rx ^ corr_mask_sec;
    else
      corrected_data = data_rx ^ corr_mask_dec;
  end

  assign data_o = (sec_err_o | dec_err_o) ? corrected_data : data_rx;

endmodule
