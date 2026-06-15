`timescale 1ns/1ps

module riscv32im_register_file (
  input  logic        clk,
  input  logic        rst_n,

  input  logic [4:0]  issue_rs1_addr_i,
  output logic [31:0] issue_rs1_data_o,
  input  logic [4:0]  issue_rs2_addr_i,
  output logic [31:0] issue_rs2_data_o,
  input  logic [4:0]  fast_rs1_addr_i,
  output logic [31:0] fast_rs1_data_o,
  input  logic [4:0]  fast_rs2_addr_i,
  output logic [31:0] fast_rs2_data_o,

  input  logic        fast_write_valid_i,
  input  logic [4:0]  fast_write_addr_i,
  input  logic [31:0] fast_write_data_i,
  input  logic        retire_write_valid_i,
  input  logic [4:0]  retire_write_addr_i,
  input  logic [31:0] retire_write_data_i
);
  logic [31:0] regs_q [31:0];
  integer reg_index;

  assign issue_rs1_data_o = (issue_rs1_addr_i == 5'd0) ? 32'h0000_0000 : regs_q[issue_rs1_addr_i];
  assign issue_rs2_data_o = (issue_rs2_addr_i == 5'd0) ? 32'h0000_0000 : regs_q[issue_rs2_addr_i];
  assign fast_rs1_data_o = (fast_rs1_addr_i == 5'd0) ? 32'h0000_0000 : regs_q[fast_rs1_addr_i];
  assign fast_rs2_data_o = (fast_rs2_addr_i == 5'd0) ? 32'h0000_0000 : regs_q[fast_rs2_addr_i];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (reg_index = 0; reg_index < 32; reg_index = reg_index + 1) begin
        regs_q[reg_index] <= 32'h0000_0000;
      end
    end else begin
      regs_q[0] <= 32'h0000_0000;

      if (fast_write_valid_i && (fast_write_addr_i != 5'd0)) begin
        regs_q[fast_write_addr_i] <= fast_write_data_i;
      end

      if (retire_write_valid_i && (retire_write_addr_i != 5'd0)) begin
        regs_q[retire_write_addr_i] <= retire_write_data_i;
      end
    end
  end

`ifndef SYNTHESIS
  default clocking riscv32im_register_file_cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  assert_no_x0_write:
    assert property (regs_q[0] == 32'h0000_0000)
    else $error("x0 changed value");
`endif
endmodule
