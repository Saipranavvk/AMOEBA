// Formal verification wrapper for CVW RV64GC
// Instantiates cvw_rvfi_wrapper and connects it to riscv_formal_monitor_rv64imc.
// SymbiYosys drives unconstrained inputs; assume constraints restrict the input space.
// Build with: sby -f checks.sby (from the formal/ directory)

module formal_wrapper (
    input logic clk,
    input logic rst
);

    // Memory interface between wrapper and memory stub
    logic [63:0] mem_addr;
    logic [7:0]  mem_rmask, mem_wmask;
    logic [63:0] mem_rdata, mem_wdata;
    logic        mem_resp;

    // RVFI signals from DUT
    logic        monitor_valid;
    logic [63:0] monitor_order;
    logic [31:0] monitor_inst;
    logic [4:0]  monitor_rs1_addr, monitor_rs2_addr, monitor_rd_addr;
    logic [63:0] monitor_rs1_rdata, monitor_rs2_rdata, monitor_rd_wdata;
    logic [63:0] monitor_pc_rdata, monitor_pc_wdata;
    logic [63:0] monitor_mem_addr;
    logic [7:0]  monitor_mem_rmask, monitor_mem_wmask;
    logic [63:0] monitor_mem_rdata, monitor_mem_wdata;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    cvw_rvfi_wrapper dut (
        .clk             (clk),
        .rst             (rst),
        .mem_addr        (mem_addr),
        .mem_rmask       (mem_rmask),
        .mem_wmask       (mem_wmask),
        .mem_rdata       (mem_rdata),
        .mem_wdata       (mem_wdata),
        .mem_resp        (mem_resp),
        .monitor_valid      (monitor_valid),
        .monitor_order      (monitor_order),
        .monitor_inst       (monitor_inst),
        .monitor_rs1_addr   (monitor_rs1_addr),
        .monitor_rs2_addr   (monitor_rs2_addr),
        .monitor_rs1_rdata  (monitor_rs1_rdata),
        .monitor_rs2_rdata  (monitor_rs2_rdata),
        .monitor_rd_addr    (monitor_rd_addr),
        .monitor_rd_wdata   (monitor_rd_wdata),
        .monitor_pc_rdata   (monitor_pc_rdata),
        .monitor_pc_wdata   (monitor_pc_wdata),
        .monitor_mem_addr   (monitor_mem_addr),
        .monitor_mem_rmask  (monitor_mem_rmask),
        .monitor_mem_wmask  (monitor_mem_wmask),
        .monitor_mem_rdata  (monitor_mem_rdata),
        .monitor_mem_wdata  (monitor_mem_wdata)
    );

    // -----------------------------------------------------------------------
    // Formal memory model: unconstrained read data, respond after 1 cycle
    // -----------------------------------------------------------------------
    logic [63:0] mem_rdata_free;  // unconstrained by solver
    logic        pending;

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_resp  <= 1'b0;
            mem_rdata <= '0;
            pending   <= 1'b0;
        end else begin
            if ((|mem_rmask || |mem_wmask) && !pending) begin
                pending  <= 1'b1;
            end
            if (pending) begin
                mem_resp  <= 1'b1;
                mem_rdata <= mem_rdata_free;
                pending   <= 1'b0;
            end else begin
                mem_resp  <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // RVFI monitor instantiation
    // -----------------------------------------------------------------------
    // Pack single-channel (ch0) RVFI signals into monitor bus
    // Channels 1-7 are tied to 0 (single-issue core)
    wire [15:0] errcode;

    riscv_formal_monitor_rv64imc monitor (
        .clock          (clk),
        .reset          (rst),
        .rvfi_valid     ({7'b0, monitor_valid}),
        .rvfi_order     ({448'b0, monitor_order}),
        .rvfi_insn      ({224'b0, monitor_inst}),
        .rvfi_trap      (8'b0),
        .rvfi_halt      (8'b0),
        .rvfi_intr      (8'b0),
        .rvfi_mode      (16'b0),
        .rvfi_rs1_addr  ({35'b0, monitor_rs1_addr}),
        .rvfi_rs2_addr  ({35'b0, monitor_rs2_addr}),
        .rvfi_rs1_rdata ({448'b0, monitor_rs1_rdata}),
        .rvfi_rs2_rdata ({448'b0, monitor_rs2_rdata}),
        .rvfi_rd_addr   ({35'b0, monitor_rd_addr}),
        .rvfi_rd_wdata  ({448'b0, monitor_rd_wdata}),
        .rvfi_pc_rdata  ({448'b0, monitor_pc_rdata}),
        .rvfi_pc_wdata  ({448'b0, monitor_pc_wdata}),
        .rvfi_mem_addr  ({448'b0, monitor_mem_addr}),
        .rvfi_mem_rmask ({56'b0, monitor_mem_rmask}),
        .rvfi_mem_wmask ({56'b0, monitor_mem_wmask}),
        .rvfi_mem_rdata ({448'b0, monitor_mem_rdata}),
        .rvfi_mem_wdata ({448'b0, monitor_mem_wdata}),
        .rvfi_mem_extamo(8'b0),
        .errcode        (errcode)
    );

    // -----------------------------------------------------------------------
    // Formal properties
    // -----------------------------------------------------------------------
    // Assert that no RVFI protocol violations occur
    always @(posedge clk) begin
        if (!rst) begin
            assert (errcode == 16'b0) else $error("RVFI monitor error: %h", errcode);
        end
    end

    // Assume reset is de-asserted after a bounded prefix
    // (allows SymbiYosys to explore post-reset behavior)
    logic [3:0] rst_cnt;
    always_ff @(posedge clk) begin
        if (rst) rst_cnt <= '0;
        else     rst_cnt <= rst_cnt + 1;
    end
    // After 4 cycles of non-reset, assume rst stays low
    always @(posedge clk) begin
        if (&rst_cnt) assume (!rst);
    end

endmodule
