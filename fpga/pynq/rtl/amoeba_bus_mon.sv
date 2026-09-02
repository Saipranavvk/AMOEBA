///////////////////////////////////////////////////////////////////////////////
// amoeba_bus_mon.sv
//
// Passive snoop of the SoC's AHB-Lite master, feeding three things the PS
// wants: the console byte stream, the HTIF exit code, and a cycle counter.
//
// Why the AHB and not the memory interface.  wallypipelinedsoc drives HADDR /
// HWDATA / HWRITE / HTRANS as the SHARED bus for every slave -- the internal
// CLINT and UART included; HSELEXT only says whether the external memory is the
// target.  So a snoop here sees the UART traffic, which a snoop on the memory
// port downstream of HSELEXT would not.
//
// Why the UART peripheral still exists.  This monitor is passive: it observes
// the write and does not answer it.  uart_apb stays instantiated so LSR/THRE
// still report the transmitter empty; without it the 8250 driver's
// wait_for_xmitr() spins forever on the first character and the console never
// starts.  Snooping is a faster tap on a working UART, not a replacement.
//
// THE DLAB TRAP.  Offset 0 of a 16550 is the transmit register only while
// LCR[7] (DLAB) is clear; with DLAB set it is the low byte of the baud divisor.
// The Linux 8250 driver opens with LCR=0x83, DLL, DLM, LCR=0x03 -- so a monitor
// that takes every write to offset 0 emits the divisor bytes as console
// characters at every port open.  Shadowing LCR[7] costs one flop and removes a
// class of "the log has garbage in it" that is otherwise very hard to place.
//
// AHB timing.  HREADY high at a clock edge both completes the current data
// phase and accepts the address on the bus.  So each edge with HREADY does two
// things in order: consume the write data belonging to the address latched last
// time, then latch the new address.  HWDATA is only meaningful in that first
// step.
//
// Byte lanes.  hdl/core/lsu/subwordwrite.sv replicates a byte store across all
// eight lanes of a 64-bit HWDATA, which is exactly why uart_apb can wire
// Din = PWDATA[7:0] regardless of the register offset.  HWDATA[7:0] is
// therefore the console byte no matter which offset was addressed, and this
// module does not need to steer lanes.
///////////////////////////////////////////////////////////////////////////////

module amoeba_bus_mon #(
    parameter int          PA_BITS      = 56,
    parameter int          AHBW         = 64,
    parameter logic [63:0] UART_BASE    = 64'h1000_0000,
    // HTIF tohost, from testcode/*/​*.ld.  Reaching the bus as a cache-line
    // writeback, one beat of which carries exactly this doubleword.
    parameter logic [63:0] TOHOST_ADDR  = 64'h8080_0000,
    parameter int          UART_FIFO_LOG2 = 10
)(
    input  logic                   clk,
    input  logic                   rst,        // synchronous, active high (PL reset)
    input  logic                   clear,      // one-cycle: zero the counters and FIFO
    input  logic                   core_reset, // 1 while the core is held; cycles do not count

    // ---- AHB snoop (all inputs; this module drives nothing on the bus) -----
    input  logic [PA_BITS-1:0]     HADDR,
    input  logic [AHBW-1:0]        HWDATA,
    input  logic                   HWRITE,
    input  logic [1:0]             HTRANS,
    input  logic                   HREADY,

    // ---- console ----------------------------------------------------------
    output logic [7:0]             uart_data,
    output logic                   uart_valid,
    input  logic                   uart_pop,
    output logic [15:0]            uart_level,
    output logic                   uart_overflow,

    // ---- HTIF -------------------------------------------------------------
    output logic                   tohost_valid,
    output logic [63:0]            tohost_data,

    // ---- counters ---------------------------------------------------------
    output logic [63:0]            cycles
);

    localparam logic [1:0] HTRANS_NONSEQ = 2'b10;

    // ---- address-phase capture --------------------------------------------
    logic                  dp_valid, dp_write;
    logic [PA_BITS-1:0]    dp_addr;

    logic wr_complete;
    assign wr_complete = HREADY & dp_valid & dp_write;

    // ---- decode ------------------------------------------------------------
    // UART_RANGE is 7: eight byte-wide registers at UART_BASE.
    logic is_uart, is_tohost;
    logic [2:0] uart_off;
    assign is_uart   = (dp_addr[PA_BITS-1:3] == UART_BASE[PA_BITS-1:3]);
    assign uart_off  = dp_addr[2:0];
    assign is_tohost = (dp_addr[PA_BITS-1:3] == TOHOST_ADDR[PA_BITS-1:3]);

    logic dlab;                       // shadow of LCR[7]
    logic uart_push;
    assign uart_push = wr_complete & is_uart & (uart_off == 3'd0) & ~dlab;

    logic fifo_full, fifo_empty;
    logic [UART_FIFO_LOG2:0] fifo_level;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            dp_valid     <= 1'b0;
            dp_write     <= 1'b0;
            dp_addr      <= '0;
            dlab         <= 1'b0;
            tohost_valid <= 1'b0;
            tohost_data  <= '0;
            cycles       <= '0;
        end else begin
            if (HREADY) begin
                // 1. the write whose address was latched on the previous ready
                //    edge is completing now; HWDATA belongs to it
                if (wr_complete) begin
                    if (is_uart && uart_off == 3'd3) dlab <= HWDATA[7];
                    if (is_tohost) begin
                        tohost_data  <= HWDATA[63:0];
                        // Only the terminating write matters: HTIF sets bit 0
                        // on exit.  Intermediate zero writes are the harness
                        // clearing the word.
                        if (HWDATA[0]) tohost_valid <= 1'b1;
                    end
                end
                // 2. and the address on the bus right now is accepted
                dp_valid <= (HTRANS == HTRANS_NONSEQ) || (HTRANS == 2'b11);
                dp_addr  <= HADDR;
                dp_write <= HWRITE;
            end

            // Cycles are counted only while the core is released, so the number
            // is comparable with the Verilator cycle counts in sim rather than
            // including however long the PS took to get around to starting it.
            if (!core_reset) cycles <= cycles + 1'b1;
        end
    end

    amoeba_fifo #(
        .W          (8),
        .DEPTH_LOG2 (UART_FIFO_LOG2)
    ) uart_fifo (
        .clk      (clk),
        .rst      (rst | clear),
        .wr_en    (uart_push),
        .wr_data  (HWDATA[7:0]),
        .full     (fifo_full),
        .overflow (uart_overflow),
        .rd_en    (uart_pop),
        .rd_data  (uart_data),
        .empty    (fifo_empty),
        .level    (fifo_level)
    );

    assign uart_valid = ~fifo_empty;
    assign uart_level = 16'(fifo_level);

    // fifo_full is observable only through uart_overflow; kept named for waves.
    logic unused_full;
    assign unused_full = fifo_full;

endmodule
