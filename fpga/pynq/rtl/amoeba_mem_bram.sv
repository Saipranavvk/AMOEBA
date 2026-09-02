///////////////////////////////////////////////////////////////////////////////
// amoeba_mem_bram.sv
//
// Bring-up memory backend: the core's AHB-Lite master against a true dual-port
// block RAM whose second port is an AXI4-Lite slave, so the PS loads the
// program image directly instead of the design needing a bootloader.
//
// Port A  <- ahb_to_memitf <- the core
// Port B  <- AXI4-Lite     <- the PS, over GP0
//
// Port B is AXI rather than a raw block RAM interface on purpose.  Exposing
// bram_en/bram_we/bram_addr and letting IPI infer a bram_rtl interface for an
// AXI BRAM Controller is the more obvious design and the more fragile one:
// interface inference on an RTL module is name-heuristic and silently produces
// loose pins when it misses.  s_axi_* on a module is the single most reliable
// inference IPI does, and it removes a whole IP from the block design.
//
// The two ports are NOT arbitrated, because they are never both live: the PS
// writes the image while the core is held in reset, then releases it.  That is
// the whole reason amoeba_ctl brings CORE_RESET out of configuration asserted.
// A PS write while the core is running is a software bug, and will corrupt
// memory rather than being detected -- do not do it.
//
// This is the first bitstream, not the final one.  ahb_to_memitf returns to
// S_IDLE between beats, so an 8-beat cache-line fill becomes eight single
// transfers; against a 1-cycle block RAM that costs almost nothing, which is
// exactly why it is fine here and not fine against DDR.  The production
// bitstream skips this module and hands the AHB to Xilinx's ahblite_axi_bridge
// so the bursts survive to the HP port.
//
// Sizing.  FreeRTOS is 10 KiB of text+data and 70 KiB of bss/heap/stack, so it
// fits comfortably; Linux does not fit in any amount of block RAM on this part
// and never will.  Note that testcode/freertos/freertos_wally.ld puts the stack
// at RAM_BASE+128 MB and tohost at RAM_BASE+8 MB, both outside anything this
// module can hold -- the FPGA build needs its own linker script with both
// inside MEM_KB.  See fpga/pynq/DESIGN.md.
///////////////////////////////////////////////////////////////////////////////

