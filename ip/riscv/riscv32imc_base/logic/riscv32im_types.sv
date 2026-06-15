`timescale 1ns/1ps

typedef struct packed {
  logic [6:0]  opcode;
  logic [4:0]  rd;
  logic [2:0]  funct3;
  logic [4:0]  rs1;
  logic [4:0]  rs2;
  logic [6:0]  funct7;
  logic [11:0] csr_addr;
  logic        illegal;
  logic        uses_rs1;
  logic        uses_rs2;
  logic        writes_rd;
  logic        serial;
  logic        to_alu;
  logic        to_muldiv;
  logic        to_lsu;
  logic        lsu_write;
} riscv32im_decode_info_t;
