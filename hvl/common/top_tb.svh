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

    // ---- UART transmit tap -------------------------------------------------
    // syscalls_amoeba.c reaches printf() -- and therefore configASSERT() -- by
    // storing bytes to the NS16550 transmit holding register at UART_BASE.
    // rv64_core_wrapper leaves the serial UARTSout pin unconnected, so rather
    // than decode a bit stream at an unknown baud rate we snoop the retired
    // byte store to THR on RVFI.  Line-buffered so the text interleaves
    // cleanly with the simulator's own $display output.
    localparam longint unsigned UART_THR_ADDR = 64'h1000_0000;

    string uart_line = "";

    /* verilator lint_off BLKSEQ */  // string accumulation must be blocking
    function automatic void uart_flush_line();
        if (uart_line.len() != 0) begin
            $display("[UART] %s", uart_line);
            uart_line = "";
        end
    endfunction

    always @(posedge clk) begin
        if (!rst && mon_itf.valid[0] && mon_itf.mem_wmask[0][0] &&
                mon_itf.mem_addr[0] == UART_THR_ADDR) begin
            automatic logic [7:0] uart_ch = mon_itf.mem_wdata[0][7:0];
            if (uart_ch == 8'h0A) begin
                uart_flush_line();
            end else if (uart_ch != 8'h0D) begin
                uart_line = $sformatf("%s%c", uart_line, uart_ch);
            end
        end
    end
    /* verilator lint_on BLKSEQ */

    // ---- Retired-PC ring buffer --------------------------------------------
    // Dumped on timeout so a hung program identifies its own spin loop without
    // a waveform dig: feed the addresses to the .dis to see where it is stuck.
    localparam int PC_HIST_DEPTH = 64;

    logic [XLEN-1:0]  pc_hist [PC_HIST_DEPTH];
    int               pc_hist_wr = 0;
    longint unsigned  pc_hist_order = 0;

    // Interrupt/trap accounting: distinguishes "the program deadlocked" from
    // "the timer tick never arrived", which look identical from the PC trace.
    longint unsigned  sim_cycle       = 0;
    longint unsigned  intr_count      = 0;
    longint unsigned  trap_count      = 0;
    longint unsigned  last_intr_cycle = 0;
    logic [XLEN-1:0]  last_intr_pc    = '0;

    always @(posedge clk) begin
        if (!rst) begin
            sim_cycle <= sim_cycle + 1;
            if (mon_itf.valid[0]) begin
                pc_hist[pc_hist_wr] <= mon_itf.pc_rdata[0];
                pc_hist_wr          <= (pc_hist_wr + 1) % PC_HIST_DEPTH;
                pc_hist_order       <= mon_itf.order[0];
                if (mon_itf.intr[0]) begin
                    intr_count      <= intr_count + 1;
                    last_intr_cycle <= sim_cycle;
                    last_intr_pc    <= mon_itf.pc_rdata[0];
                end
                if (mon_itf.trap[0]) trap_count <= trap_count + 1;
            end
        end
    end

    // ---- Optional full retired-PC log (+PCLOG_ECE411=<path>) ---------------
    // Off unless the plusarg is given.  Writes "cycle pc intr" per retirement so
    // a hang can be reconstructed offline against the ELF symbol table.
    int pclog_fd = 0;

    initial begin
        string pclog_path;
        if ($value$plusargs("PCLOG_ECE411=%s", pclog_path))
            pclog_fd = $fopen(pclog_path, "w");
    end

    always @(posedge clk) begin
        if (!rst && pclog_fd != 0 && mon_itf.valid[0])
            $fwrite(pclog_fd, "%0d %h %0d\n",
                    sim_cycle, mon_itf.pc_rdata[0], mon_itf.intr[0]);
    end

    function automatic void dump_pc_hist();
        if (pclog_fd != 0) $fflush(pclog_fd);
        $display("TB: %0d cycles, %0d interrupts taken, %0d traps taken",
                 sim_cycle, intr_count, trap_count);
        if (intr_count != 0)
            $display("TB: last interrupt at cycle %0d, entering pc %016h",
                     last_intr_cycle, last_intr_pc);
        $display("TB: last %0d retired PCs, oldest first (final rvfi_order=%0d):",
                 PC_HIST_DEPTH, pc_hist_order);
        for (int i = 0; i < PC_HIST_DEPTH; i++) begin
            automatic int idx = (pc_hist_wr + i) % PC_HIST_DEPTH;
            $display("  [%2d] %016h", i, pc_hist[idx]);
        end
    endfunction


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
                uart_flush_line();
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
                uart_flush_line();
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
            uart_flush_line();
            $finish;
        end
        if (timeout == 0) begin
            uart_flush_line();
            dump_pc_hist();
            $error("TB Error: Timed out");
            $fatal;
        end
        if (mem_itf.error != 0 || mon_itf.error != 0) begin
            uart_flush_line();
            $fatal;
        end
        timeout <= timeout - 1;
    end

