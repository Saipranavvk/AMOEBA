// DO NOT EDIT -- auto-generated from riscv-formal/monitor/generate.py
//
// Command line options: -i rv64imac -a -r 1 -c 1

module riscv_formal_monitor_rv64imac (
  input clock,
  input reset,
  input [0:0] rvfi_valid,
  input [63:0] rvfi_order,
  input [31:0] rvfi_insn,
  input [0:0] rvfi_trap,
  input [0:0] rvfi_halt,
  input [0:0] rvfi_intr,
  input [1:0] rvfi_mode,
  input [4:0] rvfi_rs1_addr,
  input [4:0] rvfi_rs2_addr,
  input [63:0] rvfi_rs1_rdata,
  input [63:0] rvfi_rs2_rdata,
  input [4:0] rvfi_rd_addr,
  input [63:0] rvfi_rd_wdata,
  input [63:0] rvfi_pc_rdata,
  input [63:0] rvfi_pc_wdata,
  input [63:0] rvfi_mem_addr,
  input [7:0] rvfi_mem_rmask,
  input [7:0] rvfi_mem_wmask,
  input [63:0] rvfi_mem_rdata,
  input [63:0] rvfi_mem_wdata,
  input [0:0] rvfi_mem_extamo,
  output reg [15:0] errcode
);
  wire ch0_rvfi_valid = rvfi_valid[0];
  wire [63:0] ch0_rvfi_order = rvfi_order[63:0];
  wire [31:0] ch0_rvfi_insn = rvfi_insn[31:0];
  wire ch0_rvfi_trap = rvfi_trap[0];
  wire ch0_rvfi_halt = rvfi_halt[0];
  wire ch0_rvfi_intr = rvfi_intr[0];
  wire [4:0] ch0_rvfi_rs1_addr = rvfi_rs1_addr[4:0];
  wire [4:0] ch0_rvfi_rs2_addr = rvfi_rs2_addr[4:0];
  wire [63:0] ch0_rvfi_rs1_rdata = rvfi_rs1_rdata[63:0];
  wire [63:0] ch0_rvfi_rs2_rdata = rvfi_rs2_rdata[63:0];
  wire [4:0] ch0_rvfi_rd_addr = rvfi_rd_addr[4:0];
  wire [63:0] ch0_rvfi_rd_wdata = rvfi_rd_wdata[63:0];
  wire [63:0] ch0_rvfi_pc_rdata = rvfi_pc_rdata[63:0];
  wire [63:0] ch0_rvfi_pc_wdata = rvfi_pc_wdata[63:0];
  wire [63:0] ch0_rvfi_mem_addr = rvfi_mem_addr[63:0];
  wire [7:0] ch0_rvfi_mem_rmask = rvfi_mem_rmask[7:0];
  wire [7:0] ch0_rvfi_mem_wmask = rvfi_mem_wmask[7:0];
  wire [63:0] ch0_rvfi_mem_rdata = rvfi_mem_rdata[63:0];
  wire [63:0] ch0_rvfi_mem_wdata = rvfi_mem_wdata[63:0];
  wire ch0_rvfi_mem_extamo = rvfi_mem_extamo[0];

  wire ch0_spec_valid;
  wire ch0_spec_trap;
  wire [4:0] ch0_spec_rs1_addr;
  wire [4:0] ch0_spec_rs2_addr;
  wire [4:0] ch0_spec_rd_addr;
  wire [63:0] ch0_spec_rd_wdata;
  wire [63:0] ch0_spec_pc_wdata;
  wire [63:0] ch0_spec_mem_addr;
  wire [7:0] ch0_spec_mem_rmask;
  wire [7:0] ch0_spec_mem_wmask;
  wire [63:0] ch0_spec_mem_wdata;

  riscv_formal_monitor_rv64imac_isa_spec ch0_isa_spec (
    .rvfi_valid(ch0_rvfi_valid),
    .rvfi_insn(ch0_rvfi_insn),
    .rvfi_pc_rdata(ch0_rvfi_pc_rdata),
    .rvfi_rs1_rdata(ch0_rvfi_rs1_rdata),
    .rvfi_rs2_rdata(ch0_rvfi_rs2_rdata),
    .rvfi_mem_rdata(ch0_rvfi_mem_rdata),
    .spec_valid(ch0_spec_valid),
    .spec_trap(ch0_spec_trap),
    .spec_rs1_addr(ch0_spec_rs1_addr),
    .spec_rs2_addr(ch0_spec_rs2_addr),
    .spec_rd_addr(ch0_spec_rd_addr),
    .spec_rd_wdata(ch0_spec_rd_wdata),
    .spec_pc_wdata(ch0_spec_pc_wdata),
    .spec_mem_addr(ch0_spec_mem_addr),
    .spec_mem_rmask(ch0_spec_mem_rmask),
    .spec_mem_wmask(ch0_spec_mem_wmask),
    .spec_mem_wdata(ch0_spec_mem_wdata)
  );

  reg [15:0] ch0_errcode;

  task ch0_handle_error;
    input [15:0] code;
    input [511:0] msg;
    begin
      $display("-------- RVFI Monitor error %0d in channel 0: %m at time %0t --------", code, $time);
      $display("Error message: %0s", msg);
      $display("rvfi_valid = %x", ch0_rvfi_valid);
      $display("rvfi_order = %x", ch0_rvfi_order);
      $display("rvfi_insn = %x", ch0_rvfi_insn);
      $display("rvfi_trap = %x", ch0_rvfi_trap);
      $display("rvfi_halt = %x", ch0_rvfi_halt);
      $display("rvfi_intr = %x", ch0_rvfi_intr);
      $display("rvfi_rs1_addr = %x", ch0_rvfi_rs1_addr);
      $display("rvfi_rs2_addr = %x", ch0_rvfi_rs2_addr);
      $display("rvfi_rs1_rdata = %x", ch0_rvfi_rs1_rdata);
      $display("rvfi_rs2_rdata = %x", ch0_rvfi_rs2_rdata);
      $display("rvfi_rd_addr = %x", ch0_rvfi_rd_addr);
      $display("rvfi_rd_wdata = %x", ch0_rvfi_rd_wdata);
      $display("rvfi_pc_rdata = %x", ch0_rvfi_pc_rdata);
      $display("rvfi_pc_wdata = %x", ch0_rvfi_pc_wdata);
      $display("rvfi_mem_addr = %x", ch0_rvfi_mem_addr);
      $display("rvfi_mem_rmask = %x", ch0_rvfi_mem_rmask);
      $display("rvfi_mem_wmask = %x", ch0_rvfi_mem_wmask);
      $display("rvfi_mem_rdata = %x", ch0_rvfi_mem_rdata);
      $display("rvfi_mem_wdata = %x", ch0_rvfi_mem_wdata);
      $display("spec_valid = %x", ch0_spec_valid);
      $display("spec_trap = %x", ch0_spec_trap);
      $display("spec_rs1_addr = %x", ch0_spec_rs1_addr);
      $display("spec_rs2_addr = %x", ch0_spec_rs2_addr);
      $display("spec_rd_addr = %x", ch0_spec_rd_addr);
      $display("spec_rd_wdata = %x", ch0_spec_rd_wdata);
      $display("spec_pc_wdata = %x", ch0_spec_pc_wdata);
      $display("spec_mem_addr = %x", ch0_spec_mem_addr);
      $display("spec_mem_rmask = %x", ch0_spec_mem_rmask);
      $display("spec_mem_wmask = %x", ch0_spec_mem_wmask);
      $display("spec_mem_wdata = %x", ch0_spec_mem_wdata);
      ch0_errcode <= code;
    end
  endtask

  always @(posedge clock) begin
    ch0_errcode <= 0;
    if (!reset && ch0_rvfi_valid) begin
      if (ch0_spec_valid) begin
        if (ch0_rvfi_trap != ch0_spec_trap) begin
          ch0_handle_error(101, "mismatch in trap");
        end
        if (ch0_rvfi_rs1_addr != ch0_spec_rs1_addr && ch0_spec_rs1_addr != 0) begin
          ch0_handle_error(102, "mismatch in rs1_addr");
        end
        if (ch0_rvfi_rs2_addr != ch0_spec_rs2_addr && ch0_spec_rs2_addr != 0) begin
          ch0_handle_error(103, "mismatch in rs2_addr");
        end
        if (ch0_rvfi_rd_addr != ch0_spec_rd_addr) begin
          ch0_handle_error(104, "mismatch in rd_addr");
        end
        if (ch0_rvfi_rd_wdata != ch0_spec_rd_wdata) begin
          ch0_handle_error(105, "mismatch in rd_wdata");
        end
        if (ch0_rvfi_pc_wdata != ch0_spec_pc_wdata) begin
          ch0_handle_error(106, "mismatch in pc_wdata");
        end
        if (ch0_rvfi_mem_wmask != ch0_spec_mem_wmask) begin
          ch0_handle_error(108, "mismatch in mem_wmask");
        end
        if (!ch0_rvfi_mem_rmask[0] && ch0_spec_mem_rmask[0]) begin
          ch0_handle_error(110, "mismatch in mem_rmask[0]");
        end
        if (ch0_rvfi_mem_wmask[0] && ch0_rvfi_mem_wdata[7:0] != ch0_spec_mem_wdata[7:0]) begin
          ch0_handle_error(120, "mismatch in mem_wdata[7:0]");
        end
        if (!ch0_rvfi_mem_rmask[1] && ch0_spec_mem_rmask[1]) begin
          ch0_handle_error(111, "mismatch in mem_rmask[1]");
        end
        if (ch0_rvfi_mem_wmask[1] && ch0_rvfi_mem_wdata[15:8] != ch0_spec_mem_wdata[15:8]) begin
          ch0_handle_error(121, "mismatch in mem_wdata[15:8]");
        end
        if (!ch0_rvfi_mem_rmask[2] && ch0_spec_mem_rmask[2]) begin
          ch0_handle_error(112, "mismatch in mem_rmask[2]");
        end
        if (ch0_rvfi_mem_wmask[2] && ch0_rvfi_mem_wdata[23:16] != ch0_spec_mem_wdata[23:16]) begin
          ch0_handle_error(122, "mismatch in mem_wdata[23:16]");
        end
        if (!ch0_rvfi_mem_rmask[3] && ch0_spec_mem_rmask[3]) begin
          ch0_handle_error(113, "mismatch in mem_rmask[3]");
        end
        if (ch0_rvfi_mem_wmask[3] && ch0_rvfi_mem_wdata[31:24] != ch0_spec_mem_wdata[31:24]) begin
          ch0_handle_error(123, "mismatch in mem_wdata[31:24]");
        end
        if (!ch0_rvfi_mem_rmask[4] && ch0_spec_mem_rmask[4]) begin
          ch0_handle_error(114, "mismatch in mem_rmask[4]");
        end
        if (ch0_rvfi_mem_wmask[4] && ch0_rvfi_mem_wdata[39:32] != ch0_spec_mem_wdata[39:32]) begin
          ch0_handle_error(124, "mismatch in mem_wdata[39:32]");
        end
        if (!ch0_rvfi_mem_rmask[5] && ch0_spec_mem_rmask[5]) begin
          ch0_handle_error(115, "mismatch in mem_rmask[5]");
        end
        if (ch0_rvfi_mem_wmask[5] && ch0_rvfi_mem_wdata[47:40] != ch0_spec_mem_wdata[47:40]) begin
          ch0_handle_error(125, "mismatch in mem_wdata[47:40]");
        end
        if (!ch0_rvfi_mem_rmask[6] && ch0_spec_mem_rmask[6]) begin
          ch0_handle_error(116, "mismatch in mem_rmask[6]");
        end
        if (ch0_rvfi_mem_wmask[6] && ch0_rvfi_mem_wdata[55:48] != ch0_spec_mem_wdata[55:48]) begin
          ch0_handle_error(126, "mismatch in mem_wdata[55:48]");
        end
        if (!ch0_rvfi_mem_rmask[7] && ch0_spec_mem_rmask[7]) begin
          ch0_handle_error(117, "mismatch in mem_rmask[7]");
        end
        if (ch0_rvfi_mem_wmask[7] && ch0_rvfi_mem_wdata[63:56] != ch0_spec_mem_wdata[63:56]) begin
          ch0_handle_error(127, "mismatch in mem_wdata[63:56]");
        end
        if (ch0_rvfi_mem_addr != ch0_spec_mem_addr && (ch0_rvfi_mem_wmask || ch0_rvfi_mem_rmask)) begin
          ch0_handle_error(107, "mismatch in mem_addr");
        end
      end
    end
  end

  wire rob_i0_valid;
  wire [63:0] rob_i0_order;
  wire [336:0] rob_i0_data;

  wire rob_o0_valid;
  wire [63:0] rob_o0_order;
  wire [336:0] rob_o0_data;

  wire ro0_rvfi_valid = rob_o0_valid;
  assign rob_i0_valid = ch0_rvfi_valid;

  wire [63:0] ro0_rvfi_order = rob_o0_order;
  assign rob_i0_order = ch0_rvfi_order;

  wire [4:0] ro0_rvfi_rs1_addr = rob_o0_data[4:0];
  assign rob_i0_data[4:0] = ch0_rvfi_rs1_addr;

  wire [4:0] ro0_rvfi_rs2_addr = rob_o0_data[9:5];
  assign rob_i0_data[9:5] = ch0_rvfi_rs2_addr;

  wire [4:0] ro0_rvfi_rd_addr = rob_o0_data[14:10];
  assign rob_i0_data[14:10] = ch0_rvfi_rd_addr;

  wire [63:0] ro0_rvfi_rs1_rdata = rob_o0_data[78:15];
  assign rob_i0_data[78:15] = ch0_rvfi_rs1_rdata;

  wire [63:0] ro0_rvfi_rs2_rdata = rob_o0_data[142:79];
  assign rob_i0_data[142:79] = ch0_rvfi_rs2_rdata;

  wire [63:0] ro0_rvfi_rd_wdata = rob_o0_data[206:143];
  assign rob_i0_data[206:143] = ch0_rvfi_rd_wdata;

  wire [63:0] ro0_rvfi_pc_rdata = rob_o0_data[270:207];
  assign rob_i0_data[270:207] = ch0_rvfi_pc_rdata;

  wire [63:0] ro0_rvfi_pc_wdata = rob_o0_data[334:271];
  assign rob_i0_data[334:271] = ch0_rvfi_pc_wdata;

  wire [0:0] ro0_rvfi_intr = rob_o0_data[335:335];
  assign rob_i0_data[335:335] = ch0_rvfi_intr;

  wire [0:0] ro0_rvfi_trap = rob_o0_data[336:336];
  assign rob_i0_data[336:336] = ch0_rvfi_trap;

  wire [15:0] rob_errcode;

  riscv_formal_monitor_rv64imac_rob rob (
    .clock(clock),
    .reset(reset),
    .i0_valid(rob_i0_valid),
    .i0_order(rob_i0_order),
    .i0_data(rob_i0_data),
    .o0_valid(rob_o0_valid),
    .o0_order(rob_o0_order),
    .o0_data(rob_o0_data),
    .errcode(rob_errcode)
  );

  always @(posedge clock) begin
    if (!reset && rob_errcode) begin
      $display("-------- RVFI Monitor ROB error %0d: %m at time %0t --------", rob_errcode, $time);
      $display("No details on ROB errors available.");
    end
  end

  reg shadow_pc_valid;
  reg shadow_pc_trap;
  reg [63:0] shadow_pc;

  reg shadow0_pc_valid;
  reg shadow0_pc_trap;
  reg [63:0] shadow0_pc_rdata;

  reg [15:0] ro0_errcode_p;

  task ro0_handle_error_p;
    input [15:0] code;
    input [511:0] msg;
    begin
      $display("-------- RVFI Monitor error %0d in reordered channel 0: %m at time %0t --------", code, $time);
      $display("Error message: %0s", msg);
      $display("rvfi_valid = %x", ro0_rvfi_valid);
      $display("rvfi_order = %x", ro0_rvfi_order);
      $display("rvfi_rs1_addr = %x", ro0_rvfi_rs1_addr);
      $display("rvfi_rs2_addr = %x", ro0_rvfi_rs2_addr);
      $display("rvfi_rs1_rdata = %x", ro0_rvfi_rs1_rdata);
      $display("rvfi_rs2_rdata = %x", ro0_rvfi_rs2_rdata);
      $display("rvfi_rd_addr = %x", ro0_rvfi_rd_addr);
      $display("rvfi_rd_wdata = %x", ro0_rvfi_rd_wdata);
      $display("rvfi_pc_rdata = %x", ro0_rvfi_pc_rdata);
      $display("rvfi_pc_wdata = %x", ro0_rvfi_pc_wdata);
      $display("rvfi_intr = %x", ro0_rvfi_intr);
      $display("rvfi_trap = %x", ro0_rvfi_trap);
      $display("shadow_pc_valid = %x", shadow0_pc_valid);
      $display("shadow_pc_rdata = %x", shadow0_pc_rdata);
      ro0_errcode_p <= code;
    end
  endtask

  always @* begin
    shadow0_pc_valid = shadow_pc_valid;
    shadow0_pc_trap = shadow_pc_trap;
    shadow0_pc_rdata = shadow_pc;
  end

  always @(posedge clock) begin
    ro0_errcode_p <= 0;
    if (reset) begin
      shadow_pc_valid <= 0;
      shadow_pc_trap <= 0;
    end
    if (!reset && ro0_rvfi_valid) begin
      if (shadow0_pc_valid && shadow0_pc_rdata != ro0_rvfi_pc_rdata && !ro0_rvfi_intr) begin
        ro0_handle_error_p(130, "mismatch with shadow pc");
      end
      if (shadow0_pc_valid && shadow0_pc_trap && !ro0_rvfi_intr) begin
        ro0_handle_error_p(133, "expected intr after trap");
      end
      shadow_pc_valid <= !ro0_rvfi_trap;
      shadow_pc_trap <= ro0_rvfi_trap;
      shadow_pc <= ro0_rvfi_pc_wdata;
    end
  end

  reg [31:0] shadow_xregs_valid;
  reg [63:0] shadow_xregs [0:31];

  reg shadow0_rs1_valid;
  reg shadow0_rs2_valid;
  reg [63:0] shadow0_rs1_rdata;
  reg [63:0] shadow0_rs2_rdata;

  reg [15:0] ro0_errcode_r;

  task ro0_handle_error_r;
    input [15:0] code;
    input [511:0] msg;
    begin
      $display("-------- RVFI Monitor error %0d in reordered channel 0: %m at time %0t --------", code, $time);
      $display("Error message: %0s", msg);
      $display("rvfi_valid = %x", ro0_rvfi_valid);
      $display("rvfi_order = %x", ro0_rvfi_order);
      $display("rvfi_rs1_addr = %x", ro0_rvfi_rs1_addr);
      $display("rvfi_rs2_addr = %x", ro0_rvfi_rs2_addr);
      $display("rvfi_rs1_rdata = %x", ro0_rvfi_rs1_rdata);
      $display("rvfi_rs2_rdata = %x", ro0_rvfi_rs2_rdata);
      $display("rvfi_rd_addr = %x", ro0_rvfi_rd_addr);
      $display("rvfi_rd_wdata = %x", ro0_rvfi_rd_wdata);
      $display("rvfi_pc_rdata = %x", ro0_rvfi_pc_rdata);
      $display("rvfi_pc_wdata = %x", ro0_rvfi_pc_wdata);
      $display("rvfi_intr = %x", ro0_rvfi_intr);
      $display("rvfi_trap = %x", ro0_rvfi_trap);
      $display("shadow_rs1_valid = %x", shadow0_rs1_valid);
      $display("shadow_rs1_rdata = %x", shadow0_rs1_rdata);
      $display("shadow_rs2_valid = %x", shadow0_rs2_valid);
      $display("shadow_rs2_rdata = %x", shadow0_rs2_rdata);
      ro0_errcode_r <= code;
    end
  endtask

  always @* begin
    shadow0_rs1_valid = 0;
    shadow0_rs1_rdata = 0;
    if (!reset && ro0_rvfi_valid) begin
      shadow0_rs1_valid = shadow_xregs_valid[ro0_rvfi_rs1_addr];
      shadow0_rs1_rdata = shadow_xregs[ro0_rvfi_rs1_addr];
    end
  end

  always @* begin
    shadow0_rs2_valid = 0;
    shadow0_rs2_rdata = 0;
    if (!reset && ro0_rvfi_valid) begin
      shadow0_rs2_valid = shadow_xregs_valid[ro0_rvfi_rs2_addr];
      shadow0_rs2_rdata = shadow_xregs[ro0_rvfi_rs2_addr];
    end
  end

  always @(posedge clock) begin
    ro0_errcode_r <= 0;
    if (reset) begin
      shadow_xregs_valid <= 1;
      shadow_xregs[0] <= 0;
    end
    if (!reset && ro0_rvfi_valid) begin
      if (shadow0_rs1_valid && shadow0_rs1_rdata != ro0_rvfi_rs1_rdata) begin
        ro0_handle_error_r(131, "mismatch with shadow rs1");
      end
      if (shadow0_rs2_valid && shadow0_rs2_rdata != ro0_rvfi_rs2_rdata) begin
        ro0_handle_error_r(132, "mismatch with shadow rs2");
      end
      shadow_xregs_valid[ro0_rvfi_rd_addr] <= 1;
      shadow_xregs[ro0_rvfi_rd_addr] <= ro0_rvfi_rd_wdata;
    end
  end

  always @(posedge clock) begin
    errcode <= 0;
    if (!reset) begin
      if (ch0_errcode) errcode <= ch0_errcode;
      if (rob_errcode) errcode <= rob_errcode;
      if (ro0_errcode_p) errcode <= ro0_errcode_p;
      if (ro0_errcode_r) errcode <= ro0_errcode_r;
    end
  end
