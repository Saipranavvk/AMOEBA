///////////////////////////////////////////
// ecc_secded_enc.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 26 August 2026
// Modified:
//
// Purpose: Parameterizable SECDED (Single Error Correction, Double Error
//          Detection) encoder using extended Hamming code.  Appends R+1
//          check bits to DATA_WIDTH input bits; output is
//          {data_i, overall_parity, hamming[R-1:0]} (check bits in LSB).
//
// Parity bit k covers all codeword positions p (1-indexed) where:
//   (a) p is not a power of 2  (data position), AND
//   (b) bit k of p is set.
// Data-bit index for position p:  p - $clog2(p+1) - 1.
//
// R breakpoints from 2^R - R - 1 >= DATA_WIDTH:
//   R=2->1, R=3->4, R=4->11, R=5->26, R=6->57, R=7->120, R=8->247
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

module ecc_secded_enc #(
  parameter int DATA_WIDTH = 64,
  // smallest R s.t. 2^R - R - 1 >= DATA_WIDTH
  parameter int R = (DATA_WIDTH <=   1) ? 2 :
                    (DATA_WIDTH <=   4) ? 3 :
                    (DATA_WIDTH <=  11) ? 4 :
                    (DATA_WIDTH <=  26) ? 5 :
                    (DATA_WIDTH <=  57) ? 6 :
                    (DATA_WIDTH <= 120) ? 7 : 8
) (
  input  logic [DATA_WIDTH-1:0] data_i,
  // layout MSB->LSB: data_i | overall_parity | hamming[R-1:0]
  output logic [DATA_WIDTH+R:0] codeword_o
);

  logic [R-1:0] hamming;
  logic         overall_parity;

  // For each parity bit k, XOR the data bits at codeword positions p where
  // p is a data position (not a power of 2) AND bit k of p is set.
  // All indexing is done with genvars so $clog2 receives a constant argument.
  for (genvar k = 0; k < R; k++) begin : gen_hamming
    logic [DATA_WIDTH+R-1:0] hcov;
    for (genvar p = 1; p <= DATA_WIDTH + R; p++) begin : gen_pos
      localparam bit IS_DATA    = ((p & (p - 1)) != 0);
      localparam bit HAS_BIT_K  = ((p >> k) & 1) != 0;
      if (IS_DATA && HAS_BIT_K) begin : covered
        localparam int DI = p - $clog2(p + 1) - 1;
        assign hcov[p-1] = data_i[DI];
      end else begin : not_covered
        assign hcov[p-1] = 1'b0;
      end
    end
    assign hamming[k] = ^hcov;
  end

  assign overall_parity = ^data_i ^ ^hamming;

  assign codeword_o = {data_i, overall_parity, hamming};

endmodule
