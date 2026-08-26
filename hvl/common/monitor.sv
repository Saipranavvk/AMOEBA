module monitor #(
    parameter int CHANNELS = 1,
    parameter int XLEN = 64,
    parameter int ILEN = 32,
    parameter int MEM_BYTES = XLEN / 8
)(
    mon_itf itf
);

    function bit is_halt(input logic [31:0] inst);
`ifdef ECE411_LINUX
        // Both OpenSBI and the kernel contain self-branch park loops -- `j .`
        // (0x0000006f) and `beq zero,zero,.` (0x00000063) -- on paths a healthy
        // boot legitimately executes.  Only the explicit halt encoding may end
        // a Linux run; the UART matcher in top_tb.svh decides pass/fail.
        is_halt = (inst == 32'hf0002013);
`else
        is_halt = inst inside {32'h00000063, 32'h0000006f, 32'hf0002013};
`endif
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

    // UART TX capture — always-on, works with or without Spike DPI.
    //
    // Excluded from the Linux tier for two reasons.  It matches on
    // itf.mem_addr, which is driven from IEUAdrW -- a *virtual* address -- so it
    // silently stops capturing once Linux enables the MMU.  And top_tb.svh
    // already reconstructs the console from the UART peripheral itself, so
    // leaving this on interleaves a second, partial copy of every line into a
    // boot log that CI has to read.
`ifndef ECE411_LINUX
    always @(posedge itf.clk iff !itf.rst) begin
        for (int unsigned channel = 0; channel < CHANNELS; channel++) begin
            if (itf.valid[channel] &&
                itf.mem_wmask[channel][0] &&
                {itf.mem_addr[channel][63:3], 3'b000} == 64'h10000000)
                $write("%c", itf.mem_wdata[channel][7:0]);
        end
    end
`endif

    `ifndef ECE411_NO_SPIKE_DPI

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
                retval = spike_dpi_next(spike_dpi_rvfi_itf);
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

        riscv_formal_monitor_rv64imafdc_zb monitor(
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

        // The generated riscv-formal models cannot represent a misaligned data
        // access: spec_trap is hardcoded to (addr & (size-1)) != 0, and
        // spec_mem_rmask / spec_rd_wdata both assume one naturally-aligned
        // word.  CVW sets ZICCLSM_SUPPORTED and completes such accesses in
        // hardware, so the monitor's verdict on them carries no information.
        //
        // The verdict is ignored rather than the instruction skipped.  Gating
        // rvfi_valid was tried and does not work: the monitor keeps a shadow PC,
        // so dropping an instruction desynchronises it and the next checked
        // instruction fails with "mismatch with shadow pc".  Feeding every
        // instruction in keeps that state correct.
        //
        // The cost is that the waiver is a time window rather than exact -- the
        // error travels through rvfimon's own registers before reaching errcode,
        // so it cannot be tied to one cycle from out here.  A genuine error
        // raised within MISALIGN_WAIVER_DEPTH cycles of a misaligned access is
        // masked too; keep the depth as small as still clears a boot.
        localparam int MISALIGN_WAIVER_DEPTH = 16;

        logic [MISALIGN_WAIVER_DEPTH-1:0] misaligned_hist;
        always @(posedge itf.clk) begin
            if (itf.rst) misaligned_hist <= '0;
            else misaligned_hist <= {misaligned_hist[MISALIGN_WAIVER_DEPTH-2:0],
                                     itf.mem_misaligned[0]};
        end

        longint unsigned rvfi_waived_count = 0;

        always @(posedge itf.clk iff !itf.rst) begin
            if (errcode != 0) begin
                if (|misaligned_hist) rvfi_waived_count <= rvfi_waived_count + 1;
                else begin
                    $error("RVFI Monitor Error");
                    itf.error <= 1'b1;
                end
            end
        end

        final begin
            if (rvfi_waived_count != 0)
                $display("Monitor: %0d RVFI verdict(s) waived near a misaligned access (riscv-formal cannot model Zicclsm)",
                         rvfi_waived_count);
        end

    `endif

    // Unconditional heartbeat: prints every 100K cycles so simulation progress is visible.
    longint sim_heartbeat_cycle;
    logic [XLEN-1:0] heartbeat_last_pc = '0;
    initial sim_heartbeat_cycle = 0;
    always @(posedge itf.clk iff !itf.rst) begin
        sim_heartbeat_cycle = sim_heartbeat_cycle + 1;
        if (itf.valid[0]) heartbeat_last_pc <= itf.pc_rdata[0];
        if (sim_heartbeat_cycle % 100_000 == 0) begin
            // The PC turns the heartbeat into a sampling profiler.  Without it a
            // silent stretch of boot -- Linux can run tens of millions of cycles
            // between printk()s -- is indistinguishable from a hang, and the
            // retired-PC ring buffer only gets dumped on timeout.  Feed the
            // address to vmlinux's symbol table to see where the kernel is.
            $display("[SIM] Heartbeat: %0d cycles elapsed (time=%0t) pc=%016h",
                     sim_heartbeat_cycle, $time, heartbeat_last_pc);
            $fflush();
        end
    end

endmodule
