`timescale 1ns/1ps

typedef struct packed {
  logic        uses_rs1;
  logic        uses_rs2;
  logic        writes_rd;
  logic        serial;
  logic        to_alu;
  logic        to_muldiv;
  logic        to_lsu;
  logic [4:0]  rs1;
  logic [4:0]  rs2;
  logic [4:0]  rd;
} riscv32im_issue_info_t;

typedef struct packed {
  logic alu_busy;
  logic muldiv_busy;
  logic lsu_busy;
} riscv32im_engine_busy_t;

typedef struct packed {
  logic        valid;
  logic        writes_rd;
  logic [4:0]  rd;
  logic        control_retired;
  logic        flush_control;
} riscv32im_retire_info_t;

typedef struct packed {
  logic issue_allowed;
  logic raw_hazard;
  logic waw_hazard;
  logic serial_hazard;
  logic engine_hazard;
  logic control_busy;
  logic [3:0] outstanding;
  logic [31:0] reg_busy;
} riscv32im_scoreboard_status_t;

typedef struct packed {
  logic        write;
  logic [2:0]  funct3;
  logic [31:0] addr;
  logic [31:0] store_data;
  logic [31:0] insn;
  logic [31:0] pc_rdata;
  logic [31:0] pc_wdata;
  logic [4:0]  rs1_addr;
  logic [4:0]  rs2_addr;
  logic [31:0] rs1_rdata;
  logic [31:0] rs2_rdata;
  logic        rd_write;
  logic [4:0]  rd_addr;
} riscv32im_lsu_issue_info_t;

typedef struct packed {
  logic        trap;
  logic [31:0] trap_cause;
  logic [31:0] trap_tval;
  logic [31:0] insn;
  logic [31:0] pc_rdata;
  logic [31:0] pc_wdata;
  logic [4:0]  rs1_addr;
  logic [4:0]  rs2_addr;
  logic [31:0] rs1_rdata;
  logic [31:0] rs2_rdata;
  logic        rd_write;
  logic [4:0]  rd_addr;
  logic [31:0] rd_wdata;
  logic [31:0] mem_addr;
  logic [3:0]  mem_rmask;
  logic [3:0]  mem_wmask;
  logic [31:0] mem_rdata;
  logic [31:0] mem_wdata;
} riscv32im_lsu_rsp_info_t;

typedef struct packed {
  logic        valid;
  logic        trap;
  logic        halt;
  logic [31:0] insn;
  logic [31:0] pc_rdata;
  logic [31:0] pc_wdata;
  logic [4:0]  rs1_addr;
  logic [4:0]  rs2_addr;
  logic [31:0] rs1_rdata;
  logic [31:0] rs2_rdata;
  logic [4:0]  rd_addr;
  logic [31:0] rd_wdata;
  logic [31:0] mem_addr;
  logic [3:0]  mem_rmask;
  logic [3:0]  mem_wmask;
  logic [31:0] mem_rdata;
  logic [31:0] mem_wdata;
} riscv32im_rvfi_retire_info_t;

typedef struct packed {
  logic        control;
  logic        trap;
  logic [31:0] trap_cause;
  logic [31:0] trap_tval;
  logic [31:0] insn;
  logic [31:0] pc_rdata;
  logic [31:0] pc_wdata;
  logic [4:0]  rs1_addr;
  logic [4:0]  rs2_addr;
  logic [31:0] rs1_rdata;
  logic [31:0] rs2_rdata;
  logic        rd_write;
  logic [4:0]  rd_addr;
  logic [31:0] rd_wdata;
  logic        csr_write;
  logic [11:0] csr_addr;
  logic [31:0] csr_wdata;
} riscv32im_alu_exec_result_t;
