///////////////////////////////////////////
// dummygen.sv
//
// Purpose: Context-aware dummy instruction generator (random instruction insertion)
//
// AMOEBA addition; not part of upstream CORE-V Wally.
//
// Captures ALU-class instructions out of the decode stage and replays them at a
// programmable average rate as architecturally invisible "dummy" instructions.
// The inserted instructions are drawn from the program actually running, so the
// dummy instruction mix tracks the real instruction mix.  Based on Leplus, Savry
// and Bossuet, "Insertion of random delay with context-aware dummy instructions
// generator in a RISC-V processor", IEEE HOST 2022.
//
// A programmable divider strobes every rand_instr_insert_freq cycles.  Each
// strobe both captures one instruction and, gated by a PRNG bit, injects the
// previously captured one -- so the average insertion rate is one every
// 2*rand_instr_insert_freq cycles.  Writing 0 to the CSR disables the feature.
//
// Stage 1 scope: OP, OP-32, OP-IMM, OP-IMM-32, LUI and AUIPC only, excluding
// the M extension.  Loads, stores, jumps, branches, FP, atomics, fences and
// SYSTEM are never captured, so an injected instruction can neither trap nor
// touch memory, control flow or privileged state.
///////////////////////////////////////////

module dummygen (
  input  logic        clk, reset,
  input  logic [31:0] FreqW,        // rand_instr_insert_freq CSR; 0 disables insertion
  input  logic [31:0] InstrD,       // real decode-stage instruction, after decompression
  input  logic        InstrValidD,  // decode stage holds a valid instruction
  input  logic        InsertOkD,    // pipeline state permits an insertion this cycle
  output logic        InjectD,      // insert DummyInstrD into decode this cycle
  output logic [31:0] DummyInstrD,  // instruction to inject
  output logic        DummySelD     // which shadow physical register the dummy writes
);

  logic [31:0] LFSR;                // PRNG; replace with a TRNG source when one exists
  logic [31:0] DivCntr;             // programmable frequency divider
  logic [31:0] DummyInstrReg;       // most recently captured instruction ("dummy opcode")
  logic        DummyValid;          // DummyInstrReg holds an instruction not yet replayed
  logic        Enabled, StrobeD, CaptureOkD, CaptureD;
  logic [6:0]  OpD;
  logic        MulDivD;

  // Programmable divider.  Held clear while disabled so enabling starts a fresh period.
  assign Enabled = |FreqW;
  always_ff @(posedge clk)
    if (reset | ~Enabled)      DivCntr <= '0;
    else if (DivCntr == '0)    DivCntr <= FreqW - 32'd1;
    else                       DivCntr <= DivCntr - 32'd1;

  assign StrobeD = Enabled & (DivCntr == '0);

  // Maximal-length 32-bit Fibonacci LFSR (taps 32, 22, 2, 1).  Free-running so that
  // the insertion pattern does not correlate with when the feature was enabled.
  always_ff @(posedge clk)
    if (reset) LFSR <= 32'h1;
    else       LFSR <= {LFSR[30:0], LFSR[31] ^ LFSR[21] ^ LFSR[1] ^ LFSR[0]};

  // Capture filter: ALU-class only.  Excluding the M extension keeps every dummy
  // single-cycle, so an insertion never stalls the pipeline for a divide.
  assign OpD     = InstrD[6:0];
  assign MulDivD = (InstrD[31:25] == 7'b0000001);

  assign CaptureOkD = InstrValidD &
    (((OpD == 7'b0110011) & ~MulDivD) |  // OP: R-type ALU, Zba/Zbb/Zbc/Zbs/Zbk/Zkn
     ((OpD == 7'b0111011) & ~MulDivD) |  // OP-32: W-type ALU
      (OpD == 7'b0010011)              |  // OP-IMM
      (OpD == 7'b0011011)              |  // OP-IMM-32
      (OpD == 7'b0110111)              |  // LUI
      (OpD == 7'b0010111));               // AUIPC

  assign CaptureD = StrobeD & CaptureOkD;

  // Inject the previously captured instruction, never the one captured this cycle:
  // that keeps the injection path clear of the decode-stage instruction mux and
  // enforces the "each captured opcode is replayed at most once" property.
  assign InjectD = StrobeD & LFSR[0] & DummyValid & InsertOkD;

  always_ff @(posedge clk)
    if (reset) begin
      DummyInstrReg <= '0;
      DummyValid    <= 1'b0;
    end else if (CaptureD) begin
      DummyInstrReg <= InstrD;
      DummyValid    <= 1'b1;
    end else if (InjectD) begin
      DummyValid    <= 1'b0;
    end

  // The captured encoding is replayed verbatim.  The rd field is left alone because
  // the register file redirects dummy writes to a shadow register regardless of rd,
  // and rewriting rs1/rs2 would corrupt the Zbb/Zbk/Zkn instructions that encode
  // their operation in the rs2 field.
  assign DummyInstrD = DummyInstrReg;
  assign DummySelD   = LFSR[1];

`ifdef ECE411_DUMMY_TRACE
  // Debug-only insertion trace; compiled out unless ECE411_DUMMY_TRACE is defined.
  // InjectD and CaptureD are single-cycle pulses by construction (one strobe per
  // divider period), so neither can double-report the way a stall-held signal would.
  logic [63:0] CycleCtr, InjectCtr;

  always_ff @(posedge clk)
    if (reset) begin
      CycleCtr  <= '0;
      InjectCtr <= '0;
    end else begin
      CycleCtr <= CycleCtr + 64'd1;
      if (InjectD) InjectCtr <= InjectCtr + 64'd1;
    end

  always_ff @(posedge clk) begin
    if (~reset & CaptureD)
      $display("[dummy] %0t cycle %0d  CAPTURE %08h", $time, CycleCtr, InstrD);
    if (~reset & InjectD)
      // rd/rs1/rs2 below are the captured encoding's own fields.  rs1/rs2 really are
      // read; rd is not used -- the write is redirected to shadow physical register p%0d.
      $display("[dummy] %0t cycle %0d  INJECT  %08h  (rd=x%0d rs1=x%0d rs2=x%0d) -> p%0d   [#%0d]",
               $time, CycleCtr, DummyInstrD,
               DummyInstrD[11:7], DummyInstrD[19:15], DummyInstrD[24:20],
               32 + DummySelD, InjectCtr + 64'd1);
  end
`endif

endmodule

