`timescale 1ns/1ps

module riscv32im_muldiv (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         req_valid_i,
  output logic                         req_ready_o,
  input  riscv32im_muldiv_issue_info_t req_i,
  output logic                         rsp_valid_o,
  input  logic                         rsp_ready_i,
  output riscv32im_muldiv_rsp_info_t   rsp_o
);
  riscv32im_muldiv_rsp_info_t rsp_q;
  riscv32im_muldiv_rsp_info_t rsp_next;

  logic signed [63:0] lhs_signed_ext;
  logic signed [63:0] rhs_signed_ext;
  logic signed [63:0] rhs_unsigned_ext_as_signed;
  logic signed [63:0] product_ss;
  logic signed [63:0] product_su;
  logic [63:0]        product_uu;
  logic signed [31:0] lhs_signed;
  logic signed [31:0] rhs_signed;
  logic [31:0]        div_signed_result;
  logic [31:0]        rem_signed_result;
  logic [31:0]        div_unsigned_result;
  logic [31:0]        rem_unsigned_result;
  logic [31:0]        result;
  logic               rsp_valid_q;

  assign req_ready_o = !rsp_valid_q || rsp_ready_i;
  assign rsp_valid_o = rsp_valid_q;
  assign rsp_o = rsp_q;

  always_comb begin
    lhs_signed_ext = {{32{req_i.lhs[31]}}, req_i.lhs};
    rhs_signed_ext = {{32{req_i.rhs[31]}}, req_i.rhs};
    rhs_unsigned_ext_as_signed = {32'h0000_0000, req_i.rhs};
    product_ss = lhs_signed_ext * rhs_signed_ext;
    product_su = lhs_signed_ext * rhs_unsigned_ext_as_signed;
    product_uu = {32'h0000_0000, req_i.lhs} * {32'h0000_0000, req_i.rhs};

    lhs_signed = req_i.lhs;
    rhs_signed = req_i.rhs;

    if (req_i.rhs == 32'h0000_0000) begin
      div_signed_result = 32'hffff_ffff;
      rem_signed_result = req_i.lhs;
      div_unsigned_result = 32'hffff_ffff;
      rem_unsigned_result = req_i.lhs;
    end else begin
      div_unsigned_result = req_i.lhs / req_i.rhs;
      rem_unsigned_result = req_i.lhs % req_i.rhs;
      if ((req_i.lhs == 32'h8000_0000) && (req_i.rhs == 32'hffff_ffff)) begin
        div_signed_result = 32'h8000_0000;
        rem_signed_result = 32'h0000_0000;
      end else begin
        div_signed_result = lhs_signed / rhs_signed;
        rem_signed_result = lhs_signed % rhs_signed;
      end
    end

    unique case (req_i.funct3)
      3'b000: result = product_uu[31:0];
      3'b001: result = product_ss[63:32];
      3'b010: result = product_su[63:32];
      3'b011: result = product_uu[63:32];
      3'b100: result = div_signed_result;
      3'b101: result = div_unsigned_result;
      3'b110: result = rem_signed_result;
      3'b111: result = rem_unsigned_result;
      default: result = 32'h0000_0000;
    endcase

    rsp_next = '0;
    rsp_next.insn = req_i.insn;
    rsp_next.pc_rdata = req_i.pc_rdata;
    rsp_next.pc_wdata = req_i.pc_wdata;
    rsp_next.rs1_addr = req_i.rs1_addr;
    rsp_next.rs2_addr = req_i.rs2_addr;
    rsp_next.rs1_rdata = req_i.rs1_rdata;
    rsp_next.rs2_rdata = req_i.rs2_rdata;
    rsp_next.rd_write = req_i.rd_write;
    rsp_next.rd_addr = req_i.rd_addr;
    rsp_next.rd_wdata = result;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rsp_valid_q <= 1'b0;
      rsp_q <= '0;
    end else if (req_ready_o) begin
      rsp_valid_q <= req_valid_i;
      if (req_valid_i) begin
        rsp_q <= rsp_next;
      end
    end else if (rsp_ready_i) begin
      rsp_valid_q <= 1'b0;
    end
  end
endmodule
