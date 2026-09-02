///////////////////////////////////////////////////////////////////////////////
// tb_mem_axi -- exercise amoeba_mem_bram's AXI4-Lite image-load port.
//
// This port had never been simulated.  The RTL testbenches backdoor-load memory
// with $readmemh, so port B was first exercised on real hardware, where it
// deadlocked the PS: it was reset from HRESETn, which the SoC asserts whenever
// the core is held in reset -- which is exactly when an image is loaded.
// AWREADY/WREADY are combinational from registers that reset to 0, so they read
// HIGH and the write was accepted, but BVALID could never assert.  A Zynq GP
// port has no default slave and no timeout, so the CPU blocked forever.
//
// The test that matters is RSTN_LOW_LOAD below: rstn (HRESETn) asserted, which
// is the real operating condition during a load, while s_axi_aresetn is
// released.  Before the fix that test hangs; it is the regression.
///////////////////////////////////////////////////////////////////////////////

module tb_mem_axi;

    localparam int          MEM_KB   = 8;
    localparam logic [63:0] MEM_BASE = 64'h8000_0000;
    localparam int          PA_BITS  = 56;

    logic clk = 0, rstn, s_axi_aresetn;
    always #5 clk = ~clk;

    // AHB side held idle throughout: this test is only about port B.
    logic               HSEL = 0, HWRITE = 0;
    logic [PA_BITS-1:0] HADDR = '0;
    logic [1:0]         HTRANS = 2'b00;
    logic [2:0]         HSIZE = 3'b011;
    logic [63:0]        HWDATA = '0;
    logic [7:0]         HWSTRB = '0;
    logic [63:0]        HRDATA;
    logic               HREADY, HRESP;

    logic [31:0] awaddr, wdata, araddr, rdata;
    logic [3:0]  wstrb;
    logic        awvalid = 0, awready, wvalid = 0, wready;
    logic [1:0]  bresp, rresp;
    logic        bvalid, bready = 0, arvalid = 0, arready, rvalid, rready = 0;

    int errors = 0;

    amoeba_mem_bram #(
        .PA_BITS(PA_BITS), .MEM_BASE(MEM_BASE), .MEM_KB(MEM_KB)
    ) dut (
        .clk(clk), .rstn(rstn), .s_axi_aresetn(s_axi_aresetn),
        .HSEL(HSEL), .HADDR(HADDR), .HTRANS(HTRANS), .HWRITE(HWRITE),
        .HSIZE(HSIZE), .HWDATA(HWDATA), .HWSTRB(HWSTRB),
        .HRDATA(HRDATA), .HREADY(HREADY), .HRESP(HRESP),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
        .s_axi_rready(rready)
    );

    // A watchdog, because the failure mode under test IS a hang.  Without this
    // the regression would present as a test that never finishes.
    int unsigned cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    task automatic expect_done(input string what, input int unsigned deadline);
        if (cyc > deadline) begin
            $display("FAIL  %s: no response within %0d cycles (the hardware deadlock)", what, deadline);
            errors++;
            $display("\n=== %0d error(s) ===", errors);
            $finish;
        end
    endtask

    // AXI handshakes complete AT a rising edge when valid and ready are both
    // high going into it.  So decide at the negedge -- where both are settled
    // -- and only then let the edge happen.  Sampling after the posedge sees
    // ready already withdrawn and mistakes a completed beat for a stalled one.
    task automatic axi_write(input [31:0] a, input [31:0] d, input [3:0] s);
        int unsigned start = cyc;
        bit aw_done, w_done, b_done;
        b_done = 0;
        @(negedge clk);
        awaddr = a; wdata = d; wstrb = s; awvalid = 1; wvalid = 1; bready = 1;
        while (!b_done) begin
            aw_done = awvalid && awready;
            w_done  = wvalid  && wready;
            b_done  = bvalid  && bready;
            if (b_done && bresp !== 2'b00) begin
                $display("FAIL  write 0x%08x: bresp=%b", a, bresp); errors++;
            end
            @(posedge clk);
            @(negedge clk);
            if (aw_done) awvalid = 0;
            if (w_done)  wvalid  = 0;
            expect_done($sformatf("write 0x%08x", a), start + 200);
        end
        awvalid = 0; wvalid = 0; bready = 0;
    endtask

    task automatic axi_read(input [31:0] a, output [31:0] d);
        int unsigned start = cyc;
        bit ar_done, r_done;
        r_done = 0;
        d = 32'hX;
        @(negedge clk);
        araddr = a; arvalid = 1; rready = 1;
        while (!r_done) begin
            ar_done = arvalid && arready;
            r_done  = rvalid  && rready;
            if (r_done) d = rdata;
            @(posedge clk);
            @(negedge clk);
            if (ar_done) arvalid = 0;
            expect_done($sformatf("read 0x%08x", a), start + 200);
        end
        arvalid = 0; rready = 0;
    endtask

    task automatic check(input string what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL  %s: got 0x%08x expected 0x%08x", what, got, exp);
            errors++;
        end else begin
            $display("ok    %s = 0x%08x", what, got);
        end
    endtask

    logic [31:0] v;

    initial begin
        rstn = 0; s_axi_aresetn = 0;
        repeat (8) @(posedge clk);

        // ------------------------------------------------------------------
        // THE REGRESSION.  rstn (HRESETn) stays LOW -- the core is held in
        // reset, which is the condition during every image load -- while the
        // PL reset is released.  Every access below must complete.
        // ------------------------------------------------------------------
        s_axi_aresetn = 1;
        repeat (4) @(posedge clk);
        $display("-- RSTN_LOW_LOAD: core in reset (rstn=0), loading via AXI --");

        axi_write(32'h0000_0000, 32'hDEAD_BEEF, 4'hF);
        axi_write(32'h0000_0004, 32'hCAFE_F00D, 4'hF);
        axi_write(32'h0000_0008, 32'h1122_3344, 4'hF);

        axi_read(32'h0000_0000, v); check("word 0", v, 32'hDEAD_BEEF);
        axi_read(32'h0000_0004, v); check("word 1", v, 32'hCAFE_F00D);
        axi_read(32'h0000_0008, v); check("word 2", v, 32'h1122_3344);

        // Byte strobes: a partial word at the tail of an image is not special.
        axi_write(32'h0000_0010, 32'hFFFF_FFFF, 4'hF);
        axi_write(32'h0000_0010, 32'h0000_00AA, 4'h1);
        axi_read (32'h0000_0010, v); check("strb 0x1", v, 32'hFFFF_FFAA);
        axi_write(32'h0000_0010, 32'h00BB_0000, 4'h4);
        axi_read (32'h0000_0010, v); check("strb 0x4", v, 32'hFFBB_FFAA);

        // Both halves of a 64-bit array word, which is what awaddr[2] selects.
        axi_write(32'h0000_0020, 32'h0000_1111, 4'hF);
        axi_write(32'h0000_0024, 32'h2222_0000, 4'hF);
        axi_read (32'h0000_0020, v); check("lo half", v, 32'h0000_1111);
        axi_read (32'h0000_0024, v); check("hi half", v, 32'h2222_0000);

        // Highest word this memory holds -- catches an index that truncates.
        axi_write(MEM_KB*1024 - 4, 32'h5A5A_5A5A, 4'hF);
        axi_read (MEM_KB*1024 - 4, v); check("top word", v, 32'h5A5A_5A5A);
        axi_read (32'h0000_0000,  v); check("word 0 unaliased", v, 32'hDEAD_BEEF);

        // ------------------------------------------------------------------
        // And it must still work with the core out of reset, which is the
        // readback-after-start case.
        // ------------------------------------------------------------------
        $display("-- core released (rstn=1) --");
        rstn = 1;
        repeat (4) @(posedge clk);
        axi_read(32'h0000_0004, v); check("readback after release", v, 32'hCAFE_F00D);

        if (errors == 0) $display("\n=== tb_mem_axi PASS ===");
        else             $display("\n=== %0d error(s) ===", errors);
        $finish;
    end

endmodule
