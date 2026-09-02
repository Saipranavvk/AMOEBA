///////////////////////////////////////////
// ecc_secded_dec.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 26 August 2026
// Modified:
//
// Purpose: Parameterizable SECDED (Single Error Correction, Double Error
//          Detection) decoder.  Input is the codeword produced by
//          ecc_secded_enc.  Recomputes check bits, builds a syndrome, and
//          in parallel constructs a per-data-bit correction mask.  A MUX
//          selects corrected data on SEC; DED is flagged separately.
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

module ecc_secded_dec #(
  parameter int DATA_WIDTH = 64,
  parameter int R = (DATA_WIDTH <=   1) ? 2 :
                    (DATA_WIDTH <=   4) ? 3 :
                    (DATA_WIDTH <=  11) ? 4 :
                    (DATA_WIDTH <=  26) ? 5 :
                    (DATA_WIDTH <=  57) ? 6 :
                    (DATA_WIDTH <= 120) ? 7 : 8
) (
  input  logic [DATA_WIDTH+R:0]   codeword_i,
  output logic [DATA_WIDTH-1:0]   data_o,
  output logic                    sec_err_o,
  output logic                    ded_err_o
);

  localparam int CHECK_BITS = R + 1;   // R Hamming bits + 1 overall parity
  localparam int CW_WIDTH   = DATA_WIDTH + CHECK_BITS;

  logic [DATA_WIDTH-1:0] data_rx;
  logic [R-1:0]          hamming_rx;

  assign hamming_rx = codeword_i[R-1:0];
  assign data_rx    = codeword_i[CW_WIDTH-1 : CHECK_BITS];

  // Recompute expected Hamming bits from received data using the same
  // position-scan as the encoder (same formula, same constants).
  logic [R-1:0] hamming_exp;
  genvar        k;

  /* verilator lint_off UNUSEDSIGNAL */
  generate
    for (k = 0; k < R; k++) begin : gen_exp
      always_comb begin
        logic xr;
        xr = 1'b0;
        for (int p = 1; p <= DATA_WIDTH + R; p++) begin
          if ((p & (p - 1)) != 0 && p[k])
            xr = xr ^ data_rx[p - $clog2(p + 1) - 1];
        end
        hamming_exp[k] = xr;
      end
    end
  endgenerate
  /* verilator lint_on UNUSEDSIGNAL */

  logic [R-1:0] syndrome;
  logic         parity_check;

  assign syndrome     = hamming_rx ^ hamming_exp;
  assign parity_check = ^codeword_i;

  // syndrome!=0 & parity_check==1: single-bit error -> SEC
  // syndrome!=0 & parity_check==0: double-bit error -> DED
  assign sec_err_o = (syndrome != '0) &  parity_check;
  assign ded_err_o = (syndrome != '0) & ~parity_check;

  // Parallel correction mask: data bit at codeword position p is in error
  // when the syndrome equals p (the Hamming position).
  // Iterate over all codeword positions; for each data position derive DI.
  logic [DATA_WIDTH-1:0] correction_mask;
  genvar                 pos;

  generate
    for (pos = 1; pos <= DATA_WIDTH + R; pos++) begin : gen_corr
      localparam int IS_DATA = ((pos & (pos - 1)) != 0) ? 1 : 0;
      if (IS_DATA != 0) begin : data_bit
        localparam int DI = pos - $clog2(pos + 1) - 1;
        assign correction_mask[DI] = (syndrome == R'(pos));
      end
    end
  endgenerate

  logic [DATA_WIDTH-1:0] corrected_data;
  assign corrected_data = data_rx ^ correction_mask;

  assign data_o = (sec_err_o & ~ded_err_o) ? corrected_data : data_rx;

endmodule
