`timescale 1ns/1ps

module riscv32im_muldiv (
  input  logic [2:0]  funct3_i,
  input  logic [31:0] lhs_i,
  input  logic [31:0] rhs_i,
  output logic [31:0] result_o
);
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

  always_comb begin
    lhs_signed_ext = {{32{lhs_i[31]}}, lhs_i};
    rhs_signed_ext = {{32{rhs_i[31]}}, rhs_i};
    rhs_unsigned_ext_as_signed = {32'h0000_0000, rhs_i};
    product_ss = lhs_signed_ext * rhs_signed_ext;
    product_su = lhs_signed_ext * rhs_unsigned_ext_as_signed;
    product_uu = {32'h0000_0000, lhs_i} * {32'h0000_0000, rhs_i};

    lhs_signed = lhs_i;
    rhs_signed = rhs_i;

    if (rhs_i == 32'h0000_0000) begin
      div_signed_result = 32'hffff_ffff;
      rem_signed_result = lhs_i;
      div_unsigned_result = 32'hffff_ffff;
      rem_unsigned_result = lhs_i;
    end else begin
      div_unsigned_result = lhs_i / rhs_i;
      rem_unsigned_result = lhs_i % rhs_i;
      if ((lhs_i == 32'h8000_0000) && (rhs_i == 32'hffff_ffff)) begin
        div_signed_result = 32'h8000_0000;
        rem_signed_result = 32'h0000_0000;
      end else begin
        div_signed_result = lhs_signed / rhs_signed;
        rem_signed_result = lhs_signed % rhs_signed;
      end
    end

    unique case (funct3_i)
      3'b000: result_o = product_uu[31:0];
      3'b001: result_o = product_ss[63:32];
      3'b010: result_o = product_su[63:32];
      3'b011: result_o = product_uu[63:32];
      3'b100: result_o = div_signed_result;
      3'b101: result_o = div_unsigned_result;
      3'b110: result_o = rem_signed_result;
      3'b111: result_o = rem_unsigned_result;
      default: result_o = 32'h0000_0000;
    endcase
  end
endmodule
