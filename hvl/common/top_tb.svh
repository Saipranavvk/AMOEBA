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

    // ---- misaligned-access flag for the RVFI waiver ------------------------
    // Recomputed here rather than read from mon_itf.mem_addr, which the wrapper
    // has already masked to an 8-byte boundary and so cannot reveal
    // misalignment.  Funct3W[1:0] encodes the access size as log2(bytes).
`ifdef ECE411_LINUX
    wire [63:0] acc_size_mask = (64'd1 << dut.Funct3W[1:0]) - 64'd1;
    assign mon_itf.mem_misaligned[0] = mon_itf.valid[0] && (|dut.MemRWW) &&
                                       ((dut.IEUAdrW & acc_size_mask) != 64'd0);
`else
    assign mon_itf.mem_misaligned[0] = 1'b0;
`endif

    // ---- UART transmit tap -------------------------------------------------
    // syscalls_amoeba.c reaches printf() -- and therefore configASSERT() -- by
    // storing bytes to the NS16550 transmit holding register at UART_BASE.
    // rv64_core_wrapper leaves the serial UARTSout pin unconnected, so rather
    // than decode a bit stream at an unknown baud rate we snoop the retired
    // byte store to THR on RVFI.  Line-buffered so the text interleaves
    // cleanly with the simulator's own $display output.
    localparam longint unsigned UART_THR_ADDR = 64'h1000_0000;

    string uart_line = "";

    // Declared here rather than with the other counters below: the console
    // printer cycle-stamps each line, and SystemVerilog needs the declaration
    // before that use.
    longint unsigned sim_cycle = 0;

    // ---- UART-driven pass/fail (Linux tier) --------------------------------
    // A Linux userland runs in U-mode with the MMU on, so it cannot reach the
    // HTif tohost address the bare-metal tiers use.  Instead the boot is judged
    // by what it prints: +UART_PASS_ECE411 ends the run successfully, and
    // +UART_FAIL_ECE411 aborts it immediately so a panic costs seconds rather
    // than the full cycle timeout.  Both take a '|'-separated pattern list and
    // match anywhere in a console line.  Unset (the default) means never match,
    // which leaves the bare-metal and FreeRTOS tiers behaving exactly as before.
    string uart_pass_str = "";
    string uart_fail_str = "";
    int    uart_log_fd   = 0;

    initial begin
        string s;
        if ($value$plusargs("UART_PASS_ECE411=%s", s)) uart_pass_str = s;
        if ($value$plusargs("UART_FAIL_ECE411=%s", s)) uart_fail_str = s;
        if ($value$plusargs("UARTLOG_ECE411=%s", s))   uart_log_fd   = $fopen(s, "w");
    end

    function automatic bit str_contains(input string haystack, input string needle);
        automatic int nl = needle.len();
        automatic int hl = haystack.len();
        if (nl == 0 || nl > hl) return 1'b0;
        for (int i = 0; i <= hl - nl; i++) begin
            if (haystack.substr(i, i + nl - 1) == needle) return 1'b1;
        end
        return 1'b0;
    endfunction

    function automatic bit str_matches_any(input string haystack, input string patterns);
        automatic int start = 0;
        automatic int plen  = patterns.len();
        if (plen == 0) return 1'b0;
        for (int i = 0; i <= plen; i++) begin
            if (i == plen || patterns[i] == "|") begin
                if (i > start && str_contains(haystack, patterns.substr(start, i - 1)))
                    return 1'b1;
                start = i + 1;
            end
        end
        return 1'b0;
    endfunction

    /* verilator lint_off BLKSEQ */  // string accumulation must be blocking
    function automatic void uart_flush_line();
        if (uart_line.len() != 0) begin
            automatic string line = uart_line;
`ifdef ECE411_LINUX
            // Cycle-stamped so a boot log doubles as a timing breakdown: the
            // cost of each phase is the difference between successive lines.
            $display("[UART @%0d] %s", sim_cycle, line);
`else
            $display("[UART] %s", line);
`endif
            uart_line = "";
            if (uart_log_fd != 0) begin
                $fwrite(uart_log_fd, "%s\n", line);
                $fflush(uart_log_fd);
            end
            if (str_matches_any(line, uart_fail_str)) begin
                $error("TB: UART matched a failure pattern -- test FAILED");
                $fatal;
            end
            if (str_matches_any(line, uart_pass_str)) begin
                $display("TB: UART matched \"%s\" -- test PASSED", uart_pass_str);
                $finish;
            end
        end
    endfunction

`ifdef ECE411_LINUX
    // Tap the UART peripheral itself rather than RVFI.  monitor_mem_addr is
    // driven from IEUAdrW, which is a *virtual* address, so the RVFI snoop below
    // stops matching UART_THR_ADDR the moment Linux turns on the MMU -- the
    // console goes silent exactly when the boot gets interesting.  Watching the
    // peripheral's own write strobe is physical by construction and works in
    // every privilege mode.
    //
    // The strobe sits high for two PCLK cycles because the AHB-to-APB bridge
    // holds PENABLE an extra cycle; that is why the CVW model's own $write
    // prints every character twice.  Taking the rising edge yields exactly one
    // byte per store.
    wire       uart_we_level = ~dut.soc.uncoregen.uncore.uartgen.uart.uartPC.MEMWb &
                               (dut.soc.uncoregen.uncore.uartgen.uart.uartPC.A == 3'b000) &
                               ~dut.soc.uncoregen.uncore.uartgen.uart.uartPC.DLAB;
    logic      uart_we_level_q;
    always @(posedge clk) uart_we_level_q <= rst ? 1'b0 : uart_we_level;

    wire       uart_ch_valid = uart_we_level & ~uart_we_level_q;
    wire [7:0] uart_ch_data  = dut.soc.uncoregen.uncore.uartgen.uart.uartPC.Din;
`else
    wire       uart_ch_valid = mon_itf.valid[0] && mon_itf.mem_wmask[0][0] &&
                               mon_itf.mem_addr[0] == UART_THR_ADDR;
    wire [7:0] uart_ch_data  = mon_itf.mem_wdata[0][7:0];
`endif

    always @(posedge clk) begin
        if (!rst && uart_ch_valid) begin
            automatic logic [7:0] uart_ch = uart_ch_data;
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

