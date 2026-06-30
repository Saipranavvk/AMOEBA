module rv64_core_wrapper (
    input  logic        clk,
    input  logic        rst,

    output logic [63:0] mem_addr,
    output logic [7:0]  mem_rmask,
    output logic [7:0]  mem_wmask,
    input  logic [63:0] mem_rdata,
    output logic [63:0] mem_wdata,
    input  logic        mem_resp,

    output logic        monitor_valid,
    output logic [63:0] monitor_order,
    output logic [31:0] monitor_inst,
    output logic        monitor_trap,
    output logic        monitor_intr,
    output logic [1:0]  monitor_mode,
    output logic [1:0]  monitor_ixl,

    output logic [4:0]  monitor_rs1_addr,
    output logic [4:0]  monitor_rs2_addr,
    output logic [63:0] monitor_rs1_rdata,
    output logic [63:0] monitor_rs2_rdata,
    output logic [4:0]  monitor_rd_addr,
    output logic [63:0] monitor_rd_wdata,

    output logic [63:0] monitor_pc_rdata,
    output logic [63:0] monitor_pc_wdata,
    output logic [63:0] monitor_mem_addr,
    output logic [7:0]  monitor_mem_rmask,
    output logic [7:0]  monitor_mem_wmask,
    output logic [63:0] monitor_mem_rdata,
    output logic [63:0] monitor_mem_wdata,
    output logic        monitor_mem_extamo,

    output logic [7:0]   mstatus_rmask,
    output logic [7:0]   mstatus_wmask,
    input  logic [63:0]  mstatus_rdata,
    output logic [63:0]  mstatus_wdata,
    
    output logic [7:0]   misa_rmask,
    output logic [7:0]   misa_wmask,
    input  logic [63:0]  misa_rdata,
    output logic [63:0]  misa_wdata,

    output logic [7:0]   mie_rmask,
    output logic [7:0]   mie_wmask,
    input  logic [63:0]  mie_rdata,
    output logic [63:0]  mie_wdata,

    output logic [7:0]   mtvec_rmask,
    output logic [7:0]   mtvec_wmask,
    input  logic [63:0]  mtvec_rdata,
    output logic [63:0]  mtvec_wdata,

    output logic [7:0]   mscratch_rmask,
    output logic [7:0]   mscratch_wmask,
    input  logic [63:0]  mscratch_rdata,
    output logic [63:0]  mscratch_wdata,

    output logic [7:0]   mepc_rmask,
    output logic [7:0]   mepc_wmask,
    input  logic [63:0]  mepc_rdata,
    output logic [63:0]  mepc_wdata,

    output logic [7:0]   mcause_rmask,
    output logic [7:0]   mcause_wmask,
    input  logic [63:0]  mcause_rdata,
    output logic [63:0]  mcause_wdata,

    output logic [7:0]   mtval_rmask,
    output logic [7:0]   mtval_wmask,
    input  logic [63:0]  mtval_rdata,
    output logic [63:0]  mtval_wdata,
    
    output logic [7:0]   mip_rmask,
    output logic [7:0]   mip_wmask,
    input  logic [63:0]  mip_rdata,
    output logic [63:0]  mip_wdata,

    output logic [7:0]   mcycle_rmask,
    output logic [7:0]   mcycle_wmask,
    input  logic [63:0]  mcycle_rdata,
    output logic [63:0]  mcycle_wdata,

    output logic [7:0]   minstret_rmask,
    output logic [7:0]   minstret_wmask,
    input  logic [63:0]  minstret_rdata,
    output logic [63:0]  minstret_wdata
);