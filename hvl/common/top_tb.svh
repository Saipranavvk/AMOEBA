  longint timeout;
    initial begin
        $value$plusargs("TIMEOUT_ECE411=%d", timeout);
    end

    localparam int CHANNELS = 1;
    localparam int XLEN = 64;
    localparam int ILEN = 32;

    // RISC-V HTif tohost address — fixed in both bin/link.ld (bare-metal) and
    // freertos_wally.ld (FreeRTOS) at 0x80800000.  All test programs write
    // here on exit; the testbench fires $finish or $fatal depending on code.
    localparam longint unsigned TOHOST_ADDR = 64'h8080_0000;

    mem_itf_w_mask #(
        .CHANNELS(1),
        .AWIDTH(XLEN),
        .DWIDTH(XLEN)
    ) mem_itf(.*);

    simple_memory_w_mask simple_memory(.itf(mem_itf));

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
        .clk      (clk),
        .rst      (rst),
        .mem_addr  (mem_itf.addr [0]),
        .mem_rmask (mem_itf.rmask[0]),
        .mem_wmask (mem_itf.wmask[0]),
        .mem_rdata (mem_itf.rdata[0]),
        .mem_wdata (mem_itf.wdata[0]),
        .mem_resp  (mem_itf.resp [0])
    );

    `include "rvfi_reference.svh"

    // HTif tohost monitor via RVFI: fires at store retirement, before cbo.flush.
    // Required for Spike DPI co-sim: Spike exits when it sees the sd to tohost,
    // so the next RVFI commit (cbo.flush) would trigger $fatal from spike_dpi_next.
    // Protocol: write (exit_code << 1) | 1 to tohost; bit 0 set means exit.
    always @(posedge clk) begin
        if (!rst && mon_itf.valid[0] && mon_itf.mem_wmask[0] != '0 &&
                mon_itf.mem_addr[0] == TOHOST_ADDR) begin
            automatic longint unsigned tohost_val;
            tohost_val = mon_itf.mem_wdata[0];
            if (tohost_val[0]) begin
                if (tohost_val == 64'd1) begin
                    $display("TB: tohost exit(0) -- test PASSED");
                    $finish;
                end else begin
                    $error("TB: tohost exit(%0d) -- test FAILED",
                           tohost_val >> 1);
                    $fatal;
                end
            end
        end
    end

    // AHB-level tohost fallback: fires after cbo.flush evicts the cache line.
    // Not needed when Spike DPI is active (RVFI check above fires first), but
    // kept as a safety net for bare-metal runs without DPI co-sim.
    always @(posedge clk) begin
        if (!rst && mem_itf.wmask[0] != '0 &&
                mem_itf.addr[0] == TOHOST_ADDR) begin
            automatic longint unsigned tohost_val;
            tohost_val = mem_itf.wdata[0];
            if (tohost_val[0]) begin
                if (tohost_val == 64'd1) begin
                    $display("TB: tohost exit(0) -- test PASSED");
                    $finish;
                end else begin
                    $error("TB: tohost exit(%0d) -- test FAILED",
                           tohost_val >> 1);
                    $fatal;
                end
            end
        end
    end

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
