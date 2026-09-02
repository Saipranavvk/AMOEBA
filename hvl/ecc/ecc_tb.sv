///////////////////////////////////////////
// ecc_tb.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 26 August 2026
// Modified:
//
// Purpose: Self-checking testbench for ecc_secded_enc/dec and
//          ecc_dected_enc/dec.  Purely combinational; compiled standalone
//          with Verilator via 'make -C sim ecc_test'.
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

module ecc_tb;

  // Codeword widths (verified against module port formulas at DATA_WIDTH=8,64):
  //   SECDED: R=parity_bits_needed(DW),  CW = DW + R + 1
  //     DW=8:  R=4, CW=13
  //     DW=64: R=7, CW=72
  //   DECTED: M=bch_m(DW), CW = DW + 2*M + 1
  //     DW=8:  M=5, CW=19
  //     DW=64: M=7, CW=79
  localparam int SECDED8_CW  = 13;
  localparam int SECDED64_CW = 72;
  localparam int DECTED8_CW  = 19;
  localparam int DECTED64_CW = 79;

  // Check-bit counts (data starts at bit CHECK_BITS in codeword)
  localparam int SECDED8_CB  = 5;   // R+1
  localparam int SECDED64_CB = 8;   // R+1
  localparam int DECTED8_CB  = 11;  // 2*M+1
  localparam int DECTED64_CB = 15;  // 2*M+1

  // ── SECDED 8-bit ─────────────────────────────────────────────────────────────
  logic [7:0]             s8_data_in;
  logic [SECDED8_CW-1:0]  s8_codeword, s8_codeword_err;
  logic [7:0]             s8_data_out;
  logic                   s8_sec, s8_ded;

  ecc_secded_enc #(.DATA_WIDTH(8))  u_sec_enc8  (.data_i(s8_data_in),  .codeword_o(s8_codeword));
  ecc_secded_dec #(.DATA_WIDTH(8))  u_sec_dec8  (.codeword_i(s8_codeword_err), .data_o(s8_data_out),
                                                  .sec_err_o(s8_sec), .ded_err_o(s8_ded));

  // ── SECDED 64-bit ────────────────────────────────────────────────────────────
  logic [63:0]            s64_data_in;
  logic [SECDED64_CW-1:0] s64_codeword, s64_codeword_err;
  logic [63:0]            s64_data_out;
  logic                   s64_sec, s64_ded;

  ecc_secded_enc #(.DATA_WIDTH(64)) u_sec_enc64 (.data_i(s64_data_in),  .codeword_o(s64_codeword));
  ecc_secded_dec #(.DATA_WIDTH(64)) u_sec_dec64 (.codeword_i(s64_codeword_err), .data_o(s64_data_out),
                                                  .sec_err_o(s64_sec), .ded_err_o(s64_ded));

  // ── DECTED 8-bit ─────────────────────────────────────────────────────────────
  logic [7:0]             d8_data_in;
  logic [DECTED8_CW-1:0]  d8_codeword, d8_codeword_err;
  logic [7:0]             d8_data_out;
  logic                   d8_sec, d8_dec, d8_ted;

  ecc_dected_enc #(.DATA_WIDTH(8))  u_dec_enc8  (.data_i(d8_data_in),  .codeword_o(d8_codeword));
  ecc_dected_dec #(.DATA_WIDTH(8))  u_dec_dec8  (.codeword_i(d8_codeword_err), .data_o(d8_data_out),
                                                  .sec_err_o(d8_sec), .dec_err_o(d8_dec), .ted_err_o(d8_ted));

  // ── DECTED 64-bit ────────────────────────────────────────────────────────────
  logic [63:0]            d64_data_in;
  logic [DECTED64_CW-1:0] d64_codeword, d64_codeword_err;
  logic [63:0]            d64_data_out;
  logic                   d64_sec, d64_dec, d64_ted;

  ecc_dected_enc #(.DATA_WIDTH(64)) u_dec_enc64 (.data_i(d64_data_in),  .codeword_o(d64_codeword));
  ecc_dected_dec #(.DATA_WIDTH(64)) u_dec_dec64 (.codeword_i(d64_codeword_err), .data_o(d64_data_out),
                                                  .sec_err_o(d64_sec), .dec_err_o(d64_dec), .ted_err_o(d64_ted));

  // ── Helpers ───────────────────────────────────────────────────────────────────
  int fail_count;

  task automatic check(input string label, input bit cond);
    if (!cond) begin
      $display("FAIL: %s", label);
      fail_count++;
    end
  endtask

  // ── SECDED 8-bit tests ────────────────────────────────────────────────────────
  task automatic test_secded8;
    automatic logic [SECDED8_CW-1:0] cw;
    s8_data_in = 8'hA5; #1;
    cw = s8_codeword;

    // no error
    s8_codeword_err = cw; #1;
    check("secded8 no-error data", s8_data_out == 8'hA5);
    check("secded8 no-error sec",  !s8_sec);
    check("secded8 no-error ded",  !s8_ded);

    // single-bit errors: all codeword positions
    // bit SECDED8_CB-1 = overall parity bit: syndrome==0 so sec_err_o not set, data intact
    for (int b = 0; b < SECDED8_CW; b++) begin
      s8_codeword_err = cw ^ (SECDED8_CW'(1) << b); #1;
      if (b != SECDED8_CB-1) begin  // skip overall-parity-only error
        check($sformatf("secded8 SEC b%0d sec", b), s8_sec);
        check($sformatf("secded8 SEC b%0d ded", b), !s8_ded);
      end
      if (b >= SECDED8_CB)
        check($sformatf("secded8 SEC b%0d corrected", b), s8_data_out == 8'hA5);
    end

    // double-bit errors: all pairs (exhaustive for 13-bit codeword)
    for (int b0 = 0; b0 < SECDED8_CW-1; b0++) begin
      for (int b1 = b0+1; b1 < SECDED8_CW; b1++) begin
        s8_codeword_err = cw ^ (SECDED8_CW'(1) << b0) ^ (SECDED8_CW'(1) << b1); #1;
        check($sformatf("secded8 DED (%0d,%0d)", b0, b1), s8_ded && !s8_sec);
      end
    end
  endtask

  // ── SECDED 64-bit tests ───────────────────────────────────────────────────────
  task automatic test_secded64;
    automatic logic [SECDED64_CW-1:0] cw;
    s64_data_in = 64'hDEADBEEFCAFEBABE; #1;
    cw = s64_codeword;

    s64_codeword_err = cw; #1;
    check("secded64 no-error data", s64_data_out == 64'hDEADBEEFCAFEBABE);
    check("secded64 no-error sec",  !s64_sec);
    check("secded64 no-error ded",  !s64_ded);

    for (int b = 0; b < SECDED64_CW; b++) begin
      s64_codeword_err = cw ^ (SECDED64_CW'(1) << b); #1;
      if (b != SECDED64_CB-1) begin  // skip overall-parity-only error
        check($sformatf("secded64 SEC b%0d sec", b), s64_sec && !s64_ded);
      end
      if (b >= SECDED64_CB)
        check($sformatf("secded64 SEC b%0d corrected", b), s64_data_out == 64'hDEADBEEFCAFEBABE);
    end

    // spot-check DED: pairs within check-bit region
    for (int b0 = 0; b0 < 8; b0++) begin
      for (int b1 = b0+1; b1 < 16 && b1 < SECDED64_CW; b1++) begin
        s64_codeword_err = cw ^ (SECDED64_CW'(1) << b0) ^ (SECDED64_CW'(1) << b1); #1;
        check($sformatf("secded64 DED (%0d,%0d)", b0, b1), s64_ded && !s64_sec);
      end
    end
  endtask

  // ── DECTED 8-bit tests ────────────────────────────────────────────────────────
  task automatic test_dected8;
    automatic logic [DECTED8_CW-1:0] cw;
    d8_data_in = 8'h5A; #1;
    cw = d8_codeword;

    d8_codeword_err = cw; #1;
    check("dected8 no-error data", d8_data_out == 8'h5A);
    check("dected8 no-error sec",  !d8_sec);
    check("dected8 no-error dec",  !d8_dec);
    check("dected8 no-error ted",  !d8_ted);

    // single data-bit errors (check bits at [DECTED8_CB-1:0], data at [CW-1:DECTED8_CB])
    for (int b = DECTED8_CB; b < DECTED8_CW; b++) begin
      d8_codeword_err = cw ^ (DECTED8_CW'(1) << b); #1;
      check($sformatf("dected8 SEC b%0d sec",       b), d8_sec);
      check($sformatf("dected8 SEC b%0d dec",       b), !d8_dec);
      check($sformatf("dected8 SEC b%0d ted",       b), !d8_ted);
      check($sformatf("dected8 SEC b%0d corrected", b), d8_data_out == 8'h5A);
    end

    // double data-bit errors (exhaustive over data region)
    for (int b0 = DECTED8_CB; b0 < DECTED8_CW-1; b0++) begin
      for (int b1 = b0+1; b1 < DECTED8_CW; b1++) begin
        d8_codeword_err = cw ^ (DECTED8_CW'(1) << b0) ^ (DECTED8_CW'(1) << b1); #1;
        check($sformatf("dected8 DEC (%0d,%0d) dec",       b0, b1), d8_dec);
        check($sformatf("dected8 DEC (%0d,%0d) sec",       b0, b1), !d8_sec);
        check($sformatf("dected8 DEC (%0d,%0d) ted",       b0, b1), !d8_ted);
        check($sformatf("dected8 DEC (%0d,%0d) corrected", b0, b1), d8_data_out == 8'h5A);
      end
    end

    // triple data-bit errors → TED (pick a few triples)
    for (int b0 = DECTED8_CB; b0 < DECTED8_CB+3; b0++) begin
      for (int b1 = b0+1; b1 < DECTED8_CB+4; b1++) begin
        for (int b2 = b1+1; b2 < DECTED8_CB+5 && b2 < DECTED8_CW; b2++) begin
          d8_codeword_err = cw ^ (DECTED8_CW'(1) << b0)
                               ^ (DECTED8_CW'(1) << b1)
                               ^ (DECTED8_CW'(1) << b2); #1;
          check($sformatf("dected8 TED (%0d,%0d,%0d)", b0, b1, b2),
                d8_ted && !d8_sec && !d8_dec);
        end
      end
    end
  endtask

  // ── DECTED 64-bit tests ───────────────────────────────────────────────────────
  task automatic test_dected64;
    automatic logic [DECTED64_CW-1:0] cw;
    d64_data_in = 64'h0123456789ABCDEF; #1;
    cw = d64_codeword;

    d64_codeword_err = cw; #1;
    check("dected64 no-error data", d64_data_out == 64'h0123456789ABCDEF);
    check("dected64 no-error sec",  !d64_sec);
    check("dected64 no-error dec",  !d64_dec);
    check("dected64 no-error ted",  !d64_ted);

    for (int b = DECTED64_CB; b < DECTED64_CW; b++) begin
      d64_codeword_err = cw ^ (DECTED64_CW'(1) << b); #1;
      check($sformatf("dected64 SEC b%0d sec",       b), d64_sec && !d64_dec && !d64_ted);
      check($sformatf("dected64 SEC b%0d corrected", b), d64_data_out == 64'h0123456789ABCDEF);
    end

    // spot-check DEC: pairs in the lower data region
    for (int b0 = DECTED64_CB; b0 < DECTED64_CB+10; b0++) begin
      for (int b1 = b0+1; b1 < DECTED64_CB+11; b1++) begin
        d64_codeword_err = cw ^ (DECTED64_CW'(1) << b0) ^ (DECTED64_CW'(1) << b1); #1;
        check($sformatf("dected64 DEC (%0d,%0d) dec",       b0, b1),
              d64_dec && !d64_sec && !d64_ted);
        check($sformatf("dected64 DEC (%0d,%0d) corrected", b0, b1),
              d64_data_out == 64'h0123456789ABCDEF);
      end
    end

    // spot-check TED: triples in the lower data region
    for (int b0 = DECTED64_CB; b0 < DECTED64_CB+3; b0++) begin
      for (int b1 = b0+1; b1 < DECTED64_CB+4; b1++) begin
        for (int b2 = b1+1; b2 < DECTED64_CB+5; b2++) begin
          d64_codeword_err = cw ^ (DECTED64_CW'(1) << b0)
                                ^ (DECTED64_CW'(1) << b1)
                                ^ (DECTED64_CW'(1) << b2); #1;
          check($sformatf("dected64 TED (%0d,%0d,%0d)", b0, b1, b2),
                d64_ted && !d64_sec && !d64_dec);
        end
      end
    end
  endtask

  // ── Main ──────────────────────────────────────────────────────────────────────
  initial begin
    fail_count = 0;
    s8_data_in = '0;   s8_codeword_err  = '0;
    s64_data_in = '0;  s64_codeword_err = '0;
    d8_data_in = '0;   d8_codeword_err  = '0;
    d64_data_in = '0;  d64_codeword_err = '0;
    #1;

    test_secded8();
    test_secded64();
    test_dected8();
    test_dected64();

    if (fail_count == 0) begin
      $display("ECC SELF-TEST PASSED");
      $finish(0);
    end else begin
      $display("ECC SELF-TEST FAILED (%0d failures)", fail_count);
      $fatal(1);
    end
  end

endmodule
