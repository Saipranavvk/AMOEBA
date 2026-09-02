///////////////////////////////////////////////////////////////////////////////
// amoeba_trace.sv
//
// Commit-trace tap: turns retired instructions into a 32-byte record and
// streams them to the PS over AXI4-Stream (into an AXI DMA S2MM channel), so
// the A9 can step a reference model alongside the soft core.
//
// WHY THIS IS WINDOWED.  A record per retired instruction is roughly 5 GB for
// the Linux boot the core already completes in simulation, and the stream is
// four 64-bit beats per record against a core that can retire one instruction
// per cycle -- so capture caps the core at about one instruction every four
// cycles.  Tracing everything is not a thing you can do.  What you do instead:
// run once with the tap OFF (the counters below still run, and cost nothing) to
// find the retire count where behaviour diverges, then run again with a window
// around it.  That is what TRIG_START / TRIG_COUNT / TRIG_PC are for, and it is
// the difference between this being a tool and being a demo.
//
// WHY IT IS LOSSLESS.  Every record carries `seq`, the retire counter, so the
// PS can prove it received a contiguous run rather than silently comparing a
// stream with holes in it.  Holes are prevented rather than detected: when the
// FIFO passes the high-water mark, ExternalStall goes high and the core stops
// retiring until the DMA catches up.  ExternalStall is folded into StallWCause
// in hdl/core/hazard/hazard.sv and is tied low everywhere else in this project.
//
// This is a much lighter hand than CVW's own packetizer.sv, which holds
// RVVIStall for the whole of each 92-byte Ethernet frame and so runs the core
// at roughly one instruction per 25 cycles whether or not anything is
// congested.  Here the core only pays when the FIFO is genuinely backing up.
//
// Signal sourcing.  The M-stage taps come in as ports and are pipelined to the
// W stage here, the same way third_party/cvw/src/rvvi/rvvisynth.sv does it.
// The top level fills these from downward hierarchical references into the SoC
// instance, which is also how CVW's own fpgaTopArtyA7.sv feeds rvvisynth --
// Vivado synthesizes read-only cross-module references.
///////////////////////////////////////////////////////////////////////////////

