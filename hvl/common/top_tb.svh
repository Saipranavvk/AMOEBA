  longint timeout;
    initial begin
        $value$plusargs("TIMEOUT_ECE411=%d", timeout);
    end

    localparam int CHANNELS = 1;
    localparam int XLEN = 64;
    localparam int ILEN = 32;

    mem_itf_w_mask #(
        .CHANNELS(1),
        .AWIDTH(XLEN),
        .DWIDTH(XLEN)
    ) mem_itf(.*);

    // Pick one of the two options (only one of these should be uncommented at a time):
    simple_memory_w_mask simple_memory(.itf(mem_itf)); // For directed testing with PROG
    // random_tb random_tb(.itf(mem_itf)); // For randomized testing

    mon_itf #(
        .CHANNELS(CHANNELS),
        .XLEN(XLEN),
        .ILEN(ILEN)
    ) mon_itf(.*);

   monitor #(
        .CHANNELS(CHANNELS),
        .XLEN(XLEN),
        .ILEN(ILEN)
    ) monitor(.itf(mon_itf));

    rv64_core_wrapper dut (
        .clk(clk),
        .rst(rst),
        .mem_addr(mem_itf.addr[0]),
        .mem_rmask(mem_itf.rmask[0]),
        .mem_wmask(mem_itf.wmask[0]),
        .mem_rdata(mem_itf.rdata[0]),
        .mem_wdata(mem_itf.wdata[0]),
        .mem_resp(mem_itf.resp[0])
        // plus monitor outputs if not reached by hierarchical rvfi_reference.json
);

    `include "rvfi_reference.svh"

    always @(posedge clk) begin
        if (mon_itf.halt) begin
            $finish;
        end
        if (timeout == 0) begin
            $error("TB Error: Timed out");
            $fatal;
        end
        if (mem_itf.error != 0 || mon_itf.error != 0) begin
            $fatal;
        end
        timeout <= timeout - 1;
    end
