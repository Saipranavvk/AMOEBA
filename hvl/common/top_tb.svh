    longint timeout;
    initial begin
        $value$plusargs("TIMEOUT_ECE411=%d", timeout);
    end

    mem_itf_w_mask #(.CHANNELS(1), .DWIDTH(32)) mem_itf(.*);
    simple_memory_32_w_mask mem(.itf(mem_itf));

    mon_itf #(.CHANNELS(8)) mon_itf(.*);
    monitor #(.CHANNELS(8)) monitor(.itf(mon_itf));

    cpu dut(
        .clk            (clk),
        .rst            (rst),
        .mem_addr       (mem_itf.addr  [0]),
        .mem_rmask      (mem_itf.rmask [0]),
        .mem_wmask      (mem_itf.wmask [0]),
        .mem_rdata      (mem_itf.rdata [0]),
        .mem_wdata      (mem_itf.wdata [0]),
        .mem_resp       (mem_itf.resp  [0])
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
