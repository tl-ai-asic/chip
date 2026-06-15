`timescale 1ns/1ps

module riscv32im_core #(
  parameter logic [31:0] RESET_VECTOR = 32'h8000_0000,
  parameter logic [31:0] HART_ID      = 32'h0000_0000
) (
  input  logic        clk,
  input  logic        rst_n,

  output logic        imem_req_valid,
  input  logic        imem_req_ready,
  output logic [31:0] imem_req_addr,
  input  logic        imem_rsp_valid,
  input  logic [31:0] imem_rsp_rdata,
  input  logic        imem_rsp_err,

  output logic        dmem_req_valid,
  input  logic        dmem_req_ready,
  output logic        dmem_req_write,
  output logic [31:0] dmem_req_addr,
  output logic [31:0] dmem_req_wdata,
  output logic [3:0]  dmem_req_wstrb,
  input  logic        dmem_rsp_valid,
  input  logic [31:0] dmem_rsp_rdata,
  input  logic        dmem_rsp_err,

  output logic        core_halt,
  output logic        core_trap,

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
  typedef enum logic [1:0] {
    ST_PREFETCH,
    ST_DECODE,
    ST_EXECUTION,
    ST_WRITE_BACK
  } state_e;

  localparam logic [6:0] OPCODE_LUI      = 7'b0110111;
  localparam logic [6:0] OPCODE_AUIPC    = 7'b0010111;
  localparam logic [6:0] OPCODE_JAL      = 7'b1101111;
  localparam logic [6:0] OPCODE_JALR     = 7'b1100111;
  localparam logic [6:0] OPCODE_BRANCH   = 7'b1100011;
  localparam logic [6:0] OPCODE_LOAD     = 7'b0000011;
  localparam logic [6:0] OPCODE_STORE    = 7'b0100011;
  localparam logic [6:0] OPCODE_OP_IMM   = 7'b0010011;
  localparam logic [6:0] OPCODE_OP       = 7'b0110011;
  localparam logic [6:0] OPCODE_MISC_MEM = 7'b0001111;
  localparam logic [6:0] OPCODE_SYSTEM   = 7'b1110011;

  localparam logic [31:0] INSN_ECALL  = 32'h0000_0073;
  localparam logic [31:0] INSN_EBREAK = 32'h0010_0073;
  localparam logic [31:0] INSN_MRET   = 32'h3020_0073;
  localparam logic [31:0] INSN_WFI    = 32'h1050_0073;

  localparam logic [31:0] EXC_INSTR_ADDR_MISALIGNED = 32'd0;
  localparam logic [31:0] EXC_INSTR_ACCESS_FAULT    = 32'd1;
  localparam logic [31:0] EXC_ILLEGAL_INSTR         = 32'd2;
  localparam logic [31:0] EXC_BREAKPOINT            = 32'd3;
  localparam logic [31:0] EXC_LOAD_ACCESS_FAULT     = 32'd5;
  localparam logic [31:0] EXC_STORE_ACCESS_FAULT    = 32'd7;
  localparam logic [31:0] EXC_ECALL_MMODE           = 32'd11;

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

  state_e      state_q;
  logic        prefetch_pending_q;
  logic        control_busy_q;
  logic [3:0]  outstanding_q;
  logic [31:0] reg_busy_q;
  logic [31:0] pc_q;
  logic [31:0] insn_q;
  logic [31:0] insn_pc_q;
  logic        insn_fetch_err_q;
  logic [31:0] regs_q [31:0];

  logic [31:0] csr_mstatus_q;
  logic [31:0] csr_mtvec_q;
  logic [31:0] csr_mscratch_q;
  logic [31:0] csr_mepc_q;
  logic [31:0] csr_mcause_q;
  logic [31:0] csr_mtval_q;
  logic [63:0] csr_mcycle_q;
  logic [63:0] csr_minstret_q;

  logic        core_halt_q;
  logic        core_trap_q;

  logic [31:0] d_insn_q;
  logic [31:0] d_pc_q;
  logic [31:0] d_pc_next_q;
  logic        d_fetch_error_q;
  riscv32im_decode_info_t d_decode_q;

  riscv32im_decode_info_t decode_info;

  logic [31:0] issue_rs1_value;
  logic [31:0] issue_rs2_value;
  logic [3:0]  issue_alu_op;
  logic [31:0] issue_alu_lhs;
  logic [31:0] issue_alu_rhs;
  logic [4:0]  issue_alu_shamt;
  logic [31:0] issue_alu_result;
  logic        issue_cmp_eq;
  logic        issue_cmp_ne;
  logic        issue_cmp_lts;
  logic        issue_cmp_ges;
  logic        issue_cmp_ltu;
  logic        issue_cmp_geu;
  logic [31:0] issue_muldiv_result;

  logic        raw_hazard;
  logic        waw_hazard;
  logic        serial_hazard;
  logic        engine_hazard;
  logic        issue_allowed;

  logic        alu_busy_q;
  logic        alu_done_q;
  logic        alu_control_q;
  logic        alu_trap_q;
  logic [31:0] alu_trap_cause_q;
  logic [31:0] alu_trap_tval_q;
  logic [31:0] alu_insn_q;
  logic [31:0] alu_pc_rdata_q;
  logic [31:0] alu_pc_wdata_q;
  logic [4:0]  alu_rs1_addr_q;
  logic [4:0]  alu_rs2_addr_q;
  logic [31:0] alu_rs1_rdata_q;
  logic [31:0] alu_rs2_rdata_q;
  logic        alu_rd_write_q;
  logic [4:0]  alu_rd_addr_q;
  logic [31:0] alu_rd_wdata_q;
  logic        alu_csr_write_q;
  logic [11:0] alu_csr_addr_q;
  logic [31:0] alu_csr_wdata_q;

  logic        muldiv_busy_q;
  logic        muldiv_done_q;
  logic [1:0]  muldiv_count_q;
  logic [31:0] muldiv_insn_q;
  logic [31:0] muldiv_pc_rdata_q;
  logic [31:0] muldiv_pc_wdata_q;
  logic [4:0]  muldiv_rs1_addr_q;
  logic [4:0]  muldiv_rs2_addr_q;
  logic [31:0] muldiv_rs1_rdata_q;
  logic [31:0] muldiv_rs2_rdata_q;
  logic        muldiv_rd_write_q;
  logic [4:0]  muldiv_rd_addr_q;
  logic [31:0] muldiv_rd_wdata_q;

  logic        lsu_start_q;
  logic        lsu_busy_q;
  logic        lsu_done_q;
  logic        lsu_write_q;
  logic        lsu_trap_q;
  logic [31:0] lsu_trap_cause_q;
  logic [31:0] lsu_trap_tval_q;
  logic [31:0] lsu_insn_q;
  logic [31:0] lsu_pc_rdata_q;
  logic [31:0] lsu_pc_wdata_q;
  logic [4:0]  lsu_rs1_addr_q;
  logic [4:0]  lsu_rs2_addr_q;
  logic [31:0] lsu_rs1_rdata_q;
  logic [31:0] lsu_rs2_rdata_q;
  logic        lsu_rd_write_q;
  logic [4:0]  lsu_rd_addr_q;
  logic [31:0] lsu_rd_wdata_q;
  logic [31:0] lsu_mem_addr_q;
  logic [3:0]  lsu_mem_rmask_q;
  logic [3:0]  lsu_mem_wmask_q;
  logic [31:0] lsu_mem_rdata_q;
  logic [31:0] lsu_mem_wdata_q;

  logic        lsu_engine_busy;
  logic        lsu_engine_done;
  logic        lsu_engine_error;
  logic [31:0] lsu_engine_load_data;
  logic [31:0] lsu_engine_mem_addr;
  logic [3:0]  lsu_engine_mem_rmask;
  logic [3:0]  lsu_engine_mem_wmask;
  logic [31:0] lsu_engine_mem_rdata;
  logic [31:0] lsu_engine_mem_wdata;

  logic        alu_wb_valid;
  logic        muldiv_wb_valid;
  logic        lsu_wb_valid;
  logic [31:0] csr_rdata;

  assign issue_rs1_value = (d_decode_q.rs1 == 5'd0) ? 32'h0000_0000 : regs_q[d_decode_q.rs1];
  assign issue_rs2_value = (d_decode_q.rs2 == 5'd0) ? 32'h0000_0000 : regs_q[d_decode_q.rs2];

  assign imem_req_valid = (state_q == ST_PREFETCH) && !prefetch_pending_q && !control_busy_q && !core_halt_q;
  assign imem_req_addr = pc_q;

  assign core_halt = core_halt_q;
  assign core_trap = core_trap_q;

  assign rvfi_mode = 2'b11;
  assign rvfi_ixl = 2'b01;
  assign rvfi_intr = 1'b0;

  assign raw_hazard = ((d_decode_q.uses_rs1 && (d_decode_q.rs1 != 5'd0) && reg_busy_q[d_decode_q.rs1]) ||
                       (d_decode_q.uses_rs2 && (d_decode_q.rs2 != 5'd0) && reg_busy_q[d_decode_q.rs2]));
  assign waw_hazard = d_decode_q.writes_rd && (d_decode_q.rd != 5'd0) && reg_busy_q[d_decode_q.rd];
  assign serial_hazard = d_decode_q.serial && (outstanding_q != 4'd0);
  assign engine_hazard = (d_decode_q.to_alu && alu_busy_q) ||
                         (d_decode_q.to_muldiv && muldiv_busy_q) ||
                         (d_decode_q.to_lsu && lsu_busy_q);
  assign issue_allowed = (state_q == ST_EXECUTION) &&
                         !control_busy_q &&
                         !raw_hazard &&
                         !waw_hazard &&
                         !serial_hazard &&
                         !engine_hazard;

  assign alu_wb_valid = alu_busy_q && alu_done_q;
  assign muldiv_wb_valid = muldiv_busy_q && muldiv_done_q;
  assign lsu_wb_valid = lsu_busy_q && lsu_done_q;

  riscv32im_alu u_issue_alu (
    .op_i(issue_alu_op),
    .lhs_i(issue_alu_lhs),
    .rhs_i(issue_alu_rhs),
    .shamt_i(issue_alu_shamt),
    .result_o(issue_alu_result),
    .cmp_eq_o(issue_cmp_eq),
    .cmp_ne_o(issue_cmp_ne),
    .cmp_lts_o(issue_cmp_lts),
    .cmp_ges_o(issue_cmp_ges),
    .cmp_ltu_o(issue_cmp_ltu),
    .cmp_geu_o(issue_cmp_geu)
  );

  riscv32im_muldiv u_issue_muldiv (
    .funct3_i(d_decode_q.funct3),
    .lhs_i(issue_rs1_value),
    .rhs_i(issue_rs2_value),
    .result_o(issue_muldiv_result)
  );

  riscv32im_lsu u_lsu (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(lsu_start_q),
    .write_i(d_decode_q.lsu_write),
    .funct3_i(d_decode_q.funct3),
    .addr_i(issue_alu_result),
    .store_data_i(issue_rs2_value),
    .busy_o(lsu_engine_busy),
    .done_o(lsu_engine_done),
    .error_o(lsu_engine_error),
    .load_data_o(lsu_engine_load_data),
    .rvfi_mem_addr_o(lsu_engine_mem_addr),
    .rvfi_mem_rmask_o(lsu_engine_mem_rmask),
    .rvfi_mem_wmask_o(lsu_engine_mem_wmask),
    .rvfi_mem_rdata_o(lsu_engine_mem_rdata),
    .rvfi_mem_wdata_o(lsu_engine_mem_wdata),
    .dmem_req_valid(dmem_req_valid),
    .dmem_req_ready(dmem_req_ready),
    .dmem_req_write(dmem_req_write),
    .dmem_req_addr(dmem_req_addr),
    .dmem_req_wdata(dmem_req_wdata),
    .dmem_req_wstrb(dmem_req_wstrb),
    .dmem_rsp_valid(dmem_rsp_valid),
    .dmem_rsp_rdata(dmem_rsp_rdata),
    .dmem_rsp_err(dmem_rsp_err)
  );

  riscv32im_decode u_decode (
    .fetch_error_i(insn_fetch_err_q),
    .insn_i(insn_q),
    .decode_o(decode_info)
  );

  riscv32im_csr_read #(
    .HART_ID(HART_ID)
  ) u_csr_read (
    .csr_addr_i(d_decode_q.csr_addr),
    .csr_mstatus_i(csr_mstatus_q),
    .csr_mtvec_i(csr_mtvec_q),
    .csr_mscratch_i(csr_mscratch_q),
    .csr_mepc_i(csr_mepc_q),
    .csr_mcause_i(csr_mcause_q),
    .csr_mtval_i(csr_mtval_q),
    .csr_mcycle_i(csr_mcycle_q),
    .csr_minstret_i(csr_minstret_q),
    .csr_rdata_o(csr_rdata)
  );

  function automatic logic [31:0] imm_i(input logic [31:0] insn);
    imm_i = {{20{insn[31]}}, insn[31:20]};
  endfunction

  function automatic logic [31:0] imm_s(input logic [31:0] insn);
    imm_s = {{20{insn[31]}}, insn[31:25], insn[11:7]};
  endfunction

  function automatic logic [31:0] imm_b(input logic [31:0] insn);
    imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
  endfunction

  function automatic logic [31:0] imm_u(input logic [31:0] insn);
    imm_u = {insn[31:12], 12'h000};
  endfunction

  function automatic logic [31:0] imm_j(input logic [31:0] insn);
    imm_j = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
  endfunction

  task automatic write_rd(input logic [4:0] rd_i, input logic [31:0] data_i);
    begin
      if (rd_i != 5'd0) begin
        regs_q[rd_i] <= data_i;
      end
    end
  endtask

  task automatic csr_write(input logic [11:0] csr_i, input logic [31:0] data_i);
    begin
      unique case (csr_i)
        CSR_MSTATUS: csr_mstatus_q <= data_i & 32'h0000_1888;
        CSR_MTVEC: csr_mtvec_q <= {data_i[31:2], data_i[1:0]};
        CSR_MSCRATCH: csr_mscratch_q <= data_i;
        CSR_MEPC: csr_mepc_q <= {data_i[31:2], 2'b00};
        CSR_MCAUSE: csr_mcause_q <= data_i;
        CSR_MTVAL: csr_mtval_q <= data_i;
        CSR_MCYCLE: csr_mcycle_q[31:0] <= data_i;
        CSR_MCYCLEH: csr_mcycle_q[63:32] <= data_i;
        CSR_MINSTRET: csr_minstret_q[31:0] <= data_i;
        CSR_MINSTRETH: csr_minstret_q[63:32] <= data_i;
        default: begin
        end
      endcase
    end
  endtask

  task automatic retire(
    input logic        trap_i,
    input logic [31:0] insn_i,
    input logic [31:0] pc_rdata_i,
    input logic [31:0] pc_wdata_i,
    input logic [4:0]  rs1_addr_i,
    input logic [4:0]  rs2_addr_i,
    input logic [31:0] rs1_rdata_i,
    input logic [31:0] rs2_rdata_i,
    input logic [4:0]  rd_addr_i,
    input logic [31:0] rd_wdata_i,
    input logic [31:0] mem_addr_i,
    input logic [3:0]  mem_rmask_i,
    input logic [3:0]  mem_wmask_i,
    input logic [31:0] mem_rdata_i,
    input logic [31:0] mem_wdata_i
  );
    begin
      rvfi_valid <= 1'b1;
      rvfi_insn <= insn_i;
      rvfi_trap <= trap_i;
      rvfi_halt <= core_halt_q;
      rvfi_rs1_addr <= rs1_addr_i;
      rvfi_rs2_addr <= rs2_addr_i;
      rvfi_rs1_rdata <= rs1_rdata_i;
      rvfi_rs2_rdata <= rs2_rdata_i;
      rvfi_rd_addr <= rd_addr_i;
      rvfi_rd_wdata <= rd_wdata_i;
      rvfi_pc_rdata <= pc_rdata_i;
      rvfi_pc_wdata <= pc_wdata_i;
      rvfi_mem_addr <= mem_addr_i;
      rvfi_mem_rmask <= mem_rmask_i;
      rvfi_mem_wmask <= mem_wmask_i;
      rvfi_mem_rdata <= mem_rdata_i;
      rvfi_mem_wdata <= mem_wdata_i;
      rvfi_order <= rvfi_order + 64'd1;
      csr_minstret_q <= csr_minstret_q + 64'd1;
    end
  endtask

  task automatic take_trap(
    input logic [31:0] cause_i,
    input logic [31:0] tval_i,
    input logic [31:0] epc_i
  );
    begin
      csr_mepc_q <= {epc_i[31:2], 2'b00};
      csr_mcause_q <= cause_i;
      csr_mtval_q <= tval_i;
      pc_q <= {csr_mtvec_q[31:2], 2'b00};
      prefetch_pending_q <= 1'b0;
      control_busy_q <= 1'b0;
      core_trap_q <= 1'b1;
    end
  endtask

  always_comb begin
    issue_alu_op = ALU_ADD;
    issue_alu_lhs = issue_rs1_value;
    issue_alu_rhs = imm_i(d_insn_q);
    issue_alu_shamt = d_insn_q[24:20];
    unique case (d_decode_q.opcode)
      OPCODE_LUI: begin
        issue_alu_op = ALU_PASS;
        issue_alu_lhs = 32'h0000_0000;
        issue_alu_rhs = imm_u(d_insn_q);
      end
      OPCODE_AUIPC: begin
        issue_alu_op = ALU_ADD;
        issue_alu_lhs = d_pc_q;
        issue_alu_rhs = imm_u(d_insn_q);
      end
      OPCODE_LOAD: begin
        issue_alu_op = ALU_ADD;
        issue_alu_lhs = issue_rs1_value;
        issue_alu_rhs = imm_i(d_insn_q);
      end
      OPCODE_STORE: begin
        issue_alu_op = ALU_ADD;
        issue_alu_lhs = issue_rs1_value;
        issue_alu_rhs = imm_s(d_insn_q);
      end
      OPCODE_BRANCH: begin
        issue_alu_op = ALU_SUB;
        issue_alu_lhs = issue_rs1_value;
        issue_alu_rhs = issue_rs2_value;
      end
      OPCODE_OP_IMM: begin
        issue_alu_lhs = issue_rs1_value;
        issue_alu_rhs = imm_i(d_insn_q);
        unique case (d_decode_q.funct3)
          3'b000: issue_alu_op = ALU_ADD;
          3'b010: issue_alu_op = ALU_SLT;
          3'b011: issue_alu_op = ALU_SLTU;
          3'b100: issue_alu_op = ALU_XOR;
          3'b110: issue_alu_op = ALU_OR;
          3'b111: issue_alu_op = ALU_AND;
          3'b001: issue_alu_op = ALU_SLL;
          3'b101: issue_alu_op = (d_decode_q.funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
          default: issue_alu_op = ALU_ADD;
        endcase
      end
      OPCODE_OP: begin
        issue_alu_lhs = issue_rs1_value;
        issue_alu_rhs = issue_rs2_value;
        issue_alu_shamt = issue_rs2_value[4:0];
        unique case (d_decode_q.funct3)
          3'b000: issue_alu_op = (d_decode_q.funct7 == 7'b0100000) ? ALU_SUB : ALU_ADD;
          3'b001: issue_alu_op = ALU_SLL;
          3'b010: issue_alu_op = ALU_SLT;
          3'b011: issue_alu_op = ALU_SLTU;
          3'b100: issue_alu_op = ALU_XOR;
          3'b101: issue_alu_op = (d_decode_q.funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
          3'b110: issue_alu_op = ALU_OR;
          3'b111: issue_alu_op = ALU_AND;
          default: issue_alu_op = ALU_ADD;
        endcase
      end
      default: begin
      end
    endcase
  end

  integer reg_index;

  always_ff @(posedge clk or negedge rst_n) begin
    logic        retire_happened;
    logic        issue_happened;
    logic        control_retired;
    logic [4:0]  retire_rd;
    logic [31:0] branch_target;
    logic        branch_taken;
    logic [31:0] csr_old;
    logic [31:0] csr_new;
    logic [31:0] csr_source;
    logic        csr_do_write;

    if (!rst_n) begin
      state_q <= ST_PREFETCH;
      prefetch_pending_q <= 1'b0;
      control_busy_q <= 1'b0;
      outstanding_q <= 4'd0;
      reg_busy_q <= 32'h0000_0000;
      pc_q <= RESET_VECTOR;
      insn_q <= 32'h0000_0013;
      insn_pc_q <= RESET_VECTOR;
      insn_fetch_err_q <= 1'b0;
      csr_mstatus_q <= 32'h0000_1800;
      csr_mtvec_q <= 32'h0000_0000;
      csr_mscratch_q <= 32'h0000_0000;
      csr_mepc_q <= 32'h0000_0000;
      csr_mcause_q <= 32'h0000_0000;
      csr_mtval_q <= 32'h0000_0000;
      csr_mcycle_q <= 64'h0000_0000_0000_0000;
      csr_minstret_q <= 64'h0000_0000_0000_0000;
      core_halt_q <= 1'b0;
      core_trap_q <= 1'b0;

      d_insn_q <= 32'h0000_0013;
      d_pc_q <= RESET_VECTOR;
      d_pc_next_q <= RESET_VECTOR + 32'd4;
      d_decode_q.opcode <= OPCODE_OP_IMM;
      d_decode_q.rd <= 5'd0;
      d_decode_q.funct3 <= 3'b000;
      d_decode_q.rs1 <= 5'd0;
      d_decode_q.rs2 <= 5'd0;
      d_decode_q.funct7 <= 7'b0000000;
      d_decode_q.csr_addr <= 12'h000;
      d_fetch_error_q <= 1'b0;
      d_decode_q.illegal <= 1'b0;
      d_decode_q.uses_rs1 <= 1'b0;
      d_decode_q.uses_rs2 <= 1'b0;
      d_decode_q.writes_rd <= 1'b0;
      d_decode_q.serial <= 1'b0;
      d_decode_q.to_alu <= 1'b1;
      d_decode_q.to_muldiv <= 1'b0;
      d_decode_q.to_lsu <= 1'b0;
      d_decode_q.lsu_write <= 1'b0;

      alu_busy_q <= 1'b0;
      alu_done_q <= 1'b0;
      alu_control_q <= 1'b0;
      alu_trap_q <= 1'b0;
      alu_trap_cause_q <= 32'h0000_0000;
      alu_trap_tval_q <= 32'h0000_0000;
      alu_insn_q <= 32'h0000_0013;
      alu_pc_rdata_q <= RESET_VECTOR;
      alu_pc_wdata_q <= RESET_VECTOR;
      alu_rs1_addr_q <= 5'd0;
      alu_rs2_addr_q <= 5'd0;
      alu_rs1_rdata_q <= 32'h0000_0000;
      alu_rs2_rdata_q <= 32'h0000_0000;
      alu_rd_write_q <= 1'b0;
      alu_rd_addr_q <= 5'd0;
      alu_rd_wdata_q <= 32'h0000_0000;
      alu_csr_write_q <= 1'b0;
      alu_csr_addr_q <= 12'h000;
      alu_csr_wdata_q <= 32'h0000_0000;

      muldiv_busy_q <= 1'b0;
      muldiv_done_q <= 1'b0;
      muldiv_count_q <= 2'd0;
      muldiv_insn_q <= 32'h0000_0013;
      muldiv_pc_rdata_q <= RESET_VECTOR;
      muldiv_pc_wdata_q <= RESET_VECTOR;
      muldiv_rs1_addr_q <= 5'd0;
      muldiv_rs2_addr_q <= 5'd0;
      muldiv_rs1_rdata_q <= 32'h0000_0000;
      muldiv_rs2_rdata_q <= 32'h0000_0000;
      muldiv_rd_write_q <= 1'b0;
      muldiv_rd_addr_q <= 5'd0;
      muldiv_rd_wdata_q <= 32'h0000_0000;

      lsu_start_q <= 1'b0;
      lsu_busy_q <= 1'b0;
      lsu_done_q <= 1'b0;
      lsu_write_q <= 1'b0;
      lsu_trap_q <= 1'b0;
      lsu_trap_cause_q <= 32'h0000_0000;
      lsu_trap_tval_q <= 32'h0000_0000;
      lsu_insn_q <= 32'h0000_0013;
      lsu_pc_rdata_q <= RESET_VECTOR;
      lsu_pc_wdata_q <= RESET_VECTOR;
      lsu_rs1_addr_q <= 5'd0;
      lsu_rs2_addr_q <= 5'd0;
      lsu_rs1_rdata_q <= 32'h0000_0000;
      lsu_rs2_rdata_q <= 32'h0000_0000;
      lsu_rd_write_q <= 1'b0;
      lsu_rd_addr_q <= 5'd0;
      lsu_rd_wdata_q <= 32'h0000_0000;
      lsu_mem_addr_q <= 32'h0000_0000;
      lsu_mem_rmask_q <= 4'h0;
      lsu_mem_wmask_q <= 4'h0;
      lsu_mem_rdata_q <= 32'h0000_0000;
      lsu_mem_wdata_q <= 32'h0000_0000;

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

      for (reg_index = 0; reg_index < 32; reg_index = reg_index + 1) begin
        regs_q[reg_index] <= 32'h0000_0000;
      end
    end else begin
      retire_happened = 1'b0;
      issue_happened = 1'b0;
      control_retired = 1'b0;
      retire_rd = 5'd0;
      branch_target = 32'h0000_0000;
      branch_taken = 1'b0;
      csr_old = 32'h0000_0000;
      csr_new = 32'h0000_0000;
      csr_source = 32'h0000_0000;
      csr_do_write = 1'b0;

      rvfi_valid <= 1'b0;
      rvfi_trap <= 1'b0;
      rvfi_halt <= core_halt_q;
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
      csr_mcycle_q <= csr_mcycle_q + 64'd1;
      regs_q[0] <= 32'h0000_0000;
      lsu_start_q <= 1'b0;

      if (muldiv_busy_q && !muldiv_done_q) begin
        if (muldiv_count_q == 2'd0) begin
          muldiv_done_q <= 1'b1;
        end else begin
          muldiv_count_q <= muldiv_count_q - 2'd1;
        end
      end

      if (lsu_busy_q && !lsu_done_q && lsu_engine_done) begin
        lsu_done_q <= 1'b1;
        lsu_trap_q <= lsu_engine_error;
        lsu_trap_cause_q <= lsu_write_q ? EXC_STORE_ACCESS_FAULT : EXC_LOAD_ACCESS_FAULT;
        lsu_trap_tval_q <= lsu_engine_mem_addr;
        lsu_rd_wdata_q <= lsu_engine_load_data;
        lsu_mem_addr_q <= lsu_engine_mem_addr;
        lsu_mem_rmask_q <= lsu_engine_mem_rmask;
        lsu_mem_wmask_q <= lsu_engine_mem_wmask;
        lsu_mem_rdata_q <= lsu_engine_mem_rdata;
        lsu_mem_wdata_q <= lsu_engine_mem_wdata;
      end

      if (lsu_wb_valid) begin
        retire_happened = 1'b1;
        retire_rd = lsu_rd_write_q ? lsu_rd_addr_q : 5'd0;
        retire(
          lsu_trap_q,
          lsu_insn_q,
          lsu_pc_rdata_q,
          lsu_trap_q ? {csr_mtvec_q[31:2], 2'b00} : lsu_pc_wdata_q,
          lsu_rs1_addr_q,
          lsu_rs2_addr_q,
          lsu_rs1_rdata_q,
          lsu_rs2_rdata_q,
          lsu_rd_write_q ? lsu_rd_addr_q : 5'd0,
          lsu_rd_write_q ? lsu_rd_wdata_q : 32'h0000_0000,
          lsu_mem_addr_q,
          lsu_mem_rmask_q,
          lsu_mem_wmask_q,
          lsu_mem_rdata_q,
          lsu_mem_wdata_q
        );
        if (lsu_trap_q) begin
          take_trap(lsu_trap_cause_q, lsu_trap_tval_q, lsu_pc_rdata_q);
        end else if (lsu_rd_write_q) begin
          write_rd(lsu_rd_addr_q, lsu_rd_wdata_q);
        end
        lsu_busy_q <= 1'b0;
        lsu_done_q <= 1'b0;
      end else if (muldiv_wb_valid) begin
        retire_happened = 1'b1;
        retire_rd = muldiv_rd_write_q ? muldiv_rd_addr_q : 5'd0;
        retire(
          1'b0,
          muldiv_insn_q,
          muldiv_pc_rdata_q,
          muldiv_pc_wdata_q,
          muldiv_rs1_addr_q,
          muldiv_rs2_addr_q,
          muldiv_rs1_rdata_q,
          muldiv_rs2_rdata_q,
          muldiv_rd_write_q ? muldiv_rd_addr_q : 5'd0,
          muldiv_rd_write_q ? muldiv_rd_wdata_q : 32'h0000_0000,
          32'h0000_0000,
          4'h0,
          4'h0,
          32'h0000_0000,
          32'h0000_0000
        );
        if (muldiv_rd_write_q) begin
          write_rd(muldiv_rd_addr_q, muldiv_rd_wdata_q);
        end
        muldiv_busy_q <= 1'b0;
        muldiv_done_q <= 1'b0;
      end else if (alu_wb_valid) begin
        retire_happened = 1'b1;
        control_retired = alu_control_q;
        retire_rd = alu_rd_write_q ? alu_rd_addr_q : 5'd0;
        retire(
          alu_trap_q,
          alu_insn_q,
          alu_pc_rdata_q,
          alu_trap_q ? {csr_mtvec_q[31:2], 2'b00} : alu_pc_wdata_q,
          alu_rs1_addr_q,
          alu_rs2_addr_q,
          alu_rs1_rdata_q,
          alu_rs2_rdata_q,
          alu_rd_write_q ? alu_rd_addr_q : 5'd0,
          alu_rd_write_q ? alu_rd_wdata_q : 32'h0000_0000,
          32'h0000_0000,
          4'h0,
          4'h0,
          32'h0000_0000,
          32'h0000_0000
        );
        if (alu_trap_q) begin
          take_trap(alu_trap_cause_q, alu_trap_tval_q, alu_pc_rdata_q);
        end else begin
          if (alu_rd_write_q) begin
            write_rd(alu_rd_addr_q, alu_rd_wdata_q);
          end
          if (alu_csr_write_q) begin
            csr_write(alu_csr_addr_q, alu_csr_wdata_q);
          end
          if (alu_control_q) begin
            pc_q <= alu_pc_wdata_q;
            control_busy_q <= 1'b0;
          end
        end
        alu_busy_q <= 1'b0;
        alu_done_q <= 1'b0;
      end

      if (retire_happened && (retire_rd != 5'd0)) begin
        reg_busy_q[retire_rd] <= 1'b0;
      end

      unique case (state_q)
        ST_PREFETCH: begin
          if (core_halt_q || control_busy_q) begin
            state_q <= ST_PREFETCH;
          end else if (!prefetch_pending_q) begin
            if (imem_req_ready) begin
              prefetch_pending_q <= 1'b1;
            end
          end else if (imem_rsp_valid) begin
            prefetch_pending_q <= 1'b0;
            insn_q <= imem_rsp_rdata;
            insn_pc_q <= pc_q;
            insn_fetch_err_q <= imem_rsp_err;
            state_q <= ST_DECODE;
          end
        end

        ST_DECODE: begin
          d_insn_q <= insn_q;
          d_pc_q <= insn_pc_q;
          d_pc_next_q <= insn_pc_q + 32'd4;
          d_decode_q.opcode <= decode_info.opcode;
          d_decode_q.rd <= decode_info.rd;
          d_decode_q.funct3 <= decode_info.funct3;
          d_decode_q.rs1 <= decode_info.rs1;
          d_decode_q.rs2 <= decode_info.rs2;
          d_decode_q.funct7 <= decode_info.funct7;
          d_decode_q.csr_addr <= decode_info.csr_addr;
          d_fetch_error_q <= insn_fetch_err_q;
          d_decode_q.illegal <= decode_info.illegal;
          d_decode_q.uses_rs1 <= decode_info.uses_rs1;
          d_decode_q.uses_rs2 <= decode_info.uses_rs2;
          d_decode_q.writes_rd <= decode_info.writes_rd;
          d_decode_q.serial <= decode_info.serial;
          d_decode_q.to_lsu <= decode_info.to_lsu;
          d_decode_q.to_muldiv <= decode_info.to_muldiv;
          d_decode_q.to_alu <= decode_info.to_alu;
          d_decode_q.lsu_write <= decode_info.lsu_write;
          state_q <= ST_EXECUTION;
        end

        ST_EXECUTION: begin
          if (issue_allowed) begin
            issue_happened = 1'b1;
            if (d_decode_q.to_lsu) begin
              lsu_start_q <= 1'b1;
              lsu_busy_q <= 1'b1;
              lsu_done_q <= 1'b0;
              lsu_write_q <= d_decode_q.lsu_write;
              lsu_trap_q <= 1'b0;
              lsu_insn_q <= d_insn_q;
              lsu_pc_rdata_q <= d_pc_q;
              lsu_pc_wdata_q <= d_pc_next_q;
              lsu_rs1_addr_q <= d_decode_q.rs1;
              lsu_rs2_addr_q <= d_decode_q.lsu_write ? d_decode_q.rs2 : 5'd0;
              lsu_rs1_rdata_q <= issue_rs1_value;
              lsu_rs2_rdata_q <= d_decode_q.lsu_write ? issue_rs2_value : 32'h0000_0000;
              lsu_rd_write_q <= !d_decode_q.lsu_write;
              lsu_rd_addr_q <= d_decode_q.rd;
              lsu_rd_wdata_q <= 32'h0000_0000;
              lsu_mem_addr_q <= issue_alu_result;
              lsu_mem_rmask_q <= 4'h0;
              lsu_mem_wmask_q <= 4'h0;
              lsu_mem_rdata_q <= 32'h0000_0000;
              lsu_mem_wdata_q <= 32'h0000_0000;
              pc_q <= d_pc_next_q;
              state_q <= ST_PREFETCH;
            end else if (d_decode_q.to_muldiv) begin
              muldiv_busy_q <= 1'b1;
              muldiv_done_q <= 1'b0;
              muldiv_count_q <= 2'd2;
              muldiv_insn_q <= d_insn_q;
              muldiv_pc_rdata_q <= d_pc_q;
              muldiv_pc_wdata_q <= d_pc_next_q;
              muldiv_rs1_addr_q <= d_decode_q.rs1;
              muldiv_rs2_addr_q <= d_decode_q.rs2;
              muldiv_rs1_rdata_q <= issue_rs1_value;
              muldiv_rs2_rdata_q <= issue_rs2_value;
              muldiv_rd_write_q <= 1'b1;
              muldiv_rd_addr_q <= d_decode_q.rd;
              muldiv_rd_wdata_q <= issue_muldiv_result;
              pc_q <= d_pc_next_q;
              state_q <= ST_PREFETCH;
            end else begin
              alu_busy_q <= 1'b1;
              alu_done_q <= 1'b1;
              alu_control_q <= d_decode_q.serial;
              alu_trap_q <= 1'b0;
              alu_trap_cause_q <= 32'h0000_0000;
              alu_trap_tval_q <= 32'h0000_0000;
              alu_insn_q <= d_insn_q;
              alu_pc_rdata_q <= d_pc_q;
              alu_pc_wdata_q <= d_pc_next_q;
              alu_rs1_addr_q <= d_decode_q.uses_rs1 ? d_decode_q.rs1 : 5'd0;
              alu_rs2_addr_q <= d_decode_q.uses_rs2 ? d_decode_q.rs2 : 5'd0;
              alu_rs1_rdata_q <= d_decode_q.uses_rs1 ? issue_rs1_value : 32'h0000_0000;
              alu_rs2_rdata_q <= d_decode_q.uses_rs2 ? issue_rs2_value : 32'h0000_0000;
              alu_rd_write_q <= d_decode_q.writes_rd;
              alu_rd_addr_q <= d_decode_q.rd;
              alu_rd_wdata_q <= issue_alu_result;
              alu_csr_write_q <= 1'b0;
              alu_csr_addr_q <= 12'h000;
              alu_csr_wdata_q <= 32'h0000_0000;

              if (d_fetch_error_q) begin
                alu_trap_q <= 1'b1;
                alu_trap_cause_q <= EXC_INSTR_ACCESS_FAULT;
                alu_trap_tval_q <= d_pc_q;
                alu_rd_write_q <= 1'b0;
              end else if (d_decode_q.illegal) begin
                alu_trap_q <= 1'b1;
                alu_trap_cause_q <= EXC_ILLEGAL_INSTR;
                alu_trap_tval_q <= d_insn_q;
                alu_rd_write_q <= 1'b0;
              end else begin
                unique case (d_decode_q.opcode)
                  OPCODE_LUI,
                  OPCODE_AUIPC,
                  OPCODE_OP_IMM: begin
                    alu_rd_wdata_q <= issue_alu_result;
                  end

                  OPCODE_OP: begin
                    alu_rd_wdata_q <= issue_alu_result;
                  end

                  OPCODE_JAL: begin
                    branch_target = d_pc_q + imm_j(d_insn_q);
                    alu_rd_wdata_q <= d_pc_next_q;
                    if (branch_target[1:0] != 2'b00) begin
                      alu_trap_q <= 1'b1;
                      alu_trap_cause_q <= EXC_INSTR_ADDR_MISALIGNED;
                      alu_trap_tval_q <= branch_target;
                      alu_rd_write_q <= 1'b0;
                    end else begin
                      alu_pc_wdata_q <= branch_target;
                    end
                  end

                  OPCODE_JALR: begin
                    branch_target = (issue_rs1_value + imm_i(d_insn_q)) & 32'hffff_fffe;
                    alu_rd_wdata_q <= d_pc_next_q;
                    if (branch_target[1:0] != 2'b00) begin
                      alu_trap_q <= 1'b1;
                      alu_trap_cause_q <= EXC_INSTR_ADDR_MISALIGNED;
                      alu_trap_tval_q <= branch_target;
                      alu_rd_write_q <= 1'b0;
                    end else begin
                      alu_pc_wdata_q <= branch_target;
                    end
                  end

                  OPCODE_BRANCH: begin
                    unique case (d_decode_q.funct3)
                      3'b000: branch_taken = issue_cmp_eq;
                      3'b001: branch_taken = issue_cmp_ne;
                      3'b100: branch_taken = issue_cmp_lts;
                      3'b101: branch_taken = issue_cmp_ges;
                      3'b110: branch_taken = issue_cmp_ltu;
                      3'b111: branch_taken = issue_cmp_geu;
                      default: branch_taken = 1'b0;
                    endcase
                    branch_target = branch_taken ? (d_pc_q + imm_b(d_insn_q)) : d_pc_next_q;
                    alu_rd_write_q <= 1'b0;
                    if (branch_taken && (branch_target[1:0] != 2'b00)) begin
                      alu_trap_q <= 1'b1;
                      alu_trap_cause_q <= EXC_INSTR_ADDR_MISALIGNED;
                      alu_trap_tval_q <= branch_target;
                    end else begin
                      alu_pc_wdata_q <= branch_target;
                    end
                  end

                  OPCODE_MISC_MEM: begin
                    alu_rd_write_q <= 1'b0;
                  end

                  OPCODE_SYSTEM: begin
                    if (d_decode_q.funct3 == 3'b000) begin
                      unique case (d_insn_q)
                        INSN_ECALL: begin
                          alu_trap_q <= 1'b1;
                          alu_trap_cause_q <= EXC_ECALL_MMODE;
                          alu_trap_tval_q <= 32'h0000_0000;
                          alu_rd_write_q <= 1'b0;
                        end
                        INSN_EBREAK: begin
                          alu_trap_q <= 1'b1;
                          alu_trap_cause_q <= EXC_BREAKPOINT;
                          alu_trap_tval_q <= 32'h0000_0000;
                          alu_rd_write_q <= 1'b0;
                        end
                        INSN_MRET: begin
                          alu_pc_wdata_q <= csr_mepc_q;
                          alu_rd_write_q <= 1'b0;
                        end
                        INSN_WFI: begin
                          alu_pc_wdata_q <= d_pc_next_q;
                          alu_rd_write_q <= 1'b0;
                        end
                        default: begin
                          alu_trap_q <= 1'b1;
                          alu_trap_cause_q <= EXC_ILLEGAL_INSTR;
                          alu_trap_tval_q <= d_insn_q;
                          alu_rd_write_q <= 1'b0;
                        end
                      endcase
                    end else begin
                      csr_old = csr_rdata;
                      csr_source = d_decode_q.funct3[2] ? {27'h0000000, d_decode_q.rs1} : issue_rs1_value;
                      unique case (d_decode_q.funct3)
                        3'b001,
                        3'b101: begin
                          csr_new = csr_source;
                          csr_do_write = 1'b1;
                        end
                        3'b010,
                        3'b110: begin
                          csr_new = csr_old | csr_source;
                          csr_do_write = (csr_source != 32'h0000_0000);
                        end
                        3'b011,
                        3'b111: begin
                          csr_new = csr_old & ~csr_source;
                          csr_do_write = (csr_source != 32'h0000_0000);
                        end
                        default: begin
                          csr_new = 32'h0000_0000;
                          csr_do_write = 1'b0;
                        end
                      endcase
                      alu_rd_write_q <= 1'b1;
                      alu_rd_wdata_q <= csr_old;
                      alu_csr_write_q <= csr_do_write;
                      alu_csr_addr_q <= d_decode_q.csr_addr;
                      alu_csr_wdata_q <= csr_new;
                    end
                  end

                  default: begin
                    alu_trap_q <= 1'b1;
                    alu_trap_cause_q <= EXC_ILLEGAL_INSTR;
                    alu_trap_tval_q <= d_insn_q;
                    alu_rd_write_q <= 1'b0;
                  end
                endcase
              end

              if (d_decode_q.serial) begin
                control_busy_q <= 1'b1;
                state_q <= ST_WRITE_BACK;
              end else begin
                pc_q <= d_pc_next_q;
                state_q <= ST_PREFETCH;
              end
            end

            if (d_decode_q.writes_rd && (d_decode_q.rd != 5'd0)) begin
              reg_busy_q[d_decode_q.rd] <= 1'b1;
            end
          end
        end

        ST_WRITE_BACK: begin
          if (control_retired) begin
            state_q <= ST_PREFETCH;
          end else begin
            state_q <= ST_WRITE_BACK;
          end
        end

        default: begin
          state_q <= ST_PREFETCH;
        end
      endcase

      if (issue_happened && !retire_happened) begin
        outstanding_q <= outstanding_q + 4'd1;
      end else if (!issue_happened && retire_happened) begin
        outstanding_q <= outstanding_q - 4'd1;
      end
    end
  end

`ifndef SYNTHESIS
  default clocking riscv32im_core_cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  assert_no_x0_write:
    assert property (regs_q[0] == 32'h0000_0000)
    else $error("x0 changed value");

  cover_retire:
    cover property (rvfi_valid && !rvfi_trap);

  cover_trap:
    cover property (rvfi_valid && rvfi_trap);

  cover_memory_write:
    cover property (rvfi_valid && (rvfi_mem_wmask != 4'h0));
`endif
endmodule
