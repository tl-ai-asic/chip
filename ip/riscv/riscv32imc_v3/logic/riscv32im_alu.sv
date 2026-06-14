`timescale 1ns/1ps

module riscv32im_alu (
  input  logic [3:0]  op_i,
  input  logic [31:0] lhs_i,
  input  logic [31:0] rhs_i,
  input  logic [4:0]  shamt_i,
  output logic [31:0] result_o,

  output logic        cmp_eq_o,
  output logic        cmp_ne_o,
  output logic        cmp_lts_o,
  output logic        cmp_ges_o,
  output logic        cmp_ltu_o,
  output logic        cmp_geu_o
);
  localparam logic [3:0] ALU_ADD  = 4'd0;
  localparam logic [3:0] ALU_SUB  = 4'd1;
  localparam logic [3:0] ALU_SLL  = 4'd2;
  localparam logic [3:0] ALU_SLT  = 4'd3;
  localparam logic [3:0] ALU_SLTU = 4'd4;
  localparam logic [3:0] ALU_XOR  = 4'd5;
  localparam logic [3:0] ALU_SRL  = 4'd6;
  localparam logic [3:0] ALU_SRA  = 4'd7;
  localparam logic [3:0] ALU_OR   = 4'd8;
  localparam logic [3:0] ALU_AND  = 4'd9;
  localparam logic [3:0] ALU_PASS = 4'd10;

  function automatic logic [31:0] sra32(input logic [31:0] lhs, input logic [4:0] shamt);
    logic signed [31:0] lhs_signed;
    begin
      lhs_signed = lhs;
      sra32 = lhs_signed >>> shamt;
    end
  endfunction

  always_comb begin
    unique case (op_i)
      ALU_ADD:  result_o = lhs_i + rhs_i;
      ALU_SUB:  result_o = lhs_i - rhs_i;
      ALU_SLL:  result_o = lhs_i << shamt_i;
      ALU_SLT:  result_o = ($signed(lhs_i) < $signed(rhs_i)) ? 32'd1 : 32'd0;
      ALU_SLTU: result_o = (lhs_i < rhs_i) ? 32'd1 : 32'd0;
      ALU_XOR:  result_o = lhs_i ^ rhs_i;
      ALU_SRL:  result_o = lhs_i >> shamt_i;
      ALU_SRA:  result_o = sra32(lhs_i, shamt_i);
      ALU_OR:   result_o = lhs_i | rhs_i;
      ALU_AND:  result_o = lhs_i & rhs_i;
      ALU_PASS: result_o = rhs_i;
      default:  result_o = 32'h0000_0000;
    endcase
  end

  assign cmp_eq_o  = (lhs_i == rhs_i);
  assign cmp_ne_o  = (lhs_i != rhs_i);
  assign cmp_lts_o = ($signed(lhs_i) < $signed(rhs_i));
  assign cmp_ges_o = ($signed(lhs_i) >= $signed(rhs_i));
  assign cmp_ltu_o = (lhs_i < rhs_i);
  assign cmp_geu_o = (lhs_i >= rhs_i);
endmodule
