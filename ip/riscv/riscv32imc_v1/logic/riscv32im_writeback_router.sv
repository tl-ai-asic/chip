`timescale 1ns/1ps

module riscv32im_writeback_router (
  input  logic                         fast_fire_i,
  input  riscv32im_alu_exec_result_t   fast_alu_result_i,

  input  logic                         lsu_wb_selected_i,
  input  riscv32im_lsu_rsp_info_t      lsu_rsp_i,

  input  logic                         muldiv_wb_selected_i,
  input  logic                         muldiv_rd_write_i,
  input  logic [4:0]                   muldiv_rd_addr_i,
  input  logic [31:0]                  muldiv_rd_wdata_i,

  input  logic                         alu_wb_selected_i,
  input  logic                         alu_trap_i,
  input  logic                         alu_rd_write_i,
  input  logic [4:0]                   alu_rd_addr_i,
  input  logic [31:0]                  alu_rd_wdata_i,

  output logic                         fast_write_valid_o,
  output logic [4:0]                   fast_write_addr_o,
  output logic [31:0]                  fast_write_data_o,
  output logic                         retire_write_valid_o,
  output logic [4:0]                   retire_write_addr_o,
  output logic [31:0]                  retire_write_data_o
);
  assign fast_write_valid_o = fast_fire_i && fast_alu_result_i.rd_write;
  assign fast_write_addr_o = fast_alu_result_i.rd_addr;
  assign fast_write_data_o = fast_alu_result_i.rd_wdata;

  always_comb begin
    retire_write_valid_o = 1'b0;
    retire_write_addr_o = 5'd0;
    retire_write_data_o = 32'h0000_0000;

    if (lsu_wb_selected_i && !lsu_rsp_i.trap && lsu_rsp_i.rd_write) begin
      retire_write_valid_o = 1'b1;
      retire_write_addr_o = lsu_rsp_i.rd_addr;
      retire_write_data_o = lsu_rsp_i.rd_wdata;
    end else if (muldiv_wb_selected_i && muldiv_rd_write_i) begin
      retire_write_valid_o = 1'b1;
      retire_write_addr_o = muldiv_rd_addr_i;
      retire_write_data_o = muldiv_rd_wdata_i;
    end else if (alu_wb_selected_i && !alu_trap_i && alu_rd_write_i) begin
      retire_write_valid_o = 1'b1;
      retire_write_addr_o = alu_rd_addr_i;
      retire_write_data_o = alu_rd_wdata_i;
    end
  end
endmodule
