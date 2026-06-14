`timescale 1ns/1ps

module riscv32im_csr_read #(
  parameter logic [31:0] HART_ID = 32'h0000_0000
) (
  input  logic [11:0] csr_addr_i,
  input  logic [31:0] csr_mstatus_i,
  input  logic [31:0] csr_mtvec_i,
  input  logic [31:0] csr_mscratch_i,
  input  logic [31:0] csr_mepc_i,
  input  logic [31:0] csr_mcause_i,
  input  logic [31:0] csr_mtval_i,
  input  logic [63:0] csr_mcycle_i,
  input  logic [63:0] csr_minstret_i,
  output logic [31:0] csr_rdata_o
);
  localparam logic [11:0] CSR_MSTATUS   = 12'h300;
  localparam logic [11:0] CSR_MTVEC     = 12'h305;
  localparam logic [11:0] CSR_MSCRATCH  = 12'h340;
  localparam logic [11:0] CSR_MEPC      = 12'h341;
  localparam logic [11:0] CSR_MCAUSE    = 12'h342;
  localparam logic [11:0] CSR_MTVAL     = 12'h343;
  localparam logic [11:0] CSR_MHARTID   = 12'hF14;
  localparam logic [11:0] CSR_CYCLE     = 12'hC00;
  localparam logic [11:0] CSR_TIME      = 12'hC01;
  localparam logic [11:0] CSR_INSTRET   = 12'hC02;
  localparam logic [11:0] CSR_CYCLEH    = 12'hC80;
  localparam logic [11:0] CSR_TIMEH     = 12'hC81;
  localparam logic [11:0] CSR_INSTRETH  = 12'hC82;
  localparam logic [11:0] CSR_MCYCLE    = 12'hB00;
  localparam logic [11:0] CSR_MINSTRET  = 12'hB02;
  localparam logic [11:0] CSR_MCYCLEH   = 12'hB80;
  localparam logic [11:0] CSR_MINSTRETH = 12'hB82;

  always_comb begin
    unique case (csr_addr_i)
      CSR_MSTATUS: csr_rdata_o = csr_mstatus_i;
      CSR_MTVEC: csr_rdata_o = csr_mtvec_i;
      CSR_MSCRATCH: csr_rdata_o = csr_mscratch_i;
      CSR_MEPC: csr_rdata_o = csr_mepc_i;
      CSR_MCAUSE: csr_rdata_o = csr_mcause_i;
      CSR_MTVAL: csr_rdata_o = csr_mtval_i;
      CSR_MHARTID: csr_rdata_o = HART_ID;
      CSR_CYCLE,
      CSR_TIME,
      CSR_MCYCLE: csr_rdata_o = csr_mcycle_i[31:0];
      CSR_INSTRET,
      CSR_MINSTRET: csr_rdata_o = csr_minstret_i[31:0];
      CSR_CYCLEH,
      CSR_TIMEH,
      CSR_MCYCLEH: csr_rdata_o = csr_mcycle_i[63:32];
      CSR_INSTRETH,
      CSR_MINSTRETH: csr_rdata_o = csr_minstret_i[63:32];
      default: csr_rdata_o = 32'h0000_0000;
    endcase
  end
endmodule
