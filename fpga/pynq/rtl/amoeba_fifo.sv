///////////////////////////////////////////////////////////////////////////////
// amoeba_fifo.sv
//
// Single-clock first-word-fall-through FIFO.  Used for both the console byte
// stream and the commit-trace records, which is why the read side is FWFT:
// both consumers want to see the head without a read-latency dance.
//
// The storage array is written combinationally and read synchronously, which
// is the shape Vivado needs to infer a block RAM.  A one-deep output register
// in front of it restores fall-through.
//
// ram_style is a literal, not a parameter.  Vivado rejects a parameter as an
// attribute value outright ("expression must be of a packed type") while lint
// accepts it, so the parameterized form passes every local check and then fails
// an hour into synthesis -- which is exactly the failure mode `make dryrun`
// cannot catch either.  Block RAM suits both users here: the trace FIFO is
// 16 KiB, and the 1 KiB console FIFO fits one RAMB18 out of the 132 the core
// leaves free.
//
// Writes to a full FIFO are DROPPED and latch a sticky `overflow`.  Both users
// treat overflow as a hard failure rather than a hiccup: a dropped console byte
// corrupts the log silently, and a dropped trace record breaks the sequence
// numbering the PS-side checker relies on.  The trace path avoids it entirely
// by stalling the core off `level` well before full.
///////////////////////////////////////////////////////////////////////////////

module amoeba_fifo #(
    parameter int W          = 8,
    parameter int DEPTH_LOG2 = 10
)(
    input  logic                  clk,
    input  logic                  rst,          // synchronous, active high

    input  logic                  wr_en,
    input  logic [W-1:0]          wr_data,
    output logic                  full,
    output logic                  overflow,     // sticky until rst

    input  logic                  rd_en,
    output logic [W-1:0]          rd_data,
    output logic                  empty,

    output logic [DEPTH_LOG2:0]   level         // includes the output register
);

    localparam int DEPTH = 1 << DEPTH_LOG2;

    (* ram_style = "block" *)
    logic [W-1:0] mem [DEPTH-1:0];

    logic [DEPTH_LOG2:0] wp, rp;
    logic [DEPTH_LOG2:0] ram_count;
    logic                ram_empty, ram_full;
    logic                out_valid;
    logic [W-1:0]        out_data;
    logic                ram_rd_en, do_wr;

    assign ram_count = wp - rp;
    assign ram_empty = (ram_count == '0);
    assign ram_full  = (ram_count == (DEPTH_LOG2+1)'(DEPTH));

    // The output register holds one entry, so the FIFO is full one short of the
    // array being full only when that register is empty; report the array.
    assign full  = ram_full;
    assign empty = ~out_valid;
    assign rd_data = out_data;
    assign level = ram_count + (DEPTH_LOG2+1)'(out_valid);

    assign do_wr = wr_en & ~ram_full;
    // Advance into the output register whenever it is free, or is being drained
    // this cycle.
    assign ram_rd_en = ~ram_empty & (~out_valid | rd_en);

    always_ff @(posedge clk) begin
        if (do_wr) mem[wp[DEPTH_LOG2-1:0]] <= wr_data;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            wp        <= '0;
            rp        <= '0;
            out_valid <= 1'b0;
            out_data  <= '0;
            overflow  <= 1'b0;
        end else begin
            if (do_wr) wp <= wp + 1'b1;
            if (wr_en & ram_full) overflow <= 1'b1;

            if (ram_rd_en) begin
                out_data  <= mem[rp[DEPTH_LOG2-1:0]];
                rp        <= rp + 1'b1;
                out_valid <= 1'b1;
            end else if (rd_en) begin
                out_valid <= 1'b0;
            end
        end
    end

endmodule
