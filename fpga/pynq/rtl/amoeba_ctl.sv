///////////////////////////////////////////////////////////////////////////////
// amoeba_ctl.sv
//
// AXI4-Lite control and status block.  This is the PS's entire view of the
// design: everything the Cortex-A9 can do to the soft core, it does through
// these registers.
//
// The organizing rule is that the PS owns the core's reset.  CORE_RESET comes
// out of configuration ASSERTED, so after the bitstream loads the core is
// halted, fetching nothing.  The PS then loads the memory image, arms the
// trace, clears the monitors, and only then releases reset.  Every other
// semantic in this file follows from that: a register that would race the core
// instead becomes something you set while it is held.
//
// 32-bit data, single outstanding transaction, no bursts, never errors.  The
// PS accesses this over GP0 at whatever base the block design assigns; nothing
// here depends on that base.
//
// Two deliberate simplifications, both safe for a register file this small and
// both worth knowing about before you widen it.  WSTRB is ignored: every write
// lands as a full 32-bit word, so a sub-word store to a control register writes
// the whole thing.  And only the low byte of the address decodes, so the map
// aliases every 256 bytes within the 4 KiB window rather than returning an
// error for an address that is off the end of it.
//
// 64-bit counter reads.  AXI-Lite is 32 bits, so a 64-bit counter takes two
// reads, and a carry landing between them yields a value that never existed.
// Reading a _LO register therefore latches the matching high half into a
// shadow, and the _HI read returns the shadow rather than the live counter.
// Read LO first, always -- reading HI alone returns whatever the last LO read
// froze.  Each counter has its own shadow so interleaved reads cannot alias.
///////////////////////////////////////////////////////////////////////////////

