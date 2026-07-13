module simple_memory_w_mask #(
    parameter DELAY = 3,
    parameter int AWIDTH = 64,
    parameter int DWIDTH = 64,
    parameter int MWIDTH = DWIDTH / 8
    )(
    mem_itf_w_mask.mem itf
);

    string memfile;
    initial begin
        $value$plusargs("MEMLST_ECE411=%s", memfile);
    end

    logic [DWIDTH-1:0] internal_memory_array [logic [DWIDTH-1:3]];

    enum int {
        MEMORY_STATE_IDLE,
        MEMORY_STATE_READ,
        MEMORY_STATE_WRITE
    } state;

    int delay_counter;

    always_ff @(posedge itf.clk) begin
        if (itf.rst) begin
            internal_memory_array.delete();
            $readmemh(memfile, internal_memory_array);
            $display("using memory file %s", memfile);
            state <= MEMORY_STATE_IDLE;
            delay_counter <= '0;
            itf.resp[0] <= 1'b0;
            itf.rdata[0] <= 'x;
        end else begin
            itf.resp[0] <= 1'b0;
            itf.rdata[0] <= 'x;
            unique case (state)
            MEMORY_STATE_IDLE: begin
            if (|itf.rmask[0]) begin
                state <= MEMORY_STATE_READ;
                delay_counter <= DELAY;
            end
            
            if (|itf.wmask[0]) begin
                state <= MEMORY_STATE_WRITE;
                delay_counter <= DELAY;
            end
            end
            MEMORY_STATE_READ: begin
                if (delay_counter == 2) begin
                    automatic logic [DWIDTH-1:0] rdata_xmask;
                    itf.resp[0] <= 1'b1;
                    for (int i = 0; i < MWIDTH; i++) begin
                        if (itf.rmask[0][i]) begin
                            rdata_xmask[i*8 +: 8] = '0;
                        end else begin
                            rdata_xmask[i*8 +: 8] = 'x;
                        end
                    end
                    itf.rdata[0] <= internal_memory_array[itf.addr[0][DWIDTH-1:3]] ^ rdata_xmask;
                end
                if (delay_counter == 1) begin
                    state <= MEMORY_STATE_IDLE;
                end
                delay_counter <= delay_counter - 1;
            end
            MEMORY_STATE_WRITE: begin
                if (delay_counter == 2) begin
                    itf.resp[0] <= 1'b1;
                end
                if (delay_counter == 1) begin
                    for (int i = 0; i < MWIDTH; i++) begin
                        if (itf.wmask[0][i]) begin
                            internal_memory_array[itf.addr[0][DWIDTH-1:3]][i*8 +: 8] = itf.wdata[0][i*8 +: 8];
                        end
                    end
                    state <= MEMORY_STATE_IDLE;
                end
                delay_counter <= delay_counter - 1;
            end
            endcase
        end
    end

    logic [AWIDTH-1:0] cached_addr;
    logic [MWIDTH-1:0] cached_mask;

    always_ff @(posedge itf.clk) begin
        if (|itf.rmask[0]) begin
            cached_addr <= itf.addr[0];
            cached_mask <= itf.rmask[0];
        end
        if (|itf.wmask[0]) begin
            cached_addr <= itf.addr[0];
            cached_mask <= itf.wmask[0];
        end
    end

    always @(posedge itf.clk iff !itf.rst) begin
        if ($isunknown(itf.rmask[0]) || $isunknown(itf.wmask[0])) begin
            $error("Memory Error: mask containes 'x");
            itf.error <= 1'b1;
        end
        if ((|itf.rmask[0]) && (|itf.wmask[0])) begin
            $error("Memory Error: simultaneous memory read and write");
            itf.error <= 1'b1;
        end
        if ((|itf.rmask[0]) || (|itf.wmask[0])) begin
            if ($isunknown(itf.addr[0])) begin
                $error("Memory Error: address contained 'x");
                itf.error <= 1'b1;
            end
            if (itf.addr[0][2:0] != 3'b000) begin
                $error("Memory Error: address is not 64-bit aligned");
                itf.error <= 1'b1;
            end
        end

        case (state)
        MEMORY_STATE_READ: begin
            if (itf.addr[0] != cached_addr) begin
                $error("Memory Error: address changed");
                itf.error <= 1'b1;
            end
            if (itf.rmask[0] != cached_mask) begin
                $error("Memory Error: mask changed");
                itf.error <= 1'b1;
            end
        end
        MEMORY_STATE_WRITE: begin
            if (itf.addr[0] != cached_addr) begin
                $error("Memory Error: address changed");
                itf.error <= 1'b1;
            end
            if (itf.wmask[0] != cached_mask) begin
                $error("Memory Error: mask changed");
                itf.error <= 1'b1;
            end
        end
        endcase
    end

endmodule
