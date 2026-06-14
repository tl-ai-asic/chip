`timescale 1ns/1ps

module riscv32im_rvfi_trace (
  input  logic clk,
  input  logic rst_n,
  input  riscv32im_rvfi_retire_info_t retire_i,

  output logic        rvfi_valid,
  output logic [63:0] rvfi_order,
  output logic [31:0] rvfi_insn,
  output logic        rvfi_trap,
  output logic        rvfi_halt,
  output logic        rvfi_intr,
  output logic [1:0]  rvfi_mode,
  output logic [1:0]  rvfi_ixl,
  output logic [4:0]  rvfi_rs1_addr,
  output logic [4:0]  rvfi_rs2_addr,
  output logic [31:0] rvfi_rs1_rdata,
  output logic [31:0] rvfi_rs2_rdata,
  output logic [4:0]  rvfi_rd_addr,
  output logic [31:0] rvfi_rd_wdata,
  output logic [31:0] rvfi_pc_rdata,
  output logic [31:0] rvfi_pc_wdata,
  output logic [31:0] rvfi_mem_addr,
  output logic [3:0]  rvfi_mem_rmask,
  output logic [3:0]  rvfi_mem_wmask,
  output logic [31:0] rvfi_mem_rdata,
  output logic [31:0] rvfi_mem_wdata
);
  assign rvfi_mode = 2'b11;
  assign rvfi_ixl = 2'b01;
  assign rvfi_intr = 1'b0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rvfi_valid <= 1'b0;
      rvfi_order <= 64'h0000_0000_0000_0000;
      rvfi_insn <= 32'h0000_0000;
      rvfi_trap <= 1'b0;
      rvfi_halt <= 1'b0;
      rvfi_rs1_addr <= 5'd0;
      rvfi_rs2_addr <= 5'd0;
      rvfi_rs1_rdata <= 32'h0000_0000;
      rvfi_rs2_rdata <= 32'h0000_0000;
      rvfi_rd_addr <= 5'd0;
      rvfi_rd_wdata <= 32'h0000_0000;
      rvfi_pc_rdata <= 32'h0000_0000;
      rvfi_pc_wdata <= 32'h0000_0000;
      rvfi_mem_addr <= 32'h0000_0000;
      rvfi_mem_rmask <= 4'h0;
      rvfi_mem_wmask <= 4'h0;
      rvfi_mem_rdata <= 32'h0000_0000;
      rvfi_mem_wdata <= 32'h0000_0000;
    end else begin
      rvfi_valid <= 1'b0;
      rvfi_trap <= 1'b0;
      rvfi_halt <= retire_i.halt;
      rvfi_rs1_addr <= 5'd0;
      rvfi_rs2_addr <= 5'd0;
      rvfi_rs1_rdata <= 32'h0000_0000;
      rvfi_rs2_rdata <= 32'h0000_0000;
      rvfi_rd_addr <= 5'd0;
      rvfi_rd_wdata <= 32'h0000_0000;
      rvfi_mem_addr <= 32'h0000_0000;
      rvfi_mem_rmask <= 4'h0;
      rvfi_mem_wmask <= 4'h0;
      rvfi_mem_rdata <= 32'h0000_0000;
      rvfi_mem_wdata <= 32'h0000_0000;

      if (retire_i.valid) begin
        rvfi_valid <= 1'b1;
        rvfi_insn <= retire_i.insn;
        rvfi_trap <= retire_i.trap;
        rvfi_halt <= retire_i.halt;
        rvfi_rs1_addr <= retire_i.rs1_addr;
        rvfi_rs2_addr <= retire_i.rs2_addr;
        rvfi_rs1_rdata <= retire_i.rs1_rdata;
        rvfi_rs2_rdata <= retire_i.rs2_rdata;
        rvfi_rd_addr <= retire_i.rd_addr;
        rvfi_rd_wdata <= retire_i.rd_wdata;
        rvfi_pc_rdata <= retire_i.pc_rdata;
        rvfi_pc_wdata <= retire_i.pc_wdata;
        rvfi_mem_addr <= retire_i.mem_addr;
        rvfi_mem_rmask <= retire_i.mem_rmask;
        rvfi_mem_wmask <= retire_i.mem_wmask;
        rvfi_mem_rdata <= retire_i.mem_rdata;
        rvfi_mem_wdata <= retire_i.mem_wdata;
        rvfi_order <= rvfi_order + 64'd1;
      end
    end
  end
endmodule