module amoeba_ctl #(
    parameter int          ADDR_W   = 12,
    parameter logic [31:0] ID_MAGIC = 32'h414D_4F42,  // "AMOB"
    parameter logic [31:0] VERSION  = 32'h0000_0100,  // 0.1.0
    parameter logic [31:0] CAPS     = 32'h0000_0000   // filled in by the top
)(
    input  logic                  aclk,
    input  logic                  aresetn,

    // ---- AXI4-Lite slave ---------------------------------------------------
    input  logic [ADDR_W-1:0]     s_axi_awaddr,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,
    input  logic [31:0]           s_axi_wdata,
    input  logic [3:0]            s_axi_wstrb,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,
    output logic [1:0]            s_axi_bresp,
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready,
    input  logic [ADDR_W-1:0]     s_axi_araddr,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,
    output logic [31:0]           s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,

    // ---- to the design -----------------------------------------------------
    output logic                  core_reset,     // 1 = core held in reset
    output logic                  mon_clear,      // one-cycle pulse
    output logic                  trace_clear,    // one-cycle pulse
    output logic [1:0]            trace_mode,
    output logic [63:0]           trig_start,
    output logic [63:0]           trig_pc,
    output logic [31:0]           trig_count,

    // ---- from the design ---------------------------------------------------
    input  logic [7:0]            uart_data,
    input  logic                  uart_valid,
    output logic                  uart_pop,
    input  logic [15:0]           uart_level,
    input  logic                  uart_overflow,

    input  logic [63:0]           cycles,
    input  logic [63:0]           retired,
    input  logic [31:0]           traps,

    input  logic                  tohost_valid,
    input  logic [63:0]           tohost_data,

    input  logic [15:0]           trace_level,
    input  logic [1:0]            trace_state,
    input  logic                  trace_overflow,
    input  logic                  trace_stalling
);

    // ---- register offsets --------------------------------------------------
    localparam logic [7:0] R_ID          = 8'h00;
    localparam logic [7:0] R_VERSION     = 8'h04;
    localparam logic [7:0] R_CAPS        = 8'h08;
    localparam logic [7:0] R_CTRL        = 8'h0C;
    localparam logic [7:0] R_STATUS      = 8'h10;
    localparam logic [7:0] R_UART_DATA   = 8'h14;
    localparam logic [7:0] R_UART_LEVEL  = 8'h18;
    localparam logic [7:0] R_CYCLES_LO   = 8'h20;
    localparam logic [7:0] R_CYCLES_HI   = 8'h24;
    localparam logic [7:0] R_RETIRED_LO  = 8'h28;
    localparam logic [7:0] R_RETIRED_HI  = 8'h2C;
    localparam logic [7:0] R_TRAPS       = 8'h30;
    localparam logic [7:0] R_TOHOST_LO   = 8'h34;
    localparam logic [7:0] R_TOHOST_HI   = 8'h38;
    localparam logic [7:0] R_TRACE_MODE  = 8'h40;
    localparam logic [7:0] R_TRIG_START_LO = 8'h44;
    localparam logic [7:0] R_TRIG_START_HI = 8'h48;
    localparam logic [7:0] R_TRIG_COUNT  = 8'h4C;
    localparam logic [7:0] R_TRIG_PC_LO  = 8'h50;
    localparam logic [7:0] R_TRIG_PC_HI  = 8'h54;
    localparam logic [7:0] R_TRACE_STAT  = 8'h58;

    // ---- write channel -----------------------------------------------------
    // Address and data are accepted independently; the write commits when both
    // have landed.  Single outstanding: BVALID blocks the next acceptance.
    logic            aw_hs, w_hs;
    logic [ADDR_W-1:0] awaddr_q;
    logic [31:0]     wdata_q;
    logic            aw_full, w_full;

    assign s_axi_awready = ~aw_full & ~s_axi_bvalid;
    assign s_axi_wready  = ~w_full  & ~s_axi_bvalid;
    assign aw_hs = s_axi_awvalid & s_axi_awready;
    assign w_hs  = s_axi_wvalid  & s_axi_wready;

    logic wr_commit;
    assign wr_commit = (aw_full | aw_hs) & (w_full | w_hs);

    logic [7:0]  wr_off;
    assign wr_off = aw_full ? awaddr_q[7:0] : s_axi_awaddr[7:0];
    logic [31:0] wr_data;
    assign wr_data = w_full ? wdata_q : s_axi_wdata;

    // ---- read channel ------------------------------------------------------
    logic ar_hs;
    assign s_axi_arready = ~s_axi_rvalid;
    assign ar_hs = s_axi_arvalid & s_axi_arready;

    logic [7:0] rd_off;
    assign rd_off = s_axi_araddr[7:0];

    // ---- state -------------------------------------------------------------
    logic [31:0] cycles_hi_sh, retired_hi_sh, tohost_hi_sh;
    logic [31:0] rdata_n;

    always_comb begin
        case (rd_off)
            R_ID:            rdata_n = ID_MAGIC;
            R_VERSION:       rdata_n = VERSION;
            R_CAPS:          rdata_n = CAPS;
            R_CTRL:          rdata_n = {29'h0, trace_clear, mon_clear, core_reset};
            R_STATUS:        rdata_n = {26'h0, trace_stalling, trace_overflow,
                                        tohost_valid, uart_overflow, uart_valid, core_reset};
            // Bit 8 is the valid flag; a read with bit 8 clear means the FIFO
            // was empty and bits 7:0 are meaningless.  The read pops.
            R_UART_DATA:     rdata_n = {23'h0, uart_valid, uart_data};
            R_UART_LEVEL:    rdata_n = {16'h0, uart_level};
            R_CYCLES_LO:     rdata_n = cycles[31:0];
            R_CYCLES_HI:     rdata_n = cycles_hi_sh;
            R_RETIRED_LO:    rdata_n = retired[31:0];
            R_RETIRED_HI:    rdata_n = retired_hi_sh;
            R_TRAPS:         rdata_n = traps;
            R_TOHOST_LO:     rdata_n = tohost_data[31:0];
            R_TOHOST_HI:     rdata_n = tohost_hi_sh;
            R_TRACE_MODE:    rdata_n = {30'h0, trace_mode};
            R_TRIG_START_LO: rdata_n = trig_start[31:0];
            R_TRIG_START_HI: rdata_n = trig_start[63:32];
            R_TRIG_COUNT:    rdata_n = trig_count;
            R_TRIG_PC_LO:    rdata_n = trig_pc[31:0];
            R_TRIG_PC_HI:    rdata_n = trig_pc[63:32];
            R_TRACE_STAT:    rdata_n = {14'h0, trace_state, trace_level};
            default:         rdata_n = 32'hDEAD_C0DE;
        endcase
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            aw_full     <= 1'b0;
            w_full      <= 1'b0;
            awaddr_q    <= '0;
            wdata_q     <= '0;
            s_axi_bvalid<= 1'b0;
            s_axi_rvalid<= 1'b0;
            s_axi_rdata <= '0;
            uart_pop    <= 1'b0;
            mon_clear   <= 1'b0;
            trace_clear <= 1'b0;
            // Reset asserted out of configuration.  Nothing runs until the PS
            // says so -- see the header.
            core_reset  <= 1'b1;
            trace_mode  <= 2'b00;
            trig_start  <= '0;
            trig_pc     <= '0;
            trig_count  <= '0;
            cycles_hi_sh<= '0;
            retired_hi_sh<= '0;
            tohost_hi_sh <= '0;
        end else begin
            // one-cycle pulses
            mon_clear   <= 1'b0;
            trace_clear <= 1'b0;
            uart_pop    <= 1'b0;

            // write channel bookkeeping
            if (aw_hs && !wr_commit) aw_full <= 1'b1;
            if (w_hs  && !wr_commit) w_full  <= 1'b1;
            if (aw_hs)               awaddr_q <= s_axi_awaddr;
            if (w_hs)                wdata_q  <= s_axi_wdata;

            if (wr_commit) begin
                aw_full      <= 1'b0;
                w_full       <= 1'b0;
                s_axi_bvalid <= 1'b1;
                case (wr_off)
                    R_CTRL: begin
                        core_reset  <= wr_data[0];
                        mon_clear   <= wr_data[1];
                        trace_clear <= wr_data[2];
                    end
                    R_TRACE_MODE:    trace_mode        <= wr_data[1:0];
                    R_TRIG_START_LO: trig_start[31:0]  <= wr_data;
                    R_TRIG_START_HI: trig_start[63:32] <= wr_data;
                    R_TRIG_COUNT:    trig_count        <= wr_data;
                    R_TRIG_PC_LO:    trig_pc[31:0]     <= wr_data;
                    R_TRIG_PC_HI:    trig_pc[63:32]    <= wr_data;
                    default: ; // read-only or unmapped: writes are ignored, not errors
                endcase
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;

            // read channel
            if (ar_hs) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rdata  <= rdata_n;
                // Freeze the high half so the follow-up _HI read is coherent
                // with the _LO value just returned.
                if (rd_off == R_CYCLES_LO)  cycles_hi_sh  <= cycles[63:32];
                if (rd_off == R_RETIRED_LO) retired_hi_sh <= retired[63:32];
                if (rd_off == R_TOHOST_LO)  tohost_hi_sh  <= tohost_data[63:32];
                // Popping here, not on RREADY, keeps the FIFO in step with the
                // value already captured into RDATA above.
                if (rd_off == R_UART_DATA)  uart_pop <= uart_valid;
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
        end
    end

    // This block never errors: unmapped writes are dropped and unmapped reads
    // return a recognizable pattern.  A hung AXI transaction on a debug block
    // is worse than a wrong value, because it takes the PS down with it.
    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;

endmodule