module amoeba_mem_bram #(
    parameter int          PA_BITS  = 56,
    parameter logic [63:0] MEM_BASE = 64'h8000_0000,
    parameter int          MEM_KB   = 256
)(
    input  logic                  clk,
    input  logic                  rstn,

    // Port B's reset, and it is DELIBERATELY NOT rstn.
    //
    // rstn here is the SoC's HRESETn, which is asserted whenever the PS holds
    // the core in reset -- which is exactly when an image is being loaded.
    // Resetting the AXI4-Lite load port from it deadlocks the PS on its first
    // write: AWREADY/WREADY are combinational from registers that reset to 0,
    // so they read HIGH and the transaction is accepted, but BVALID can never
    // assert while reset holds it clear.  A Zynq GP port has no default slave
    // and no timeout, so the CPU blocks forever on a write that will never
    // complete.  Port B belongs to the PS and follows the PL reset.
    input  logic                  s_axi_aresetn,

    // ---- AHB-Lite slave, from the SoC's external port ----------------------
    input  logic                  HSEL,
    input  logic [PA_BITS-1:0]    HADDR,
    input  logic [1:0]            HTRANS,
    input  logic                  HWRITE,
    input  logic [2:0]            HSIZE,
    input  logic [63:0]           HWDATA,
    input  logic [7:0]            HWSTRB,
    output logic [63:0]           HRDATA,
    output logic                  HREADY,
    output logic                  HRESP,

    // ---- port B: AXI4-Lite image load, from the PS -------------------------
    // 32-bit data against a 64-bit array: awaddr[2] picks the half and WSTRB
    // gives the byte enables inside it.  Byte-granular, so a partial word at
    // the end of an image is not a special case.
    input  logic [31:0]           s_axi_awaddr,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,
    input  logic [31:0]           s_axi_wdata,
    input  logic [3:0]            s_axi_wstrb,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,
    output logic [1:0]            s_axi_bresp,
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready,
    input  logic [31:0]           s_axi_araddr,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,
    output logic [31:0]           s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready
);

    localparam int WORDS      = (MEM_KB * 1024) / 8;
    localparam int ADDR_BITS  = $clog2(WORDS);

    // mem_itf, the same protocol the Verilator tier drives, so the adapter is
    // shared with simulation rather than being FPGA-only code.
    logic [63:0] mem_addr, mem_wdata, mem_rdata;
    logic [7:0]  mem_rmask, mem_wmask;
    logic        mem_resp;

    ahb_to_memitf #(.AHB_PA_BITS(PA_BITS)) adapter (
        .clk       (clk),
        .HRESETn   (rstn),
        .HSEL      (HSEL),
        .HADDR     (HADDR),
        .HTRANS    (HTRANS),
        .HWRITE    (HWRITE),
        .HSIZE     (HSIZE),
        .HWDATA    (HWDATA),
        .HWSTRB    (HWSTRB),
        .HRDATA    (HRDATA),
        .HREADY    (HREADY),
        .HRESP     (HRESP),
        .mem_addr  (mem_addr),
        .mem_rmask (mem_rmask),
        .mem_wmask (mem_wmask),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),
        .mem_resp  (mem_resp)
    );

    // Two always_ff blocks on different clocks writing one array is the true
    // dual-port inference template Vivado wants; Verilator sees it as a
    // multiply-driven signal, which here it deliberately is.
    /* verilator lint_off MULTIDRIVEN */
    (* ram_style = "block" *)
    logic [63:0] mem [WORDS-1:0];
    /* verilator lint_on MULTIDRIVEN */

    // Address decode drops MEM_BASE and any bits above the array: an access
    // past MEM_KB aliases rather than erroring.  The AHB decoder upstream has
    // already limited us to EXT_MEM_RANGE, which is 256 MB and much larger than
    // this array, so out-of-range accesses are a software sizing mistake --
    // they will show up as wrapped writes, which is loud enough to find.
    logic [ADDR_BITS-1:0] widx;
    assign widx = mem_addr[ADDR_BITS+2:3] - MEM_BASE[ADDR_BITS+2:3];

    logic [63:0] rdata_q;
    logic        resp_q;

    always_ff @(posedge clk) begin
        for (int b = 0; b < 8; b++)
            if (mem_wmask[b]) mem[widx][b*8 +: 8] <= mem_wdata[b*8 +: 8];
        rdata_q <= mem[widx];
    end

    assign mem_rdata = rdata_q;

    // mem_resp must lag the mask by exactly the block RAM's read latency.
    // Answering combinationally would make ahb_to_memitf latch HRDATA on the
    // same edge that rdata_q is still capturing, handing the core the PREVIOUS
    // read's data -- a bug that only shows up as occasional wrong loads.
    always_ff @(posedge clk) begin
        if (!rstn) resp_q <= 1'b0;
        else       resp_q <= |mem_rmask | |mem_wmask;
    end
    assign mem_resp = resp_q;

    // ---- port B: AXI4-Lite -------------------------------------------------
    // Single outstanding, no bursts, never errors.  A 256 KiB image is 65,536
    // word writes, which from userspace over a mapped GP0 window is a few
    // milliseconds -- not worth an AXI4 burst slave to speed up something that
    // happens once per run while the core is halted.
    logic        aw_hs, w_hs, ar_hs, wr_commit;
    logic        aw_full, w_full;
    logic [31:0] awaddr_q, wdata_q;
    logic [3:0]  wstrb_q;

    assign s_axi_awready = ~aw_full & ~s_axi_bvalid;
    assign s_axi_wready  = ~w_full  & ~s_axi_bvalid;
    assign aw_hs = s_axi_awvalid & s_axi_awready;
    assign w_hs  = s_axi_wvalid  & s_axi_wready;
    assign wr_commit = (aw_full | aw_hs) & (w_full | w_hs);

    logic [31:0] wr_addr;
    logic [31:0] wr_data;
    logic [3:0]  wr_strb;
    assign wr_addr = aw_full ? awaddr_q : s_axi_awaddr;
    assign wr_data = w_full  ? wdata_q  : s_axi_wdata;
    assign wr_strb = w_full  ? wstrb_q  : s_axi_wstrb;

    logic        rd_pending, rd_half;
    logic [63:0] rdata_b_q;

    // ARREADY is also held low through wr_commit: port B has one array port, so
    // a read accepted on the same cycle as a write would present the write's
    // index and return the wrong doubleword.  Writes win -- a read here is a
    // verification convenience, a write is the image.
    assign s_axi_arready = ~s_axi_rvalid & ~rd_pending & ~wr_commit;
    assign ar_hs = s_axi_arvalid & s_axi_arready;

    // Port B's array access.  Kept as one always_ff on the same clock as port A
    // but a separate block, which is the true-dual-port inference template.
    logic [ADDR_BITS-1:0] widx_b;
    logic [7:0]           wmask_b;
    logic [63:0]          wdata_b;

    assign widx_b  = wr_commit ? wr_addr[ADDR_BITS+2:3] : s_axi_araddr[ADDR_BITS+2:3];
    assign wmask_b = wr_commit ? (wr_addr[2] ? {wr_strb, 4'h0} : {4'h0, wr_strb}) : 8'h0;
    assign wdata_b = {wr_data, wr_data};

    always_ff @(posedge clk) begin
        for (int b = 0; b < 8; b++)
            if (wmask_b[b]) mem[widx_b][b*8 +: 8] <= wdata_b[b*8 +: 8];
        rdata_b_q <= mem[widx_b];
    end

    always_ff @(posedge clk) begin
        if (!s_axi_aresetn) begin
            aw_full      <= 1'b0;
            w_full       <= 1'b0;
            awaddr_q     <= '0;
            wdata_q      <= '0;
            wstrb_q      <= '0;
            s_axi_bvalid <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= '0;
            rd_pending   <= 1'b0;
            rd_half      <= 1'b0;
        end else begin
            if (aw_hs && !wr_commit) aw_full <= 1'b1;
            if (w_hs  && !wr_commit) w_full  <= 1'b1;
            if (aw_hs) awaddr_q <= s_axi_awaddr;
            if (w_hs)  begin wdata_q <= s_axi_wdata; wstrb_q <= s_axi_wstrb; end

            if (wr_commit) begin
                aw_full      <= 1'b0;
                w_full       <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;

            // Reads take an extra cycle: the array read is synchronous, so the
            // address is presented on the accept cycle and the data lands the
            // cycle after.  rd_pending covers that gap and holds ARREADY low,
            // which is also what stops a read racing a write for the array.
            if (ar_hs) begin
                rd_pending <= 1'b1;
                rd_half    <= s_axi_araddr[2];
            end else if (rd_pending) begin
                rd_pending   <= 1'b0;
                s_axi_rvalid <= 1'b1;
                s_axi_rdata  <= rd_half ? rdata_b_q[63:32] : rdata_b_q[31:0];
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
        end
    end

    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;

endmodule
