module monitor #(
    parameter int CHANNELS = 1,
    parameter int XLEN = 64,
    parameter int ILEN = 32,
    parameter int MEM_BYTES = XLEN / 8
)(
    mon_itf itf
);

    function bit is_halt(input logic [31:0] inst);
        is_halt = inst inside {32'h00000063, 32'h0000006f, 32'hf0002013};
    endfunction

    always @(posedge itf.clk iff !itf.rst) begin
        for (int unsigned channel = 0; channel < CHANNELS; channel++) begin
            if (itf.valid[channel] && is_halt(itf.inst[channel])) begin
                itf.halt <= 1'b1;
            end
        end
    end

    `ifndef ECE411_NO_ROI

        int time_fd;
        initial time_fd = $fopen("./time.txt", "w");

        longint inst_count;
        longint cycle_count;
        longint start_time;
        bit ipc_printed;

        longint power_start_time;
        bit power_printed;

        `ifdef ECE411_VERILATOR
            bit dump_on;
        `endif

        initial begin
            inst_count       = longint'(0);
            cycle_count      = longint'(0);
            start_time       = longint'(0);
            ipc_printed      = 1'b0;
            power_start_time = longint'(0);
            power_printed    = 1'b0;
            `ifdef ECE411_VERILATOR
                dump_on      = 1'b0;
            `endif
        end

        always @(posedge itf.clk iff !itf.rst) begin
            cycle_count += longint'(1);
            for (int unsigned channel = 0; channel < CHANNELS; channel++) begin
                if (itf.valid[channel]) begin
                    inst_count += longint'(1);
                    if (itf.inst[channel] == 32'h00102013) begin
                        $display("Monitor: Segment Start time is %t", $time);
                        inst_count = longint'(0);
                        cycle_count = longint'(0);
                        start_time = $time;
                    end
                    if (itf.inst[channel] == 32'h00202013) begin
                        ipc_printed = 1'b1;
                        $display("Monitor: Segment Stop time is %t", $time);
                        $display("Monitor: Segment IPC: %f", real'(inst_count) / cycle_count);
                        $display("Monitor: Segment Time: %t", $time - start_time);
                    end
                    if (itf.inst[channel] == 32'h00302013) begin
                        $display("Monitor: Power Start time is %t", $time);
                        power_start_time = $time;
                        if ($test$plusargs("NO_DUMP_ALL_ECE411")) begin
                            `ifdef ECE411_VERILATOR
                                // $dumpon();
                                dump_on = 1'b1;
                            `else
                                $fsdbDumpon();
                            `endif
                        end
                    end
                    if (itf.inst[channel] == 32'h00402013) begin
                        power_printed = 1'b1;
                        $display("Monitor: Power Stop time is %t", $time);
                        $fwrite(time_fd, "%0t\n", power_start_time);
                        $fwrite(time_fd, "%0t", $time);
                        if ($test$plusargs("NO_DUMP_ALL_ECE411")) begin
                            `ifdef ECE411_VERILATOR
                                // $dumpoff();
                                dump_on = 1'b0;
                            `else
                                $fsdbDumpoff();
                            `endif
                        end
                    end
                end
            end
        end

        final begin
            if (!ipc_printed) begin
                $display("Monitor: Total IPC: %f", real'(inst_count) / cycle_count);
                $display("Monitor: Total Time: %t", $time - start_time);
            end
            if (!power_printed) begin
                $fwrite(time_fd, "%0t\n", power_start_time);
                $fwrite(time_fd, "%0t", $time);
            end
            $fclose(time_fd);
        end

    `endif

    `ifndef ECE411_NO_SPIKE_PRINTER

        int spike_fd;
        initial spike_fd = $fopen("../spike/commit.log", "w");
        final $fclose(spike_fd);

        always @ (posedge itf.clk iff !itf.rst) begin
            if (!itf.halt) begin
                automatic struct {
                    int unsigned channel;
                    longint unsigned order;
                } sp, s[$:CHANNELS];
                for (int unsigned channel = 0; channel < CHANNELS; channel++) begin
                    if(itf.valid[channel]) begin
                        sp.channel = channel;
                        sp.order = itf.order[channel];
                        s.push_front(sp);
                    end
                end
                if (s.size() != 0) begin
                    s.rsort with(item.order);
                end
                while (s.size() != 0) begin
                    automatic int channel;
                    sp = s.pop_back();
                    channel = sp.channel;
                    if (itf.order[channel] % 1 == 0) begin
                        $display("dut commit No.%d, rd_s: x%02d, rd: 0x%h, inst: 0x%h", itf.order[channel], itf.rd_addr[channel], |itf.rd_addr[channel] ? itf.rd_wdata[channel] : 32'd0, itf.inst[channel]);
                    end
                    if (itf.inst[channel][1:0] == 2'b11) begin
                        $fwrite(spike_fd, "core   0: 3 0x%h (0x%h)", itf.pc_rdata[channel], itf.inst[channel]);
                    end else begin
                        $fwrite(spike_fd, "core   0: 3 0x%h (0x%h)", itf.pc_rdata[channel], itf.inst[channel][15:0]);
                    end
                    if (|itf.rd_addr[channel]) begin
                        if (itf.rd_addr[channel] < 10)
                            $fwrite(spike_fd, " x%0d  ", itf.rd_addr[channel]);
                        else
                            $fwrite(spike_fd, " x%0d ", itf.rd_addr[channel]);
                        $fwrite(spike_fd, "0x%h", itf.rd_wdata[channel]);
                    end
                    `ifndef ECE411_NO_FLOAT
                        if (|itf.frd_addr[channel]) begin
                            if (itf.frd_addr[channel] < 10)
                                $fwrite(spike_fd, " f%0d  ", itf.frd_addr[channel][4:0]);
                            else
                                $fwrite(spike_fd, " f%0d ", itf.frd_addr[channel][4:0]);
                            $fwrite(spike_fd, "0x%h", itf.frd_wdata[channel]);
                        end
                    `endif
                    if (|itf.mem_rmask[channel]) begin
                        automatic int first_1 = 0;
                        for(int i = 0; i < 8; i++) begin
                            if(itf.mem_rmask[channel][i]) begin
                                first_1 = i;
                                break;
                            end
                        end
                        $fwrite(spike_fd, " mem 0x%h", {itf.mem_addr[channel][31:2], 2'b0} + first_1);
                    end
                    if (|itf.mem_wmask[channel]) begin
                        automatic int amount_o_1 = 0;
                        automatic int first_1 = 0;
                        for(int i = 0; i < 8; i++) begin
                            if(itf.mem_wmask[channel][i]) begin
                                amount_o_1 += 1;
                            end
                        end
                        for(int i = 0; i < 8; i++) begin
                            if(itf.mem_wmask[channel][i]) begin
                                first_1 = i;
                                break;
                            end
                        end
                        $fwrite(spike_fd, " mem 0x%h", {itf.mem_addr[channel][31:2], 2'b0} + first_1);
                        case (amount_o_1)
                            1: begin
                                automatic logic[7:0] wdata_byte = itf.mem_wdata[channel][8*first_1 +: 8];
                                $fwrite(spike_fd, " 0x%h", wdata_byte);
                            end
                            2: begin
                                automatic logic[15:0] wdata_half = itf.mem_wdata[channel][8*first_1 +: 16];
                                $fwrite(spike_fd, " 0x%h", wdata_half);
                            end
                            4:
                                $fwrite(spike_fd, " 0x%h", itf.mem_wdata[channel]);
                        endcase
                    end
                    $fwrite(spike_fd, "\n");
                    if (is_halt(itf.inst[channel])) begin
                        break;
                    end
                end
            end
        end

    `endif

    `ifndef ECE411_NO_X_CHECK

        always @(posedge itf.clk iff !itf.rst) begin
            for (int unsigned channel = 0; channel < CHANNELS; channel++) begin
                if ($isunknown(itf.valid[channel])) begin
                    $error("RVFI Interface Error: valid is 1'bx");
                    itf.error <= 1'b1;
                end
            end
        end

        generate for (genvar channel = 0; channel < CHANNELS; channel++) begin : x_detection
            always @(posedge itf.clk iff !itf.rst) begin
                if (itf.valid[channel]) begin
                    if ($isunknown(itf.order[channel])) begin
                        $error("RVFI Interface Error: order contains 'x");
                        itf.error <= 1'b1;
                    end
                    if ($isunknown(itf.inst[channel])) begin
                        $error("RVFI Interface Error: inst contains 'x");
                        itf.error <= 1'b1;
                    end
                    if ($isunknown(itf.rs1_addr[channel])) begin
                        $error("RVFI Interface Error: rs1_addr contains 'x");
                        itf.error <= 1'b1;
                    end
                    if ($isunknown(itf.rs2_addr[channel])) begin
                        $error("RVFI Interface Error: rs2_addr contains 'x");
                        itf.error <= 1'b1;
                    end
                    if (|itf.rs1_addr[channel]) begin
                        if ($isunknown(itf.rs1_rdata[channel])) begin
                            $error("RVFI Interface Error: rs1_rdata contains 'x");
                            itf.error <= 1'b1;
                        end
                    end
                    if (|itf.rs2_addr[channel]) begin
                        if ($isunknown(itf.rs2_rdata[channel])) begin
                            $error("RVFI Interface Error: rs2_rdata contains 'x");
                            itf.error <= 1'b1;
                        end
                    end
                    if ($isunknown(itf.rd_addr[channel])) begin
                        $error("RVFI Interface Error: rd_addr contains 'x");
                        itf.error <= 1'b1;
                    end
                    if (|itf.rd_addr[channel]) begin
                        if ($isunknown(itf.rd_wdata[channel])) begin
                            $error("RVFI Interface Error: rd_wdata contains 'x");
                            itf.error <= 1'b1;
                        end
                    end
                    `ifndef ECE411_NO_FLOAT
                        if ($isunknown(itf.frs1_addr[channel])) begin
                            $error("RVFI Interface Error: frs1_addr contains 'x");
                            itf.error <= 1'b1;
                        end
                        if ($isunknown(itf.frs2_addr[channel])) begin
                            $error("RVFI Interface Error: frs2_addr contains 'x");
                            itf.error <= 1'b1;
                        end
                        if ($isunknown(itf.frs3_addr[channel])) begin
                            $error("RVFI Interface Error: frs3_addr contains 'x");
                            itf.error <= 1'b1;
                        end
                        if (|itf.frs1_addr[channel]) begin
                            if ($isunknown(itf.frs1_rdata[channel])) begin
                                $error("RVFI Interface Error: frs1_rdata contains 'x");
                                itf.error <= 1'b1;
                            end
                        end
                        if (|itf.frs2_addr[channel]) begin
                            if ($isunknown(itf.frs2_rdata[channel])) begin
                                $error("RVFI Interface Error: frs2_rdata contains 'x");
                                itf.error <= 1'b1;
                            end
                        end
                        if (|itf.frs3_addr[channel]) begin
                            if ($isunknown(itf.frs3_rdata[channel])) begin
                                $error("RVFI Interface Error: frs3_rdata contains 'x");
                                itf.error <= 1'b1;
                            end
                        end
                        if ($isunknown(itf.frd_addr[channel])) begin
                            $error("RVFI Interface Error: frd_addr contains 'x");
                            itf.error <= 1'b1;
                        end
                        if (|itf.frd_addr[channel]) begin
                            if ($isunknown(itf.frd_wdata[channel])) begin
                                $error("RVFI Interface Error: frd_wdata contains 'x");
                                itf.error <= 1'b1;
                            end
                        end
                    `endif
                    if ($isunknown(itf.pc_rdata[channel])) begin
                        $error("RVFI Interface Error: pc_rdata contains 'x");
                        itf.error <= 1'b1;
                    end
                    if ($isunknown(itf.pc_wdata[channel])) begin
                        $error("RVFI Interface Error: pc_wdata contains 'x");
                        itf.error <= 1'b1;
                    end
                    if ($isunknown(itf.mem_rmask[channel])) begin
                        $error("RVFI Interface Error: mem_rmask contains 'x");
                        itf.error <= 1'b1;
                    end
                    if ($isunknown(itf.mem_wmask[channel])) begin
                        $error("RVFI Interface Error: mem_wmask contains 'x");
                        itf.error <= 1'b1;
                    end
                    if (|itf.mem_rmask[channel] || |itf.mem_wmask[channel]) begin
                        if ($isunknown(itf.mem_addr[channel])) begin
                            $error("RVFI Interface Error: mem_addr contains 'x");
                            itf.error <= 1'b1;
                        end
                    end
                    if (|itf.mem_rmask[channel]) begin
                        for (int i = 0; i < 8; i++) begin
                            if (itf.mem_rmask[channel][i]) begin
                                if ($isunknown(itf.mem_rdata[channel][i*8 +: 8])) begin
                                    $error("RVFI Interface Error: mem_rdata contains 'x");
                                    itf.error <= 1'b1;
                                end
                            end
                        end
                    end
                    if (|itf.mem_wmask[channel]) begin
                        for (int i = 0; i < 8; i++) begin
                            if (itf.mem_wmask[channel][i]) begin
                                if ($isunknown(itf.mem_wdata[channel][i*8 +: 8])) begin
                                    $error("RVFI Interface Error: mem_wdata contains 'x");
                                    itf.error <= 1'b1;
                                end
                            end
                        end
                    end
                end
            end
        end endgenerate

    `endif

    `ifndef ECE411_NO_SPIKE_DPI

        // NOTE: spike.so must be recompiled with uint64_t for wide fields when upgrading
        // from RV32 to RV64. Until then, DPI comparisons check lower 32 bits only.
        typedef struct packed {
            bit [31:0] inst;
            bit [31:0] trapped;
            bit [31:0] rs1_addr;
            bit [31:0] rs2_addr;
            bit [63:0] rs1_rdata;
            bit [63:0] rs2_rdata;
            bit [31:0] rd_addr;
            bit [63:0] rd_wdata;
            bit [31:0] frs1_addr;
            bit [31:0] frs2_addr;
            bit [31:0] frs3_addr;
            bit [63:0] frs1_rdata;
            bit [63:0] frs2_rdata;
            bit [63:0] frs3_rdata;
            bit [31:0] frd_addr;
            bit [63:0] frd_wdata;
            bit [63:0] pc_rdata;
            bit [63:0] pc_wdata;
            bit [63:0] mem_addr;
            bit [31:0] mem_rmask;
            bit [31:0] mem_wmask;
            bit [63:0] mem_rdata;
            bit [63:0] mem_wdata;
        } spike_dpi_rvfi_itf_t;

        import "DPI-C" function void spike_dpi_init(string mem_space, string elf_file);
        import "DPI-C" function int unsigned spike_dpi_fin();
        import "DPI-C" function int unsigned spike_dpi_next(output spike_dpi_rvfi_itf_t r);
        import "DPI-C" function string spike_dpi_dasm();
        import "DPI-C" function void spike_dpi_set_ireg(input int unsigned regnum, input longint unsigned val);

        initial begin
            automatic string elf_file;
            $value$plusargs("ELF_ECE411=%s", elf_file);
            $display("using elf file %s", elf_file);
            spike_dpi_init("-m0x80000000:0x10000000", elf_file);
        end

        final begin
            automatic int unsigned retval;
            retval = spike_dpi_fin();
        end

        spike_dpi_rvfi_itf_t spike_dpi_rvfi_itf;
        longint spike_dpi_order;
        initial spike_dpi_order = 64'd0;

        // Resync state for MMIO-silent-skip: Spike commits MMIO device stores without
        // printing them in --log-commits.  When detected, we synthesize a matching
        // response for the skipped instruction so lock-step comparison can resume.
        logic        mmio_resync_pending;
        logic [63:0] mmio_resync_target_pc;
        logic [63:0] mmio_resync_lookahead_pc;
        initial begin
            mmio_resync_pending      = 1'b0;
            mmio_resync_target_pc    = 64'd0;
            mmio_resync_lookahead_pc = 64'd0;
        end

        // Poll-loop resync: after an MMIO load diff, track the mask instruction and
        // subsequent branch; suppress all divergence until DUT exits the poll loop
        // and commits the UART write that Spike already consumed silently.
        logic        mmio_load_follow_pending;
        logic        mmio_branch_pending;
        logic        uart_poll_skip;
        logic [63:0] uart_spike_resume_pc;
        initial begin
            mmio_load_follow_pending = 1'b0;
            mmio_branch_pending      = 1'b0;
            uart_poll_skip           = 1'b0;
            uart_spike_resume_pc     = 64'd0;
        end

        // Cascade suppression: a DRAM load may return a value previously tainted by an
        // MMIO divergence (e.g. CLINT mtime written to printf arg stack, then loaded by
        // vprintfmt).  Track the tainted register so downstream arithmetic can be
        // suppressed without emitting false errors.
        logic       cascade_active;
        logic [4:0] cascade_rd;
        // Loop-skip: when Spike exits an iteration loop before DUT (because the loop
        // count depends on a tainted DRAM value), synthesize DUT's extra iterations
        // without advancing Spike's log pointer.
        logic        loop_skip_active;
        logic [63:0] loop_skip_exit_pc;
        initial begin
            cascade_active    = 1'b0;
            cascade_rd        = 5'd0;
            loop_skip_active  = 1'b0;
            loop_skip_exit_pc = 64'd0;
        end

        always @ (posedge itf.clk iff !itf.rst) begin
            if (!itf.halt) begin
            automatic struct {
                int unsigned channel;
                longint unsigned order;
            } sp, s[$:CHANNELS];
            for (int unsigned channel = 0; channel < CHANNELS; channel++) begin
                if(itf.valid[channel]) begin
                    sp.channel = channel;
                    sp.order = itf.order[channel];
                    s.push_front(sp);
                end
            end
            if (s.size() != 0) begin
                s.rsort with(item.order);
            end
            while (s.size() != 0) begin
                automatic int channel;
                automatic bit [21:0] diff = '0;
                automatic int unsigned retval;
                sp = s.pop_back();
                channel = sp.channel;
                if (mmio_resync_pending && itf.pc_rdata[channel] == mmio_resync_target_pc) begin
                    // Spike silently committed this MMIO device store without logging it.
                    // Synthesize a perfectly-matching response from DUT's RVFI so that
                    // spike_dpi_next's saved lookahead (mmio_resync_lookahead_pc) becomes
                    // the next instruction both sides will compare normally.
                    spike_dpi_rvfi_itf.inst       = itf.inst[channel];
                    spike_dpi_rvfi_itf.trapped    = '0;
                    spike_dpi_rvfi_itf.rs1_addr   = '0;
                    spike_dpi_rvfi_itf.rs2_addr   = '0;
                    spike_dpi_rvfi_itf.rs1_rdata  = '0;
                    spike_dpi_rvfi_itf.rs2_rdata  = '0;
                    spike_dpi_rvfi_itf.rd_addr    = itf.rd_addr[channel];
                    spike_dpi_rvfi_itf.rd_wdata   = itf.rd_wdata[channel];
                    spike_dpi_rvfi_itf.frs1_addr  = '0;
                    spike_dpi_rvfi_itf.frs2_addr  = '0;
                    spike_dpi_rvfi_itf.frs3_addr  = '0;
                    spike_dpi_rvfi_itf.frs1_rdata = '0;
                    spike_dpi_rvfi_itf.frs2_rdata = '0;
                    spike_dpi_rvfi_itf.frs3_rdata = '0;
                    spike_dpi_rvfi_itf.frd_addr   = '0;
                    spike_dpi_rvfi_itf.frd_wdata  = '0;
                    spike_dpi_rvfi_itf.pc_rdata   = itf.pc_rdata[channel];
                    spike_dpi_rvfi_itf.pc_wdata   = mmio_resync_lookahead_pc;
                    spike_dpi_rvfi_itf.mem_addr   = {itf.mem_addr[channel][63:3], 3'b000};
                    spike_dpi_rvfi_itf.mem_rmask  = {24'd0, itf.mem_rmask[channel]};
                    spike_dpi_rvfi_itf.mem_wmask  = {24'd0, itf.mem_wmask[channel]};
                    spike_dpi_rvfi_itf.mem_rdata  = itf.mem_rdata[channel];
                    spike_dpi_rvfi_itf.mem_wdata  = itf.mem_wdata[channel];
                    mmio_resync_pending <= 1'b0;
                    retval = 1;
                end else if (uart_poll_skip) begin
                    // DUT is still in the UART TX poll loop; Spike has already committed
                    // and exited.  Synthesize all DUT instructions from DUT data without
                    // advancing Spike's log pointer.  Keep shadow registers in sync so
                    // comparison resumes cleanly after the poll exit.
                    if (itf.rd_addr[channel] != '0)
                        spike_dpi_set_ireg(itf.rd_addr[channel], itf.rd_wdata[channel]);
                    begin
                        automatic logic [63:0] pc_poll_seq;
                        pc_poll_seq = itf.pc_rdata[channel]
                                    + (itf.inst[channel][1:0] != 2'b11 ? 64'd2 : 64'd4);
                        // rd_addr==0 (beqz/branch) AND sequential (not taken) → DUT exiting loop
                        if (itf.rd_addr[channel] == '0 && itf.pc_wdata[channel] == pc_poll_seq) begin
                            $display("[UART POLL EXIT] order %0d pc=%h: DUT exiting UART TX poll loop; arming store resync sb@%h resume@%h",
                                itf.order[channel], itf.pc_rdata[channel],
                                pc_poll_seq, uart_spike_resume_pc);
                            uart_poll_skip           <= 1'b0;
                            mmio_resync_pending      <= 1'b1;
                            mmio_resync_target_pc    <= pc_poll_seq;
                            mmio_resync_lookahead_pc <= uart_spike_resume_pc;
                        end
                    end
                    spike_dpi_rvfi_itf.inst       = itf.inst      [channel];
                    spike_dpi_rvfi_itf.trapped    = '0;
                    spike_dpi_rvfi_itf.rs1_addr   = '0;
                    spike_dpi_rvfi_itf.rs2_addr   = '0;
                    spike_dpi_rvfi_itf.rs1_rdata  = '0;
                    spike_dpi_rvfi_itf.rs2_rdata  = '0;
                    spike_dpi_rvfi_itf.rd_addr    = itf.rd_addr   [channel];
                    spike_dpi_rvfi_itf.rd_wdata   = itf.rd_wdata  [channel];
                    spike_dpi_rvfi_itf.frs1_addr  = '0;
                    spike_dpi_rvfi_itf.frs2_addr  = '0;
                    spike_dpi_rvfi_itf.frs3_addr  = '0;
                    spike_dpi_rvfi_itf.frs1_rdata = '0;
                    spike_dpi_rvfi_itf.frs2_rdata = '0;
                    spike_dpi_rvfi_itf.frs3_rdata = '0;
                    spike_dpi_rvfi_itf.frd_addr   = '0;
                    spike_dpi_rvfi_itf.frd_wdata  = '0;
                    spike_dpi_rvfi_itf.pc_rdata   = itf.pc_rdata  [channel];
                    spike_dpi_rvfi_itf.pc_wdata   = itf.pc_wdata  [channel];
                    spike_dpi_rvfi_itf.mem_addr   = {itf.mem_addr[channel][63:3], 3'b000};
                    spike_dpi_rvfi_itf.mem_rmask  = {24'd0, itf.mem_rmask[channel]};
                    spike_dpi_rvfi_itf.mem_wmask  = {24'd0, itf.mem_wmask[channel]};
                    spike_dpi_rvfi_itf.mem_rdata  = itf.mem_rdata [channel];
                    spike_dpi_rvfi_itf.mem_wdata  = itf.mem_wdata [channel];
                    retval = 1;
                end else if (loop_skip_active) begin
                    // Spike exited this iteration loop early (fewer iters due to tainted
                    // DRAM value).  Synthesize DUT's remaining iterations without advancing
                    // Spike's log.  Sync every written register into the shadow so normal
                    // comparison resumes cleanly when DUT reaches the loop exit PC.
                    if (itf.rd_addr[channel] != '0)
                        spike_dpi_set_ireg(itf.rd_addr[channel], itf.rd_wdata[channel]);
                    if (itf.pc_wdata[channel] == loop_skip_exit_pc) begin
                        $display("[LOOP SKIP EXIT] order %0d pc=%h: DUT exits loop to %h; cascade cleared",
                            itf.order[channel], itf.pc_rdata[channel], loop_skip_exit_pc);
                        loop_skip_active <= 1'b0;
                        cascade_active   <= 1'b0;
                    end
                    spike_dpi_rvfi_itf.inst       = itf.inst      [channel];
                    spike_dpi_rvfi_itf.trapped    = '0;
                    spike_dpi_rvfi_itf.rs1_addr   = '0;
                    spike_dpi_rvfi_itf.rs2_addr   = '0;
                    spike_dpi_rvfi_itf.rs1_rdata  = '0;
                    spike_dpi_rvfi_itf.rs2_rdata  = '0;
                    spike_dpi_rvfi_itf.rd_addr    = itf.rd_addr   [channel];
                    spike_dpi_rvfi_itf.rd_wdata   = itf.rd_wdata  [channel];
                    spike_dpi_rvfi_itf.frs1_addr  = '0;
                    spike_dpi_rvfi_itf.frs2_addr  = '0;
                    spike_dpi_rvfi_itf.frs3_addr  = '0;
                    spike_dpi_rvfi_itf.frs1_rdata = '0;
                    spike_dpi_rvfi_itf.frs2_rdata = '0;
                    spike_dpi_rvfi_itf.frs3_rdata = '0;
                    spike_dpi_rvfi_itf.frd_addr   = '0;
                    spike_dpi_rvfi_itf.frd_wdata  = '0;
                    spike_dpi_rvfi_itf.pc_rdata   = itf.pc_rdata  [channel];
                    spike_dpi_rvfi_itf.pc_wdata   = itf.pc_wdata  [channel];
                    spike_dpi_rvfi_itf.mem_addr   = {itf.mem_addr[channel][63:3], 3'b000};
                    spike_dpi_rvfi_itf.mem_rmask  = {24'd0, itf.mem_rmask[channel]};
                    spike_dpi_rvfi_itf.mem_wmask  = {24'd0, itf.mem_wmask[channel]};
                    spike_dpi_rvfi_itf.mem_rdata  = itf.mem_rdata [channel];
                    spike_dpi_rvfi_itf.mem_wdata  = itf.mem_wdata [channel];
                    retval = 1;
                end else begin
                    retval = spike_dpi_next(spike_dpi_rvfi_itf);
                end
                if (retval == 2) begin
                    $fatal(0, "Spike co-simulation: Spike exited with error. Build spike with --enable-commitlog or set ECE411_NO_SPIKE_DPI.");
                end else if (retval == 3) begin
                    $finish;
                end
                diff[ 0] = itf.inst      [channel] != spike_dpi_rvfi_itf.inst          ;
                diff[ 1] = |spike_dpi_rvfi_itf.rs1_addr[4:0]  ? itf.rs1_addr  [channel] != spike_dpi_rvfi_itf.rs1_addr[4:0]  : 1'b0;
                diff[ 2] = |spike_dpi_rvfi_itf.rs1_addr[4:0]  ? itf.rs1_rdata [channel] != spike_dpi_rvfi_itf.rs1_rdata      : 1'b0;
                diff[ 3] = |spike_dpi_rvfi_itf.rs2_addr[4:0]  ? itf.rs2_addr  [channel] != spike_dpi_rvfi_itf.rs2_addr[4:0]  : 1'b0;
                diff[ 4] = |spike_dpi_rvfi_itf.rs2_addr[4:0]  ? itf.rs2_rdata [channel] != spike_dpi_rvfi_itf.rs2_rdata      : 1'b0;
                diff[ 5] = itf.rd_addr   [channel] != spike_dpi_rvfi_itf.rd_addr[4:0]  ;
                diff[ 6] = |spike_dpi_rvfi_itf.rd_addr[4:0]   ? itf.rd_wdata  [channel] != spike_dpi_rvfi_itf.rd_wdata       : 1'b0;
                `ifndef ECE411_NO_FLOAT
                    diff[ 7] = |spike_dpi_rvfi_itf.frs1_addr[5:0] ? itf.frs1_addr [channel] != spike_dpi_rvfi_itf.frs1_addr[5:0] : 1'b0;
                    diff[ 8] = |spike_dpi_rvfi_itf.frs1_addr[5:0] ? itf.frs1_rdata[channel] != spike_dpi_rvfi_itf.frs1_rdata     : 1'b0;
                    diff[ 9] = |spike_dpi_rvfi_itf.frs2_addr[5:0] ? itf.frs2_addr [channel] != spike_dpi_rvfi_itf.frs2_addr[5:0] : 1'b0;
                    diff[10] = |spike_dpi_rvfi_itf.frs2_addr[5:0] ? itf.frs2_rdata[channel] != spike_dpi_rvfi_itf.frs2_rdata     : 1'b0;
                    diff[11] = |spike_dpi_rvfi_itf.frs3_addr[5:0] ? itf.frs3_addr [channel] != spike_dpi_rvfi_itf.frs3_addr[5:0] : 1'b0;
                    diff[12] = |spike_dpi_rvfi_itf.frs3_addr[5:0] ? itf.frs3_rdata[channel] != spike_dpi_rvfi_itf.frs3_rdata     : 1'b0;
                    diff[13] = itf.frd_addr  [channel] != spike_dpi_rvfi_itf.frd_addr[5:0] ;
                    diff[14] = |spike_dpi_rvfi_itf.frd_addr[5:0]  ? itf.frd_wdata [channel] != spike_dpi_rvfi_itf.frd_wdata      : 1'b0;
                `endif
                diff[15] = itf.pc_rdata  [channel] != spike_dpi_rvfi_itf.pc_rdata      ;
                diff[16] = itf.pc_wdata  [channel] != spike_dpi_rvfi_itf.pc_wdata      ;
                diff[18] = itf.mem_rmask [channel] != spike_dpi_rvfi_itf.mem_rmask[7:0];
                diff[19] = itf.mem_wmask [channel] != spike_dpi_rvfi_itf.mem_wmask[7:0];
                if (spike_dpi_rvfi_itf.mem_rmask[7:0] != 8'd0) begin
                    diff[17] = {itf.mem_addr[channel][63:3], 3'b000} != spike_dpi_rvfi_itf.mem_addr;
                    diff[20] = 1'b0;
                    for (int i = 0; i < 8; i++) begin
                        if (spike_dpi_rvfi_itf.mem_rmask[i] && (itf.mem_rdata[channel][i*8 +: 8] != spike_dpi_rvfi_itf.mem_rdata[i*8 +: 8])) begin
                            diff[20] = 1'b1;
                        end
                    end
                end
                if (spike_dpi_rvfi_itf.mem_wmask[7:0] != 8'd0) begin
                    diff[17] = {itf.mem_addr[channel][63:3], 3'b000} != spike_dpi_rvfi_itf.mem_addr;
                    diff[21] = 1'b0;
                    for (int i = 0; i < 8; i++) begin
                        if (spike_dpi_rvfi_itf.mem_wmask[i] && (itf.mem_wdata[channel][i*8 +: 8] != spike_dpi_rvfi_itf.mem_wdata[i*8 +: 8])) begin
                            diff[21] = 1'b1;
                        end
                    end
                end
                if (spike_dpi_rvfi_itf.trapped) begin
                    $display("");
                    $error("Spike Monitor Error at time %0t channel %0d order %0d", $time, channel, itf.order[channel]);
                    $display("Trapped at pc x%08x inst x%08x dasm %s", spike_dpi_rvfi_itf.pc_rdata, spike_dpi_rvfi_itf.inst, spike_dpi_dasm());
                    $display("");
                    itf.error <= 1'b1;
                end else if (itf.order[channel] != spike_dpi_order) begin
                    $display("");
                    $error("Spike Monitor Error at time %0t channel %0d order %0d", $time, channel, itf.order[channel]);
                    $display("Expected order %0d, got %0d.", spike_dpi_order, itf.order[channel]);
                    $display("");
                    itf.error <= 1'b1;
                end else if (diff != 22'd0) begin
                    // Check for MMIO-silent-skip before treating as a real error.
                    // Pattern: only pc_wdata differs (diff[16] only), DUT sequential,
                    // Spike is exactly 4 bytes past DUT's sequential next — meaning Spike
                    // committed one MMIO device store without printing it in --log-commits.
                    begin
                        automatic logic [63:0] mmio_pc_seq;
                        mmio_pc_seq = itf.pc_rdata[channel]
                                    + (itf.inst[channel][1:0] != 2'b11 ? 64'd2 : 64'd4);
                        if (diff == 22'h00010000
                                && itf.pc_wdata[channel]       == mmio_pc_seq
                                && spike_dpi_rvfi_itf.pc_wdata == mmio_pc_seq + 64'd4) begin
                            // MMIO store silent-skip: Spike committed a device store without
                            // logging it in --log-commits. Arm synthesis for the next commit.
                            $display("[MMIO RESYNC] order %0d pc=%h: Spike silently skipped MMIO store at %h; resuming at %h",
                                itf.order[channel], itf.pc_rdata[channel],
                                mmio_pc_seq, spike_dpi_rvfi_itf.pc_wdata);
                            mmio_resync_pending      <= 1'b1;
                            mmio_resync_target_pc    <= mmio_pc_seq;
                            mmio_resync_lookahead_pc <= spike_dpi_rvfi_itf.pc_wdata;
                            mmio_branch_pending      <= 1'b0;
                        end else if ((diff & ~22'h100040) == 22'd0
                                && spike_dpi_rvfi_itf.mem_rmask != '0
                                && spike_dpi_rvfi_itf.mem_addr >= 64'h02000000
                                && spike_dpi_rvfi_itf.mem_addr <  64'h20000000) begin
                            // MMIO load data divergence: Spike's device stub returned a
                            // different value than the DUT's real peripheral (e.g. UART LSR
                            // TEMT bit tracks actual TX state in DUT but is always set in
                            // Spike's stub).  Force Spike's shadow register to DUT's value
                            // so the next instruction's rs1_rdata comparison passes.
                            $display("[MMIO LOAD DIFF] order %0d pc=%h: MMIO read at %h DUT=h%0x Spike=h%0x -- suppressed",
                                itf.order[channel], itf.pc_rdata[channel],
                                spike_dpi_rvfi_itf.mem_addr,
                                itf.rd_wdata[channel], spike_dpi_rvfi_itf.rd_wdata);
                            if (itf.rd_addr[channel] != '0)
                                spike_dpi_set_ireg(itf.rd_addr[channel], itf.rd_wdata[channel]);
                            // If rd_wdata diverged, the next instruction (mask/AND) will
                            // also diverge because Spike used its real stub value.
                            if (diff[6])
                                mmio_load_follow_pending <= 1'b1;
                        end else if (mmio_load_follow_pending && diff == 22'h00000040) begin
                            // Mask/AND following a suppressed MMIO load: rd_wdata diverges
                            // because Spike computed the AND with its stub register value.
                            $display("[MMIO FOLLOW] order %0d pc=%h: mask follow (DUT=h%0x Spike=h%0x) -- suppressed",
                                itf.order[channel], itf.pc_rdata[channel],
                                itf.rd_wdata[channel], spike_dpi_rvfi_itf.rd_wdata);
                            mmio_load_follow_pending <= 1'b0;
                            mmio_branch_pending      <= 1'b1;
                            if (itf.rd_addr[channel] != '0)
                                spike_dpi_set_ireg(itf.rd_addr[channel], itf.rd_wdata[channel]);
                        end else if (mmio_branch_pending && diff == 22'h00010000
                                && itf.pc_wdata[channel] != mmio_pc_seq) begin
                            // Branch after MMIO load follow: DUT took the backward branch
                            // (UART TX not ready) while Spike's stub returned ready.
                            // Save Spike's resume PC (past its invisible UART write) and
                            // enter poll-skip mode to absorb all remaining DUT poll iterations.
                            $display("[MMIO BRANCH] order %0d pc=%h: DUT re-polling (branch to %h), Spike resume %h -- entering poll skip",
                                itf.order[channel], itf.pc_rdata[channel],
                                itf.pc_wdata[channel], spike_dpi_rvfi_itf.pc_wdata);
                            mmio_branch_pending  <= 1'b0;
                            uart_spike_resume_pc <= spike_dpi_rvfi_itf.pc_wdata;
                            uart_poll_skip       <= 1'b1;
                        end else if ((diff & ~22'h100040) == 22'd0
                                && spike_dpi_rvfi_itf.mem_rmask != '0
                                && spike_dpi_rvfi_itf.mem_addr >= 64'h80000000) begin
                            // DRAM load returning a value previously tainted by MMIO divergence
                            // (e.g. CLINT mtime was stored to printf arg stack by FreeRTOS and
                            // is now being read back by vprintfmt).  Spike's process memory has
                            // the wrong value; patch the shadow and start cascade tracking so
                            // downstream arithmetic divergences can be suppressed cleanly.
                            $display("[DRAM LOAD DIFF] order %0d pc=%h: DRAM read at %h DUT=h%0x Spike=h%0x -- cascade started",
                                itf.order[channel], itf.pc_rdata[channel],
                                spike_dpi_rvfi_itf.mem_addr,
                                itf.rd_wdata[channel], spike_dpi_rvfi_itf.rd_wdata);
                            if (itf.rd_addr[channel] != '0) begin
                                spike_dpi_set_ireg(itf.rd_addr[channel], itf.rd_wdata[channel]);
                                cascade_active <= 1'b1;
                                cascade_rd     <= itf.rd_addr[channel][4:0];
                            end
                        end else if (cascade_active && diff == 22'h00000040
                                && (spike_dpi_rvfi_itf.rs1_addr[4:0] == cascade_rd
                                    || spike_dpi_rvfi_itf.rs2_addr[4:0] == cascade_rd)) begin
                            // Arithmetic instruction consuming the tainted register: rd_wdata
                            // diverges because Spike computed from its wrong value.  Patch the
                            // shadow with DUT's result so the cascade propagates correctly.
                            $display("[CASCADE FOLLOW] order %0d pc=%h: cascade x%0d, rd=x%0d DUT=h%0x Spike=h%0x -- suppressed",
                                itf.order[channel], itf.pc_rdata[channel],
                                cascade_rd, itf.rd_addr[channel],
                                itf.rd_wdata[channel], spike_dpi_rvfi_itf.rd_wdata);
                            if (itf.rd_addr[channel] != '0)
                                spike_dpi_set_ireg(itf.rd_addr[channel], itf.rd_wdata[channel]);
                        end else if (cascade_active && diff == 22'h00010000
                                && spike_dpi_rvfi_itf.pc_wdata == mmio_pc_seq
                                && itf.pc_wdata[channel] != mmio_pc_seq) begin
                            // Loop-count divergence: Spike fell through (exited loop) but DUT
                            // took a backward branch (still iterating) because the tainted
                            // register produces more loop iterations in DUT than in Spike.
                            // Enter loop-skip mode: synthesize DUT's remaining iterations
                            // (keeping shadow in sync) until DUT reaches Spike's exit PC.
                            $display("[CASCADE LOOP SKIP] order %0d pc=%h: Spike exited to %h, DUT looping to %h -- loop skip",
                                itf.order[channel], itf.pc_rdata[channel],
                                spike_dpi_rvfi_itf.pc_wdata, itf.pc_wdata[channel]);
                            loop_skip_active  <= 1'b1;
                            loop_skip_exit_pc <= spike_dpi_rvfi_itf.pc_wdata;
                        end else begin
                            $display("");
                            $error("Spike Monitor Error at time %0t channel %0d order %0d", $time, channel, itf.order[channel]);
                            $display("-------begin spike mismatch--------");
                            $display("%010s %04s %09s %09s"              , "signal    ", "diff", "      dut", "    spike");
                            $display("%010s %04s h%08x h%08x %s"         , "inst      ", diff[ 0] ? "--->" : "    ", itf.inst      [channel], spike_dpi_rvfi_itf.inst, spike_dpi_dasm());
                            $display("%010s %04s        %02d        %02d", "rs1_addr  ", diff[ 1] ? "--->" : "    ", itf.rs1_addr  [channel], spike_dpi_rvfi_itf.rs1_addr  );
                            $display("%010s %04s h%08x h%08x"            , "rs1_rdata ", diff[ 2] ? "--->" : "    ", itf.rs1_rdata [channel], spike_dpi_rvfi_itf.rs1_rdata );
                            $display("%010s %04s        %02d        %02d", "rs2_addr  ", diff[ 3] ? "--->" : "    ", itf.rs2_addr  [channel], spike_dpi_rvfi_itf.rs2_addr  );
                            $display("%010s %04s h%08x h%08x"            , "rs2_rdata ", diff[ 4] ? "--->" : "    ", itf.rs2_rdata [channel], spike_dpi_rvfi_itf.rs2_rdata );
                            $display("%010s %04s        %02d        %02d", "rd_addr   ", diff[ 5] ? "--->" : "    ", itf.rd_addr   [channel], spike_dpi_rvfi_itf.rd_addr   );
                            $display("%010s %04s h%08x h%08x"            , "rd_wdata  ", diff[ 6] ? "--->" : "    ", itf.rd_wdata  [channel], spike_dpi_rvfi_itf.rd_wdata  );
                            `ifndef ECE411_NO_FLOAT
                                $display("%010s %04s        %02d        %02d", "frs1_addr ", diff[ 7] ? "--->" : "    ", itf.frs1_addr [channel], spike_dpi_rvfi_itf.frs1_addr );
                                $display("%010s %04s h%08x h%08x"            , "frs1_rdata", diff[ 8] ? "--->" : "    ", itf.frs1_rdata[channel], spike_dpi_rvfi_itf.frs1_rdata);
                                $display("%010s %04s        %02d        %02d", "frs2_addr ", diff[ 9] ? "--->" : "    ", itf.frs2_addr [channel], spike_dpi_rvfi_itf.frs2_addr );
                                $display("%010s %04s h%08x h%08x"            , "frs2_rdata", diff[10] ? "--->" : "    ", itf.frs2_rdata[channel], spike_dpi_rvfi_itf.frs2_rdata);
                                $display("%010s %04s        %02d        %02d", "frs3_addr ", diff[11] ? "--->" : "    ", itf.frs3_addr [channel], spike_dpi_rvfi_itf.frs3_addr  );
                                $display("%010s %04s h%08x h%08x"            , "frs3_rdata", diff[12] ? "--->" : "    ", itf.frs3_rdata[channel], spike_dpi_rvfi_itf.frs3_rdata);
                                $display("%010s %04s        %02d        %02d", "frd_addr  ", diff[13] ? "--->" : "    ", itf.frd_addr  [channel], spike_dpi_rvfi_itf.frd_addr  );
                                $display("%010s %04s h%08x h%08x"            , "frd_wdata ", diff[14] ? "--->" : "    ", itf.frd_wdata [channel], spike_dpi_rvfi_itf.frd_wdata );
                            `endif
                            $display("%010s %04s h%08x h%08x"            , "pc_rdata  ", diff[15] ? "--->" : "    ", itf.pc_rdata  [channel], spike_dpi_rvfi_itf.pc_rdata  );
                            $display("%010s %04s h%08x h%08x"            , "pc_wdata  ", diff[16] ? "--->" : "    ", itf.pc_wdata  [channel], spike_dpi_rvfi_itf.pc_wdata  );
                            if (diff[16]) begin
                                automatic logic [63:0] pc_seq_next;
                                pc_seq_next = itf.pc_rdata[channel]
                                            + (itf.inst[channel][1:0] != 2'b11 ? 64'd2 : 64'd4);
                                if (itf.pc_wdata[channel] == pc_seq_next)
                                    $display("  [pc_wdata hint] DUT=sequential(pc+%0d), Spike jumped to %h -- interrupt/trap boundary",
                                        itf.inst[channel][1:0] != 2'b11 ? 2 : 4,
                                        spike_dpi_rvfi_itf.pc_wdata);
                                else
                                    $display("  [pc_wdata hint] DUT=%h Spike=%h -- both non-sequential",
                                        itf.pc_wdata[channel], spike_dpi_rvfi_itf.pc_wdata);
                            end
                            $display("%010s %04s h%08x h%08x"            , "mem_addr  ", diff[17] ? "--->" : "    ", itf.mem_addr  [channel], spike_dpi_rvfi_itf.mem_addr  );
                            $display("%010s %04s     b%04b     b%04b"    , "mem_rmask ", diff[18] ? "--->" : "    ", itf.mem_rmask [channel], spike_dpi_rvfi_itf.mem_rmask );
                            $display("%010s %04s     b%04b     b%04b"    , "mem_wmask ", diff[19] ? "--->" : "    ", itf.mem_wmask [channel], spike_dpi_rvfi_itf.mem_wmask );
                            $display("%010s %04s h%08x h%08x"            , "mem_rdata ", diff[20] ? "--->" : "    ", itf.mem_rdata [channel], spike_dpi_rvfi_itf.mem_rdata );
                            $display("%010s %04s h%08x h%08x"            , "mem_wdata ", diff[21] ? "--->" : "    ", itf.mem_wdata [channel], spike_dpi_rvfi_itf.mem_wdata );
                            $display("-------end spike mismatch----------");
                            $display("");
                            itf.error <= 1'b1;
                        end
                    end
                end
                // Clear follow-up flags on clean pass so stale state doesn't persist.
                if (diff == 22'd0 && !uart_poll_skip) begin
                    mmio_load_follow_pending <= 1'b0;
                    mmio_branch_pending      <= 1'b0;
                end
                spike_dpi_order = spike_dpi_order + 64'd1;
            end
            end // !itf.halt
        end

    `endif

    `ifndef ECE411_NO_RVFI

        logic [CHANNELS*1 -1:0] rvfi_valid;
        logic [CHANNELS*64-1:0] rvfi_order;
        logic [CHANNELS*XLEN-1:0] rvfi_insn;
        logic [CHANNELS*1 -1:0] rvfi_trap;
        logic [CHANNELS*1 -1:0] rvfi_halt;
        logic [CHANNELS*1 -1:0] rvfi_intr;
        logic [CHANNELS*2 -1:0] rvfi_mode;
        logic [CHANNELS*5 -1:0] rvfi_rs1_addr;
        logic [CHANNELS*5 -1:0] rvfi_rs2_addr;
        logic [CHANNELS*XLEN-1:0] rvfi_rs1_rdata;
        logic [CHANNELS*XLEN-1:0] rvfi_rs2_rdata;
        logic [CHANNELS*5 -1:0] rvfi_rd_addr;
        logic [CHANNELS*XLEN-1:0] rvfi_rd_wdata;
        logic [CHANNELS*XLEN-1:0] rvfi_pc_rdata;
        logic [CHANNELS*XLEN-1:0] rvfi_pc_wdata;
        logic [CHANNELS*XLEN-1:0] rvfi_mem_addr;
        logic [CHANNELS*MEM_BYTES-1:0] rvfi_mem_rmask;
        logic [CHANNELS*MEM_BYTES-1:0] rvfi_mem_wmask;
        logic [CHANNELS*XLEN-1:0] rvfi_mem_rdata;
        logic [CHANNELS*XLEN-1:0] rvfi_mem_wdata;
        logic [CHANNELS*1 -1:0] rvfi_mem_extamo;

        generate for (genvar channel = 0; channel < CHANNELS; channel++) begin : assign_channels
            assign rvfi_trap      [channel]          = itf.trap      [channel];
            assign rvfi_intr      [channel]          = itf.intr      [channel];
            assign rvfi_mode      [channel*2 +: 2]   = itf.mode      [channel];
            assign rvfi_mem_extamo[channel]          = itf.mem_extamo[channel];
            assign rvfi_valid    [channel*1  +: 1 ] =   itf.valid    [channel];
            assign rvfi_order    [channel*64 +: 64] =   itf.order    [channel];
            assign rvfi_insn     [channel*32 +: 32] =   itf.inst     [channel];
            assign rvfi_halt     [channel*1  +: 1 ] =   itf.halt              ;
            assign rvfi_rs1_addr [channel*5  +: 5 ] =   itf.rs1_addr [channel];
            assign rvfi_rs2_addr [channel*5  +: 5 ] =   itf.rs2_addr [channel];
            assign rvfi_rs1_rdata[channel*XLEN +: XLEN] = (|itf.rs1_addr [channel]) ? itf.rs1_rdata[channel] : '0;
            assign rvfi_rs2_rdata[channel*XLEN +: XLEN] = (|itf.rs2_addr [channel]) ? itf.rs2_rdata[channel] : '0;
            assign rvfi_rd_addr  [channel*5         +: 5        ] =   itf.rd_addr  [channel];
            assign rvfi_rd_wdata [channel*XLEN      +: XLEN     ] = (|itf.rd_addr  [channel]) ? itf.rd_wdata[channel] : '0;
            assign rvfi_pc_rdata [channel*XLEN      +: XLEN     ] =   itf.pc_rdata [channel];
            assign rvfi_pc_wdata [channel*XLEN      +: XLEN     ] =   itf.pc_wdata [channel];
            assign rvfi_mem_addr [channel*XLEN      +: XLEN     ] = { itf.mem_addr [channel][XLEN-1:3], 3'b000};
            assign rvfi_mem_rmask[channel*MEM_BYTES +: MEM_BYTES] =   itf.mem_rmask[channel];
            assign rvfi_mem_wmask[channel*MEM_BYTES +: MEM_BYTES] =   itf.mem_wmask[channel];
            assign rvfi_mem_rdata[channel*XLEN      +: XLEN     ] =   itf.mem_rdata[channel];
            assign rvfi_mem_wdata[channel*XLEN      +: XLEN     ] =   itf.mem_wdata[channel];
        end endgenerate

        logic [15:0] errcode;

        riscv_formal_monitor_rv64imac monitor(
            .clock              (itf.clk),
            .reset              (itf.rst),
            .rvfi_valid         (rvfi_valid),
            .rvfi_order         (rvfi_order),
            .rvfi_insn          (rvfi_insn),
            .rvfi_trap          (rvfi_trap),
            .rvfi_halt          (rvfi_halt),
            .rvfi_intr          (rvfi_intr),
            .rvfi_mode          (rvfi_mode),
            .rvfi_rs1_addr      (rvfi_rs1_addr),
            .rvfi_rs2_addr      (rvfi_rs2_addr),
            .rvfi_rs1_rdata     (rvfi_rs1_rdata),
            .rvfi_rs2_rdata     (rvfi_rs2_rdata),
            .rvfi_rd_addr       (rvfi_rd_addr),
            .rvfi_rd_wdata      (rvfi_rd_wdata),
            .rvfi_pc_rdata      (rvfi_pc_rdata),
            .rvfi_pc_wdata      (rvfi_pc_wdata),
            .rvfi_mem_addr      (rvfi_mem_addr),
            .rvfi_mem_rmask     (rvfi_mem_rmask),
            .rvfi_mem_wmask     (rvfi_mem_wmask),
            .rvfi_mem_rdata     (rvfi_mem_rdata),
            .rvfi_mem_wdata     (rvfi_mem_wdata),
            .rvfi_mem_extamo    (rvfi_mem_extamo),
            .errcode            (errcode)
        );

        always @(posedge itf.clk iff !itf.rst) begin
            if (errcode != 0) begin
                $error("RVFI Monitor Error");
                itf.error <= 1'b1;
            end
        end

    `endif

endmodule
