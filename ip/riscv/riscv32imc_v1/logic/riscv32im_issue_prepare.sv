`timescale 1ns/1ps

module riscv32im_issue_prepare (
  input  logic [31:0] insn_i,
  input  logic [31:0] pc_i,
  input  riscv32im_decode_info_t decode_i,
  input  logic [31:0] rs1_value_i,
  input  logic [31:0] rs2_value_i,
  output logic [3:0]  alu_op_o,
  output logic [31:0] alu_lhs_o,
  output logic [31:0] alu_rhs_o,
  output logic [4:0]  alu_shamt_o
);
  localparam logic [6:0] OPCODE_LUI      = 7'b0110111;
  localparam logic [6:0] OPCODE_AUIPC    = 7'b0010111;
  localparam logic [6:0] OPCODE_BRANCH   = 7'b1100011;
  localparam logic [6:0] OPCODE_LOAD     = 7'b0000011;
  localparam logic [6:0] OPCODE_STORE    = 7'b0100011;
  localparam logic [6:0] OPCODE_OP_IMM   = 7'b0010011;
  localparam logic [6:0] OPCODE_OP       = 7'b0110011;

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

  function automatic logic [31:0] imm_i(input logic [31:0] insn);
    imm_i = {{20{insn[31]}}, insn[31:20]};
  endfunction

  function automatic logic [31:0] imm_s(input logic [31:0] insn);
    imm_s = {{20{insn[31]}}, insn[31:25], insn[11:7]};
  endfunction

  function automatic logic [31:0] imm_u(input logic [31:0] insn);
    imm_u = {insn[31:12], 12'h000};
  endfunction

  always_comb begin
    alu_op_o = ALU_ADD;
    alu_lhs_o = rs1_value_i;
    alu_rhs_o = imm_i(insn_i);
    alu_shamt_o = insn_i[24:20];

    unique case (decode_i.opcode)
      OPCODE_LUI: begin
        alu_op_o = ALU_PASS;
        alu_lhs_o = 32'h0000_0000;
        alu_rhs_o = imm_u(insn_i);
      end
      OPCODE_AUIPC: begin
        alu_op_o = ALU_ADD;
        alu_lhs_o = pc_i;
        alu_rhs_o = imm_u(insn_i);
      end
      OPCODE_LOAD: begin
        alu_op_o = ALU_ADD;
        alu_lhs_o = rs1_value_i;
        alu_rhs_o = imm_i(insn_i);
      end
      OPCODE_STORE: begin
        alu_op_o = ALU_ADD;
        alu_lhs_o = rs1_value_i;
        alu_rhs_o = imm_s(insn_i);
      end
      OPCODE_BRANCH: begin
        alu_op_o = ALU_SUB;
        alu_lhs_o = rs1_value_i;
        alu_rhs_o = rs2_value_i;
      end
      OPCODE_OP_IMM: begin
        alu_lhs_o = rs1_value_i;
        alu_rhs_o = imm_i(insn_i);
        unique case (decode_i.funct3)
          3'b000: alu_op_o = ALU_ADD;
          3'b010: alu_op_o = ALU_SLT;
          3'b011: alu_op_o = ALU_SLTU;
          3'b100: alu_op_o = ALU_XOR;
          3'b110: alu_op_o = ALU_OR;
          3'b111: alu_op_o = ALU_AND;
          3'b001: alu_op_o = ALU_SLL;
          3'b101: alu_op_o = (decode_i.funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
          default: alu_op_o = ALU_ADD;
        endcase
      end
      OPCODE_OP: begin
        alu_lhs_o = rs1_value_i;
        alu_rhs_o = rs2_value_i;
        alu_shamt_o = rs2_value_i[4:0];
        unique case (decode_i.funct3)
          3'b000: alu_op_o = (decode_i.funct7 == 7'b0100000) ? ALU_SUB : ALU_ADD;
          3'b001: alu_op_o = ALU_SLL;
          3'b010: alu_op_o = ALU_SLT;
          3'b011: alu_op_o = ALU_SLTU;
          3'b100: alu_op_o = ALU_XOR;
          3'b101: alu_op_o = (decode_i.funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
          3'b110: alu_op_o = ALU_OR;
          3'b111: alu_op_o = ALU_AND;
          default: alu_op_o = ALU_ADD;
        endcase
      end
      default: begin
      end
    endcase
  end
endmodule
