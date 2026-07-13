// AHB-Lite slave adapter bridging CVW's external AHB-Lite master to a mem_itf_w_mask port.
// Only responds when HSEL=1 (selected by address decoder). Returns HREADY=1 immediately otherwise.
// Only supports NONSEQ single transfers (no bursts, no lock).
// HSIZE controls which byte lanes are active; HADDR[2:0] selects offset within the 8-byte word.
module ahb_to_memitf #(
    parameter AHB_PA_BITS = 56
)(
    // AHB-Lite slave inputs (from CVW SoC)
    input  logic                clk,
    input  logic                HRESETn,
    input  logic                HSEL,     // slave select from AHB decoder
    input  logic [AHB_PA_BITS-1:0]  HADDR,
    input  logic [1:0]          HTRANS,   // 00=IDLE 10=NONSEQ
    input  logic                HWRITE,
    input  logic [2:0]          HSIZE,
    input  logic [63:0]         HWDATA,
    input  logic [7:0]          HWSTRB,
    // AHB-Lite slave outputs
    output logic [63:0]         HRDATA,
    output logic                HREADY,
    output logic                HRESP,
    // mem_itf_w_mask port (single channel)
    output logic [63:0]         mem_addr,
    output logic [7:0]          mem_rmask,
    output logic [7:0]          mem_wmask,
    output logic [63:0]         mem_wdata,
    input  logic [63:0]         mem_rdata,
    input  logic                mem_resp
);

    localparam HTRANS_IDLE   = 2'b00;
    localparam HTRANS_BUSY   = 2'b01;
    localparam HTRANS_NONSEQ = 2'b10;
    localparam HTRANS_SEQ    = 2'b11;

    typedef enum logic [1:0] {
        S_IDLE,
        S_READ,
        S_WRITE
    } state_t;

    state_t state;

    logic [AHB_PA_BITS-1:0] addr_r;
    logic               write_r;
    logic [2:0]         size_r;

    function automatic logic [7:0] size_to_mask(input logic [2:0] hsize, input logic [2:0] offset);
        logic [7:0] m;
        m = '0;
        case (hsize)
            3'b000: m = 8'h01 << offset;
            3'b001: m = 8'h03 << {offset[2:1], 1'b0};
            3'b010: m = 8'h0F << {offset[2], 2'b0};
            3'b011: m = 8'hFF;
            default: m = 8'hFF;
        endcase
        return m;
    endfunction

    always_ff @(posedge clk or negedge HRESETn) begin
        if (!HRESETn) begin
            state     <= S_IDLE;
            HREADY    <= 1'b1;
            HRDATA    <= '0;
            mem_addr  <= '0;
            mem_rmask <= '0;
            mem_wmask <= '0;
            mem_wdata <= '0;
        end else begin
            case (state)
            S_IDLE: begin
                mem_rmask <= '0;
                mem_wmask <= '0;
                if (HSEL && (HTRANS == HTRANS_NONSEQ || HTRANS == HTRANS_SEQ)) begin
                    addr_r  <= HADDR;
                    write_r <= HWRITE;
                    size_r  <= HSIZE;
                    if (!HWRITE) begin
                        mem_addr  <= 64'({HADDR[AHB_PA_BITS-1:3], 3'b000});
                        mem_rmask <= size_to_mask(HSIZE, HADDR[2:0]);
                        HREADY    <= 1'b0;
                        state     <= S_READ;
                    end else begin
                        HREADY <= 1'b0;
                        state  <= S_WRITE;
                    end
                end
            end
            S_READ: begin
                if (mem_resp) begin
                    HRDATA    <= mem_rdata;
                    mem_rmask <= '0;
                    HREADY    <= 1'b1;
                    state     <= S_IDLE;
                end
            end
            S_WRITE: begin
                mem_addr  <= 64'({addr_r[AHB_PA_BITS-1:3], 3'b000});
                mem_wmask <= HWSTRB != '0 ? HWSTRB : size_to_mask(size_r, addr_r[2:0]);
                mem_wdata <= HWDATA;
                if (mem_resp) begin
                    mem_wmask <= '0;
                    HREADY    <= 1'b1;
                    state     <= S_IDLE;
                end
            end
            endcase
        end
    end

    assign HRESP = 1'b0;

endmodule
