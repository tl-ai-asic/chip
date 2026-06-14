`timescale 1ns/1ps

module riscv32im_csr_file #(
  parameter logic [31:0] HART_ID = 32'h0000_0000
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic [11:0] csr_addr_i,
  output logic [31:0] csr_rdata_o,
  output logic [31:0] csr_mtvec_o,
  output logic [31:0] csr_mepc_o,

  input  logic        write_valid_i,
  input  logic [11:0] write_addr_i,
  input  logic [31:0] write_data_i,

  input  logic        trap_valid_i,
  input  logic [31:0] trap_cause_i,
  input  logic [31:0] trap_tval_i,
  input  logic [31:0] trap_epc_i,

  input  logic        retire_valid_i
);
  localparam logic [11:0] CSR_MSTATUS   = 12'h300;
  localparam logic [11:0] CSR_MTVEC     = 12'h305;
  localparam logic [11:0] CSR_MSCRATCH  = 12'h340;
  localparam logic [11:0] CSR_MEPC      = 12'h341;
  localparam logic [11:0] CSR_MCAUSE    = 12'h342;
  localparam logic [11:0] CSR_MTVAL     = 12'h343;
  localparam logic [11:0] CSR_MCYCLE    = 12'hB00;
  localparam logic [11:0] CSR_MINSTRET  = 12'hB02;
  localparam logic [11:0] CSR_MCYCLEH   = 12'hB80;
  localparam logic [11:0] CSR_MINSTRETH = 12'hB82;

  logic [31:0] csr_mstatus_q;
  logic [31:0] csr_mtvec_q;
  logic [31:0] csr_mscratch_q;
  logic [31:0] csr_mepc_q;
  logic [31:0] csr_mcause_q;
  logic [31:0] csr_mtval_q;
  logic [63:0] csr_mcycle_q;
  logic [63:0] csr_minstret_q;

  assign csr_mtvec_o = csr_mtvec_q;
  assign csr_mepc_o = csr_mepc_q;

  riscv32im_csr_read #(
    .HART_ID(HART_ID)
  ) u_read (
    .csr_addr_i(csr_addr_i),
    .csr_mstatus_i(csr_mstatus_q),
    .csr_mtvec_i(csr_mtvec_q),
    .csr_mscratch_i(csr_mscratch_q),
    .csr_mepc_i(csr_mepc_q),
    .csr_mcause_i(csr_mcause_q),
    .csr_mtval_i(csr_mtval_q),
    .csr_mcycle_i(csr_mcycle_q),
    .csr_minstret_i(csr_minstret_q),
    .csr_rdata_o(csr_rdata_o)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      csr_mstatus_q <= 32'h0000_1800;
      csr_mtvec_q <= 32'h0000_0000;
      csr_mscratch_q <= 32'h0000_0000;
      csr_mepc_q <= 32'h0000_0000;
      csr_mcause_q <= 32'h0000_0000;
      csr_mtval_q <= 32'h0000_0000;
      csr_mcycle_q <= 64'h0000_0000_0000_0000;
      csr_minstret_q <= 64'h0000_0000_0000_0000;
    end else begin
      csr_mcycle_q <= csr_mcycle_q + 64'd1;
      if (retire_valid_i) begin
        csr_minstret_q <= csr_minstret_q + 64'd1;
      end

      if (write_valid_i) begin
        unique case (write_addr_i)
          CSR_MSTATUS: csr_mstatus_q <= write_data_i & 32'h0000_1888;
          CSR_MTVEC: csr_mtvec_q <= {write_data_i[31:2], write_data_i[1:0]};
          CSR_MSCRATCH: csr_mscratch_q <= write_data_i;
          CSR_MEPC: csr_mepc_q <= {write_data_i[31:2], 2'b00};
          CSR_MCAUSE: csr_mcause_q <= write_data_i;
          CSR_MTVAL: csr_mtval_q <= write_data_i;
          CSR_MCYCLE: csr_mcycle_q[31:0] <= write_data_i;
          CSR_MCYCLEH: csr_mcycle_q[63:32] <= write_data_i;
          CSR_MINSTRET: csr_minstret_q[31:0] <= write_data_i;
          CSR_MINSTRETH: csr_minstret_q[63:32] <= write_data_i;
          default: begin
          end
        endcase
      end

      if (trap_valid_i) begin
        csr_mepc_q <= {trap_epc_i[31:2], 2'b00};
        csr_mcause_q <= trap_cause_i;
        csr_mtval_q <= trap_tval_i;
      end
    end
  end
endmodule
