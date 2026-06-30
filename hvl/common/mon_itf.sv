interface mon_itf #(
    parameter int CHANNELS = 1,
    parameter int XLEN = 64,
    parameter int ILEN = 32,
    parameter int MEM_BYTES = XLEN / 8
)(
    input bit clk,
    input bit rst
);

            logic               valid      [CHANNELS];
            logic [63:0]        order      [CHANNELS];
            logic [ILEN-1:0]    inst       [CHANNELS];
            logic               trap       [CHANNELS];
            logic               intr       [CHANNELS];
            logic [1:0]         mode       [CHANNELS];
            logic [1:0]         ixl        [CHANNELS];
            logic               mem_extamo [CHANNELS];

            logic [4:0]         rs1_addr   [CHANNELS];
            logic [4:0]         rs2_addr   [CHANNELS];
            logic [XLEN-1:0]    rs1_rdata  [CHANNELS];
            logic [XLEN-1:0]    rs2_rdata  [CHANNELS];
            logic [4:0]         rd_addr    [CHANNELS];
            logic [XLEN-1:0]    rd_wdata   [CHANNELS];

            logic [XLEN-1:0]    pc_rdata   [CHANNELS];
            logic [XLEN-1:0]    pc_wdata   [CHANNELS];
            logic [XLEN-1:0]    mem_addr   [CHANNELS];
            logic [MEM_BYTES-1:0] mem_rmask [CHANNELS];
            logic [MEM_BYTES-1:0] mem_wmask [CHANNELS];
            logic [XLEN-1:0]    mem_rdata  [CHANNELS];
            logic [XLEN-1:0]    mem_wdata  [CHANNELS];

            bit             halt  = 1'b0;
            bit             error = 1'b0;

endinterface