endmodule

module riscv_formal_monitor_rv64imac_rob (
  input clock,
  input reset,
    input i0_valid,
    input [63:0] i0_order,
    input [336:0] i0_data,
    output reg o0_valid,
    output reg [63:0] o0_order,
    output reg [336:0] o0_data,
  output reg [15:0] errcode
);
  reg [400:0] buffer [0:0];
  reg [0:0] valid;
  reg [63:0] cursor;
  reg continue_flag;

  always @(posedge clock) begin
    o0_valid <= 0;
    errcode <= 0;
    continue_flag = 1;
    if (reset) begin
      valid <= 0;
      cursor = 0;
    end else begin
      if (i0_valid) begin
        if (valid[i0_order[-1:0]])
          errcode <= 60000 + i0_order[7:0];
        buffer[i0_order[-1:0]] <= {i0_data, i0_order};
        valid[i0_order[-1:0]] <= 1;
      end
      if (continue_flag && valid[cursor[-1:0]]) begin
        if (buffer[cursor[-1:0]][63:0] != cursor)
          errcode <= 61000 + cursor[7:0];
        o0_valid <= 1;
        o0_order <= buffer[cursor[-1:0]][63:0];
        o0_data <= buffer[cursor[-1:0]][400:64];
        valid[cursor[-1:0]] <= 0;
        cursor = cursor + 1;
      end else begin
        continue_flag = 0;
      end
    end
  end
endmodule
