///////////////////////////////////////////
// ecc_bit_flip.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 4 September 2026
// Modified:
//
// Purpose: Parameterizable single-bit error injector for ECC testing.
//          Uses a 16-bit Galois LFSR to select a pseudo-random codeword bit
//          index; a period counter triggers an injection every 2^INJECT_PERIOD
//          clock cycles.  Injection is gated by inject_en so the module is a
//          pure combinational pass-through (codeword_o = codeword_i) when
//          inject_en = 0.  This keeps the normal-operation critical path clean
//          and makes the design DFT-friendly: a test controller can assert
//          inject_en to exercise ECC correction without a separate build.
//
//          Only a single bit is ever flipped per injection event, guaranteeing
//          that the SECDED decoder can always correct the error.  DED (double
//          error) injection is not supported here by design.
//
//          Synthesis path: LFSR + period counter are ordinary flip-flops.
//          When inject_en is tied to 0 (production), synthesis constant-
//          propagation can eliminate the XOR flip path entirely.
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

module ecc_bit_flip #(
  parameter int CW_WIDTH      = 72,   // codeword width (DATA_WIDTH + R + 1)
  parameter int LFSR_POLY     = 16'hB400, // Galois LFSR: x^16+x^14+x^13+x^11+1
  parameter int INJECT_PERIOD = 9     // inject every 2^INJECT_PERIOD cycles
) (
  input  logic                 clk,
  input  logic                 reset,
  input  logic                 inject_en,          // 1 = inject; 0 = pass-through
  input  logic [CW_WIDTH-1:0]  codeword_i,
  output logic [CW_WIDTH-1:0]  codeword_o
);

  localparam int LOG_CW = $clog2(CW_WIDTH);

  // ── Galois LFSR ──────────────────────────────────────────────────────────────
  // Feedback: shift right, XOR polynomial mask on LSB-out.
  // Initialised to all-ones (avoids the lock-up all-zeros state).
  logic [15:0] lfsr;

  always_ff @(posedge clk)
    if (reset) lfsr <= 16'hFFFF;
    else       lfsr <= {1'b0, lfsr[15:1]} ^ (lfsr[0] ? 16'(LFSR_POLY) : 16'h0);

  // ── Period counter ───────────────────────────────────────────────────────────
  // Counts freely; injection fires on the single cycle where all bits are 1.
  logic [INJECT_PERIOD-1:0] cnt;

  always_ff @(posedge clk)
    if (reset) cnt <= '0;
    else       cnt <= cnt + 1'b1;

  // ── Bit-index selection ──────────────────────────────────────────────────────
  // Use the lower LOG_CW bits of the LFSR as the candidate index.
  // Clamp indices >= CW_WIDTH to 0 (simple comparator, no divider hardware).
  logic [LOG_CW-1:0] bit_sel;

  assign bit_sel = (lfsr[LOG_CW-1:0] < LOG_CW'(CW_WIDTH))
                    ? lfsr[LOG_CW-1:0]
                    : '0;

  // ── Injection (combinational) ─────────────────────────────────────────────────
  // Flip exactly one bit when inject_en is asserted and the counter fires.
  // When inject_en=0 this is a direct wire assignment (no XOR in critical path).
  always_comb begin
    codeword_o = codeword_i;
    if (inject_en & (&cnt))
      codeword_o[bit_sel] = ~codeword_i[bit_sel];
  end

endmodule