module amoeba_trace #(
    parameter int XLEN         = 64,
    // Records per AXI-Stream packet.  TLAST lands on the last beat of each
    // packet, so this is the DMA descriptor size: 256 * 32 B = 8 KiB.
    parameter int PKT_RECORDS  = 256,
    parameter int FIFO_LOG2    = 9,     // 512 records = 16 KiB = 4 BRAM36
    // Stall the core this many free slots before the FIFO is actually full.
    // Needs to cover the retires already in flight when the stall is asserted.
    parameter int HIGH_WATER   = (1 << FIFO_LOG2) - 64
)(
    input  logic                  clk,
    input  logic                  rst,          // PL reset, synchronous
    input  logic                  clear,        // one-cycle: reset counters and capture state
    input  logic                  core_reset,

    // ---- configuration (written by the PS while the core is held) ----------
    input  logic [1:0]            mode,
    input  logic [63:0]           trig_start,   // WINDOW: first seq to capture
    input  logic [63:0]           trig_pc,      // PC_TRIG: PC that arms capture
    input  logic [31:0]           trig_count,   // records to capture; 0 = unlimited

    // ---- core taps, M stage unless noted ------------------------------------
    input  logic                  StallE, StallM, StallW,
    input  logic                  FlushE, FlushM, FlushW,
    input  logic [XLEN-1:0]       PCM,
    input  logic                  InstrValidM,
    input  logic [31:0]           InstrRawD,
    input  logic                  TrapM,
    input  logic [1:0]            PrivilegeModeW,
    input  logic                  GPRWen,       // W stage: register file write port
    input  logic [4:0]            GPRAddr,
    input  logic [XLEN-1:0]       GPRValue,

    // ---- to the core --------------------------------------------------------
    output logic                  ExternalStall,

    // ---- AXI4-Stream master to the DMA -------------------------------------
    output logic [63:0]           m_axis_tdata,
    output logic                  m_axis_tvalid,
    input  logic                  m_axis_tready,
    output logic                  m_axis_tlast,
    output logic [7:0]            m_axis_tkeep,

    // ---- status -------------------------------------------------------------
    output logic [63:0]           retired,
    output logic [31:0]           traps,
    output logic [15:0]           level,
    output logic [1:0]            state,
    output logic                  overflow
);

    localparam logic [1:0] MODE_OFF     = 2'b00;  // counters only
    localparam logic [1:0] MODE_ALL     = 2'b01;  // capture from release
    localparam logic [1:0] MODE_WINDOW  = 2'b10;  // capture from seq == trig_start
    localparam logic [1:0] MODE_PC_TRIG = 2'b11;  // capture from first retire at trig_pc

    localparam logic [1:0] ST_IDLE = 2'b00;
    localparam logic [1:0] ST_ARM  = 2'b01;
    localparam logic [1:0] ST_CAP  = 2'b10;
    localparam logic [1:0] ST_DONE = 2'b11;

    logic tap_rst;
    assign tap_rst = rst | clear | core_reset;

    // ---- pipeline the M-stage taps to W ------------------------------------
    logic [31:0]     InstrRawE, InstrRawM, InstrRawW;
    logic [XLEN-1:0] PCW;
    logic            InstrValidW, TrapW;

    flopenrc #(32)   iraw_e (clk, tap_rst, FlushE, ~StallE, InstrRawD, InstrRawE);
    flopenrc #(32)   iraw_m (clk, tap_rst, FlushM, ~StallM, InstrRawE, InstrRawM);
    flopenrc #(32)   iraw_w (clk, tap_rst, FlushW, ~StallW, InstrRawM, InstrRawW);
    flopenrc #(XLEN) pc_w   (clk, tap_rst, FlushW, ~StallW, PCM,        PCW);
    flopenrc #(1)    iv_w   (clk, tap_rst, FlushW, ~StallW, InstrValidM, InstrValidW);
    flopenrc #(1)    trap_w (clk, tap_rst, FlushW, ~StallW, TrapM,       TrapW);

    // Same retire condition hdl/rv64_core_wrapper.sv uses for monitor_valid.
    // The (|PCW) term suppresses the bubble that walks out of the pipeline
    // after reset, which would otherwise be counted as a retired instruction.
    logic retire;
    assign retire = InstrValidW & ~StallW & (|PCW);

    // ---- always-on counters -------------------------------------------------
    // These run in every mode including OFF: they are ~100 flops and they are
    // what makes the two-pass workflow above possible.
    always_ff @(posedge clk) begin
        if (tap_rst) begin
            retired <= '0;
            traps   <= '0;
        end else if (retire) begin
            retired <= retired + 1'b1;
            if (TrapW) traps <= traps + 1'b1;
        end
    end

    // ---- capture state machine ----------------------------------------------
    logic [31:0] captured;
    logic        trigger;

    always_comb begin
        case (mode)
            MODE_ALL:     trigger = 1'b1;
            MODE_WINDOW:  trigger = (retired >= trig_start);
            MODE_PC_TRIG: trigger = retire & (PCW == trig_pc);
            default:      trigger = 1'b0;
        endcase
    end

    logic capturing;
    assign capturing = (state == ST_CAP);

    logic push;
    logic fifo_full;
    logic [FIFO_LOG2:0] fifo_level;

    assign push = capturing & retire & ~fifo_full;

    // The last record of the capture, used to force TLAST so a partial packet
    // does not sit in the DMA waiting for beats that will never arrive.
    logic last_record;
    assign last_record = capturing & retire &
                         (trig_count != 32'h0) & (captured == trig_count - 1'b1);

    always_ff @(posedge clk) begin
        if (tap_rst) begin
            state    <= (mode == MODE_OFF) ? ST_IDLE : ST_ARM;
            captured <= '0;
        end else begin
            case (state)
                ST_IDLE: if (mode != MODE_OFF) state <= ST_ARM;
                ST_ARM:  if (mode == MODE_OFF)      state <= ST_IDLE;
                         else if (trigger)          state <= ST_CAP;
                ST_CAP: begin
                    if (retire) begin
                        captured <= captured + 1'b1;
                        if (last_record) state <= ST_DONE;
                    end
                    if (mode == MODE_OFF) state <= ST_IDLE;
                end
                ST_DONE: if (mode == MODE_OFF) state <= ST_IDLE;
            endcase
        end
    end

    // ---- record -------------------------------------------------------------
    //   [ 63:  0] pc            architectural PC of the retired instruction
    //   [ 95: 64] insn          compressed forms zero-extended from 16 bits
    //   [159: 96] rd_wdata      0 when no register was written
    //   [164:160] rd            0 when no register was written
    //   [    165] trap
    //   [167:166] priv          current privilege at writeback
    //   [191:168] reserved, zero
    //   [255:192] seq           retire counter; gaps prove records were lost
    logic [255:0] record;
    assign record = {
        retired,                                            // [255:192]
        24'h0,                                              // [191:168]
        PrivilegeModeW,                                     // [167:166]
        TrapW,                                              // [    165]
        GPRWen ? GPRAddr  : 5'h0,                           // [164:160]
        GPRWen ? GPRValue : {XLEN{1'b0}},                   // [159: 96]
        (InstrRawW[1:0] != 2'b11) ? {16'h0, InstrRawW[15:0]} : InstrRawW,
        PCW                                                 // [ 63:  0]
    };

    // ---- FIFO ---------------------------------------------------------------
    // Record-wide, so a record can never be torn across a full boundary the way
    // it could if the FIFO held 64-bit beats.  The 4:1 serialization happens on
    // the read side, below.
    logic [255:0] head;
    logic         fifo_empty, pop;

    amoeba_fifo #(
        .W          (256),
        .DEPTH_LOG2 (FIFO_LOG2)
    ) rec_fifo (
        .clk      (clk),
        .rst      (tap_rst),
        .wr_en    (push),
        .wr_data  (record),
        .full     (fifo_full),
        .overflow (overflow),
        .rd_en    (pop),
        .rd_data  (head),
        .empty    (fifo_empty),
        .level    (fifo_level)
    );

    assign level = 16'(fifo_level);

    // Stall the core well before the FIFO is full: retires already in the
    // pipeline still land after ExternalStall is asserted, and a record dropped
    // for want of a slot breaks the seq contract.
    assign ExternalStall = capturing & (fifo_level >= (FIFO_LOG2+1)'(HIGH_WATER));

    // ---- 64-bit stream out --------------------------------------------------
    logic [1:0]  beat;
    logic [15:0] pkt_rec;      // records emitted in the current packet

    always_comb begin
        case (beat)
            2'd0: m_axis_tdata = head[ 63:  0];
            2'd1: m_axis_tdata = head[127: 64];
            2'd2: m_axis_tdata = head[191:128];
            2'd3: m_axis_tdata = head[255:192];
        endcase
    end

    assign m_axis_tvalid = ~fifo_empty;
    assign m_axis_tkeep  = 8'hFF;
    assign pop = m_axis_tvalid & m_axis_tready & (beat == 2'd3);

    // TLAST closes a packet every PKT_RECORDS records so the DMA retires a
    // descriptor at a predictable size, and also on the final record of a
    // bounded capture so the tail does not sit unflushed.
    assign m_axis_tlast = m_axis_tvalid & (beat == 2'd3) &
                          ((pkt_rec == 16'(PKT_RECORDS - 1)) |
                           ((state == ST_DONE) & (fifo_level == (FIFO_LOG2+1)'(1))));

    always_ff @(posedge clk) begin
        if (tap_rst) begin
            beat    <= 2'd0;
            pkt_rec <= '0;
        end else if (m_axis_tvalid & m_axis_tready) begin
            beat <= beat + 1'b1;
            if (beat == 2'd3)
                pkt_rec <= m_axis_tlast ? 16'h0 : pkt_rec + 1'b1;
        end
    end

endmodule
