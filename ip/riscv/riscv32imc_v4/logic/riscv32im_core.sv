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

  state_e      state_q;
  logic [31:0] insn_q;
  logic [31:0] insn_pc_q;
  logic [31:0] insn_predicted_pc_q;
  logic        insn_fetch_err_q;

  logic        core_halt_q;
  logic        core_trap_q;

  logic [31:0] d_insn_q;
  logic [31:0] d_pc_q;
  logic [31:0] d_pc_next_q;
  logic [31:0] d_predicted_pc_q;
  logic        d_fetch_error_q;
  riscv32im_decode_info_t d_decode_q;

  riscv32im_decode_info_t decode_info;

  riscv32im_issue_info_t        scoreboard_issue;
  riscv32im_engine_busy_t       scoreboard_engines;
  riscv32im_retire_info_t       scoreboard_retire;
  riscv32im_scoreboard_status_t scoreboard_status;
  riscv32im_rvfi_retire_info_t  rvfi_retire;

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
  riscv32im_alu_exec_result_t alu_exec_result;

  riscv32im_decode_info_t fast_decode_info;
  logic [31:0] fast_rs1_value;
  logic [31:0] fast_rs2_value;
  logic [3:0]  fast_alu_op;
  logic [31:0] fast_alu_lhs;
  logic [31:0] fast_alu_rhs;
  logic [4:0]  fast_alu_shamt;
  logic [31:0] fast_alu_result;
  logic        fast_cmp_eq;
  logic        fast_cmp_ne;
  logic        fast_cmp_lts;
  logic        fast_cmp_ges;
  logic        fast_cmp_ltu;
  logic        fast_cmp_geu;
  logic        fast_fire;
  logic        fast_branch_fire;
  logic        fast_branch_taken;
  logic [31:0] fast_branch_target;
  logic        fast_muldiv_candidate;
  logic        fast_muldiv_fire;
  riscv32im_alu_exec_result_t fast_alu_exec_result;

  logic        alu_busy_q;
  logic        alu_done_q;
  logic        alu_control_q;
  logic        alu_trap_q;
  logic [31:0] alu_trap_cause_q;
  logic [31:0] alu_trap_tval_q;
  logic [31:0] alu_insn_q;
  logic [31:0] alu_pc_rdata_q;
  logic [31:0] alu_pc_wdata_q;
  logic [31:0] alu_predicted_pc_q;
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

  logic                         muldiv_req_valid;
  logic                         muldiv_req_ready;
  logic                         muldiv_rsp_valid;
  logic                         muldiv_rsp_ready;
  riscv32im_muldiv_issue_info_t muldiv_issue;
  riscv32im_muldiv_rsp_info_t   muldiv_rsp;

  logic        lsu_start_q;
  riscv32im_lsu_issue_info_t lsu_issue;
  riscv32im_lsu_rsp_info_t   lsu_rsp;
  logic        lsu_issue_ready;
  logic        lsu_rsp_valid;
  logic        lsu_engine_busy;

  logic        alu_wb_valid;
  logic        muldiv_wb_valid;
  logic        lsu_wb_valid;
  logic        alu_wb_selected;
  logic        muldiv_wb_selected;
  logic        lsu_wb_selected;
  logic        issue_fire;
  logic        control_retired;
  logic        retire_redirect;
  logic        prefetch_fetch_enable;
  logic        prefetch_consume;
  logic        prefetch_valid;
  logic [31:0] prefetch_insn;
  logic [31:0] prefetch_pc;
  logic [31:0] prefetch_predicted_pc;
  logic        prefetch_err;
  logic [31:0] prefetch_redirect_pc;
  logic [31:0] csr_rdata;
  logic [31:0] csr_mtvec;
  logic [31:0] csr_mepc;
  logic        csr_write_valid;
  logic [11:0] csr_write_addr;
  logic [31:0] csr_write_data;
  logic        csr_trap_valid;
  logic [31:0] csr_trap_cause;
  logic [31:0] csr_trap_tval;
  logic [31:0] csr_trap_epc;
  logic        fast_rd_write;
  logic [4:0]  fast_rd_addr;
  logic [31:0] fast_rd_wdata;
  logic        retire_rd_write;
  logic [4:0]  retire_rd_addr;
  logic [31:0] retire_rd_wdata;

  function automatic logic [31:0] imm_b(input logic [31:0] insn);
    imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
  endfunction

  assign prefetch_fetch_enable = !core_halt_q &&
                                 !retire_redirect &&
                                 ((state_q == ST_PREFETCH) ||
                                  ((state_q == ST_DECODE) && !decode_info.serial) ||
                                  ((state_q == ST_EXECUTION) && !d_decode_q.serial));
  assign prefetch_consume = fast_fire ||
                            fast_branch_fire ||
                            fast_muldiv_fire ||
                            ((state_q == ST_PREFETCH) &&
                             prefetch_valid &&
                             !core_halt_q &&
                             !scoreboard_status.control_busy);

  assign core_halt = core_halt_q;
  assign core_trap = core_trap_q;

  assign alu_wb_valid = alu_busy_q && alu_done_q;
  assign muldiv_wb_valid = muldiv_rsp_valid;
  assign lsu_wb_valid = lsu_rsp_valid;
  assign lsu_wb_selected = lsu_wb_valid;
  assign muldiv_wb_selected = !lsu_wb_valid && muldiv_wb_valid;
  assign alu_wb_selected = !lsu_wb_valid && !muldiv_wb_valid && alu_wb_valid;
  assign muldiv_rsp_ready = !lsu_wb_valid;
  assign control_retired = alu_wb_selected && alu_control_q;
  assign retire_redirect = (lsu_wb_selected && lsu_rsp.trap) ||
                           (alu_wb_selected &&
                            (alu_trap_q ||
                             (alu_control_q && (alu_pc_wdata_q != alu_predicted_pc_q))));
  assign prefetch_redirect_pc = ((lsu_wb_selected && lsu_rsp.trap) ||
                                 (alu_wb_selected && alu_trap_q)) ?
                                {csr_mtvec[31:2], 2'b00} :
                                alu_pc_wdata_q;

  assign csr_write_valid = alu_wb_selected && !alu_trap_q && alu_csr_write_q;
  assign csr_write_addr = alu_csr_addr_q;
  assign csr_write_data = alu_csr_wdata_q;

  assign csr_trap_valid = (lsu_wb_selected && lsu_rsp.trap) || (alu_wb_selected && alu_trap_q);
  assign csr_trap_cause = (lsu_wb_selected && lsu_rsp.trap) ? lsu_rsp.trap_cause : alu_trap_cause_q;
  assign csr_trap_tval = (lsu_wb_selected && lsu_rsp.trap) ? lsu_rsp.trap_tval : alu_trap_tval_q;
  assign csr_trap_epc = (lsu_wb_selected && lsu_rsp.trap) ? lsu_rsp.pc_rdata : alu_pc_rdata_q;
  assign fast_fire = (state_q == ST_PREFETCH) &&
                     prefetch_valid &&
                     !core_halt_q &&
                     !scoreboard_status.control_busy &&
                     (scoreboard_status.outstanding == 4'd0) &&
                     (scoreboard_status.reg_busy == 32'h0000_0000) &&
                     !alu_busy_q &&
                     !muldiv_wb_valid &&
                     !lsu_engine_busy &&
                     fast_decode_info.to_alu &&
                     !fast_decode_info.to_lsu &&
                     !fast_decode_info.to_muldiv &&
                     !fast_decode_info.serial &&
                     !fast_decode_info.illegal &&
                     !prefetch_err;
  always_comb begin
    unique case (fast_decode_info.funct3)
      3'b000: fast_branch_taken = fast_cmp_eq;
      3'b001: fast_branch_taken = fast_cmp_ne;
      3'b100: fast_branch_taken = fast_cmp_lts;
      3'b101: fast_branch_taken = fast_cmp_ges;
      3'b110: fast_branch_taken = fast_cmp_ltu;
      3'b111: fast_branch_taken = fast_cmp_geu;
      default: fast_branch_taken = 1'b0;
    endcase
  end
  assign fast_branch_target = fast_branch_taken ?
                              (prefetch_pc + imm_b(prefetch_insn)) :
                              (prefetch_pc + 32'd4);
  assign fast_branch_fire = (state_q == ST_PREFETCH) &&
                            prefetch_valid &&
                            !core_halt_q &&
                            !scoreboard_status.control_busy &&
                            (scoreboard_status.outstanding == 4'd0) &&
                            (scoreboard_status.reg_busy == 32'h0000_0000) &&
                            !alu_busy_q &&
                            !muldiv_wb_valid &&
                            !lsu_engine_busy &&
                            (fast_decode_info.opcode == 7'b1100011) &&
                            !fast_decode_info.illegal &&
                            !prefetch_err &&
                            (fast_branch_target == prefetch_predicted_pc);
  assign fast_muldiv_candidate = (state_q == ST_PREFETCH) &&
                                 prefetch_valid &&
                                 !core_halt_q &&
                                 fast_decode_info.to_muldiv &&
                                 !fast_decode_info.to_alu &&
                                 !fast_decode_info.to_lsu &&
                                 !fast_decode_info.serial &&
                                 !fast_decode_info.illegal &&
                                 !prefetch_err &&
                                 muldiv_req_ready;
  assign fast_muldiv_fire = fast_muldiv_candidate && scoreboard_status.issue_allowed;

  assign scoreboard_issue.uses_rs1 = fast_muldiv_candidate ? fast_decode_info.uses_rs1 : d_decode_q.uses_rs1;
  assign scoreboard_issue.uses_rs2 = fast_muldiv_candidate ? fast_decode_info.uses_rs2 : d_decode_q.uses_rs2;
  assign scoreboard_issue.writes_rd = fast_muldiv_candidate ? fast_decode_info.writes_rd : d_decode_q.writes_rd;
  assign scoreboard_issue.serial = fast_muldiv_candidate ? fast_decode_info.serial : d_decode_q.serial;
  assign scoreboard_issue.to_alu = fast_muldiv_candidate ? fast_decode_info.to_alu : d_decode_q.to_alu;
  assign scoreboard_issue.to_muldiv = fast_muldiv_candidate ? fast_decode_info.to_muldiv : d_decode_q.to_muldiv;
  assign scoreboard_issue.to_lsu = fast_muldiv_candidate ? fast_decode_info.to_lsu : d_decode_q.to_lsu;
  assign scoreboard_issue.rs1 = fast_muldiv_candidate ? fast_decode_info.rs1 : d_decode_q.rs1;
  assign scoreboard_issue.rs2 = fast_muldiv_candidate ? fast_decode_info.rs2 : d_decode_q.rs2;
  assign scoreboard_issue.rd = fast_muldiv_candidate ? fast_decode_info.rd : d_decode_q.rd;

  assign scoreboard_engines.alu_busy = alu_busy_q;
  assign scoreboard_engines.muldiv_busy = !muldiv_req_ready;
  assign scoreboard_engines.lsu_busy = lsu_engine_busy;

  assign lsu_engine_busy = !lsu_issue_ready;
  assign issue_fire = (state_q == ST_EXECUTION) && scoreboard_status.issue_allowed;

  always_comb begin
    scoreboard_retire = '0;
    if (lsu_wb_selected) begin
      scoreboard_retire.valid = 1'b1;
      scoreboard_retire.writes_rd = lsu_rsp.rd_write;
      scoreboard_retire.rd = lsu_rsp.rd_addr;
      scoreboard_retire.flush_control = lsu_rsp.trap;
    end else if (muldiv_wb_selected) begin
      scoreboard_retire.valid = 1'b1;
      scoreboard_retire.writes_rd = muldiv_rsp.rd_write;
      scoreboard_retire.rd = muldiv_rsp.rd_addr;
    end else if (alu_wb_selected) begin
      scoreboard_retire.valid = 1'b1;
      scoreboard_retire.writes_rd = alu_rd_write_q;
      scoreboard_retire.rd = alu_rd_addr_q;
      scoreboard_retire.control_retired = alu_control_q;
      scoreboard_retire.flush_control = alu_trap_q;
    end
  end

  assign lsu_issue.write = d_decode_q.lsu_write;
  assign lsu_issue.funct3 = d_decode_q.funct3;
  assign lsu_issue.addr = issue_alu_result;
  assign lsu_issue.store_data = issue_rs2_value;
  assign lsu_issue.insn = d_insn_q;
  assign lsu_issue.pc_rdata = d_pc_q;
  assign lsu_issue.pc_wdata = d_pc_next_q;
  assign lsu_issue.rs1_addr = d_decode_q.rs1;
  assign lsu_issue.rs2_addr = d_decode_q.lsu_write ? d_decode_q.rs2 : 5'd0;
  assign lsu_issue.rs1_rdata = issue_rs1_value;
  assign lsu_issue.rs2_rdata = d_decode_q.lsu_write ? issue_rs2_value : 32'h0000_0000;
  assign lsu_issue.rd_write = !d_decode_q.lsu_write;
  assign lsu_issue.rd_addr = d_decode_q.rd;

  assign muldiv_req_valid = ((state_q == ST_EXECUTION) &&
                             issue_fire &&
                             d_decode_q.to_muldiv) ||
                            fast_muldiv_fire;
  assign muldiv_issue.funct3 = fast_muldiv_fire ? fast_decode_info.funct3 : d_decode_q.funct3;
  assign muldiv_issue.lhs = fast_muldiv_fire ? fast_rs1_value : issue_rs1_value;
  assign muldiv_issue.rhs = fast_muldiv_fire ? fast_rs2_value : issue_rs2_value;
  assign muldiv_issue.insn = fast_muldiv_fire ? prefetch_insn : d_insn_q;
  assign muldiv_issue.pc_rdata = fast_muldiv_fire ? prefetch_pc : d_pc_q;
  assign muldiv_issue.pc_wdata = fast_muldiv_fire ? (prefetch_pc + 32'd4) : d_pc_next_q;
  assign muldiv_issue.rs1_addr = fast_muldiv_fire ? fast_decode_info.rs1 : d_decode_q.rs1;
  assign muldiv_issue.rs2_addr = fast_muldiv_fire ? fast_decode_info.rs2 : d_decode_q.rs2;
  assign muldiv_issue.rs1_rdata = fast_muldiv_fire ? fast_rs1_value : issue_rs1_value;
  assign muldiv_issue.rs2_rdata = fast_muldiv_fire ? fast_rs2_value : issue_rs2_value;
  assign muldiv_issue.rd_write = 1'b1;
  assign muldiv_issue.rd_addr = fast_muldiv_fire ? fast_decode_info.rd : d_decode_q.rd;

  always_comb begin
    rvfi_retire = '0;
    rvfi_retire.halt = core_halt_q;

    if (fast_branch_fire) begin
      rvfi_retire.valid = 1'b1;
      rvfi_retire.insn = prefetch_insn;
      rvfi_retire.pc_rdata = prefetch_pc;
      rvfi_retire.pc_wdata = fast_branch_target;
      rvfi_retire.rs1_addr = fast_decode_info.rs1;
      rvfi_retire.rs2_addr = fast_decode_info.rs2;
      rvfi_retire.rs1_rdata = fast_rs1_value;
      rvfi_retire.rs2_rdata = fast_rs2_value;
    end else if (fast_fire) begin
      rvfi_retire.valid = 1'b1;
      rvfi_retire.insn = fast_alu_exec_result.insn;
      rvfi_retire.pc_rdata = fast_alu_exec_result.pc_rdata;
      rvfi_retire.pc_wdata = fast_alu_exec_result.pc_wdata;
      rvfi_retire.rs1_addr = fast_alu_exec_result.rs1_addr;
      rvfi_retire.rs2_addr = fast_alu_exec_result.rs2_addr;
      rvfi_retire.rs1_rdata = fast_alu_exec_result.rs1_rdata;
      rvfi_retire.rs2_rdata = fast_alu_exec_result.rs2_rdata;
      rvfi_retire.rd_addr = fast_alu_exec_result.rd_write ? fast_alu_exec_result.rd_addr : 5'd0;
      rvfi_retire.rd_wdata = fast_alu_exec_result.rd_write ? fast_alu_exec_result.rd_wdata : 32'h0000_0000;
    end else if (lsu_wb_selected) begin
      rvfi_retire.valid = 1'b1;
      rvfi_retire.trap = lsu_rsp.trap;
      rvfi_retire.insn = lsu_rsp.insn;
      rvfi_retire.pc_rdata = lsu_rsp.pc_rdata;
      rvfi_retire.pc_wdata = lsu_rsp.trap ? {csr_mtvec[31:2], 2'b00} : lsu_rsp.pc_wdata;
      rvfi_retire.rs1_addr = lsu_rsp.rs1_addr;
      rvfi_retire.rs2_addr = lsu_rsp.rs2_addr;
      rvfi_retire.rs1_rdata = lsu_rsp.rs1_rdata;
      rvfi_retire.rs2_rdata = lsu_rsp.rs2_rdata;
      rvfi_retire.rd_addr = lsu_rsp.rd_write ? lsu_rsp.rd_addr : 5'd0;
      rvfi_retire.rd_wdata = lsu_rsp.rd_write ? lsu_rsp.rd_wdata : 32'h0000_0000;
      rvfi_retire.mem_addr = lsu_rsp.mem_addr;
      rvfi_retire.mem_rmask = lsu_rsp.mem_rmask;
      rvfi_retire.mem_wmask = lsu_rsp.mem_wmask;
      rvfi_retire.mem_rdata = lsu_rsp.mem_rdata;
      rvfi_retire.mem_wdata = lsu_rsp.mem_wdata;
    end else if (muldiv_wb_selected) begin
      rvfi_retire.valid = 1'b1;
      rvfi_retire.insn = muldiv_rsp.insn;
      rvfi_retire.pc_rdata = muldiv_rsp.pc_rdata;
      rvfi_retire.pc_wdata = muldiv_rsp.pc_wdata;
      rvfi_retire.rs1_addr = muldiv_rsp.rs1_addr;
      rvfi_retire.rs2_addr = muldiv_rsp.rs2_addr;
      rvfi_retire.rs1_rdata = muldiv_rsp.rs1_rdata;
      rvfi_retire.rs2_rdata = muldiv_rsp.rs2_rdata;
      rvfi_retire.rd_addr = muldiv_rsp.rd_write ? muldiv_rsp.rd_addr : 5'd0;
      rvfi_retire.rd_wdata = muldiv_rsp.rd_write ? muldiv_rsp.rd_wdata : 32'h0000_0000;
    end else if (alu_wb_selected) begin
      rvfi_retire.valid = 1'b1;
      rvfi_retire.trap = alu_trap_q;
      rvfi_retire.insn = alu_insn_q;
      rvfi_retire.pc_rdata = alu_pc_rdata_q;
      rvfi_retire.pc_wdata = alu_trap_q ? {csr_mtvec[31:2], 2'b00} : alu_pc_wdata_q;
      rvfi_retire.rs1_addr = alu_rs1_addr_q;
      rvfi_retire.rs2_addr = alu_rs2_addr_q;
      rvfi_retire.rs1_rdata = alu_rs1_rdata_q;
      rvfi_retire.rs2_rdata = alu_rs2_rdata_q;
      rvfi_retire.rd_addr = alu_rd_write_q ? alu_rd_addr_q : 5'd0;
      rvfi_retire.rd_wdata = alu_rd_write_q ? alu_rd_wdata_q : 32'h0000_0000;
    end
  end

  riscv32im_writeback_router u_writeback_router (
    .fast_fire_i(fast_fire),
    .fast_alu_result_i(fast_alu_exec_result),
    .lsu_wb_selected_i(lsu_wb_selected),
    .lsu_rsp_i(lsu_rsp),
    .muldiv_wb_selected_i(muldiv_wb_selected),
    .muldiv_rsp_i(muldiv_rsp),
    .alu_wb_selected_i(alu_wb_selected),
    .alu_trap_i(alu_trap_q),
    .alu_rd_write_i(alu_rd_write_q),
    .alu_rd_addr_i(alu_rd_addr_q),
    .alu_rd_wdata_i(alu_rd_wdata_q),
    .fast_write_valid_o(fast_rd_write),
    .fast_write_addr_o(fast_rd_addr),
    .fast_write_data_o(fast_rd_wdata),
    .retire_write_valid_o(retire_rd_write),
    .retire_write_addr_o(retire_rd_addr),
    .retire_write_data_o(retire_rd_wdata)
  );

  riscv32im_register_file u_register_file (
    .clk(clk),
    .rst_n(rst_n),
    .issue_rs1_addr_i(d_decode_q.rs1),
    .issue_rs1_data_o(issue_rs1_value),
    .issue_rs2_addr_i(d_decode_q.rs2),
    .issue_rs2_data_o(issue_rs2_value),
    .fast_rs1_addr_i(fast_decode_info.rs1),
    .fast_rs1_data_o(fast_rs1_value),
    .fast_rs2_addr_i(fast_decode_info.rs2),
    .fast_rs2_data_o(fast_rs2_value),
    .fast_write_valid_i(fast_rd_write),
    .fast_write_addr_i(fast_rd_addr),
    .fast_write_data_i(fast_rd_wdata),
    .retire_write_valid_i(retire_rd_write),
    .retire_write_addr_i(retire_rd_addr),
    .retire_write_data_i(retire_rd_wdata)
  );

  riscv32im_scoreboard u_scoreboard (
    .clk(clk),
    .rst_n(rst_n),
    .issue_stage_i((state_q == ST_EXECUTION) || fast_muldiv_candidate),
    .issue_fire_i(issue_fire || fast_muldiv_fire),
    .issue_i(scoreboard_issue),
    .engines_i(scoreboard_engines),
    .retire_i(scoreboard_retire),
    .status_o(scoreboard_status)
  );

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

  riscv32im_alu u_fast_alu (
    .op_i(fast_alu_op),
    .lhs_i(fast_alu_lhs),
    .rhs_i(fast_alu_rhs),
    .shamt_i(fast_alu_shamt),
    .result_o(fast_alu_result),
    .cmp_eq_o(fast_cmp_eq),
    .cmp_ne_o(fast_cmp_ne),
    .cmp_lts_o(fast_cmp_lts),
    .cmp_ges_o(fast_cmp_ges),
    .cmp_ltu_o(fast_cmp_ltu),
    .cmp_geu_o(fast_cmp_geu)
  );

  riscv32im_muldiv u_issue_muldiv (
    .clk(clk),
    .rst_n(rst_n),
    .req_valid_i(muldiv_req_valid),
    .req_ready_o(muldiv_req_ready),
    .req_i(muldiv_issue),
    .rsp_valid_o(muldiv_rsp_valid),
    .rsp_ready_i(muldiv_rsp_ready),
    .rsp_o(muldiv_rsp)
  );

  riscv32im_issue_prepare u_issue_prepare (
    .insn_i(d_insn_q),
    .pc_i(d_pc_q),
    .decode_i(d_decode_q),
    .rs1_value_i(issue_rs1_value),
    .rs2_value_i(issue_rs2_value),
    .alu_op_o(issue_alu_op),
    .alu_lhs_o(issue_alu_lhs),
    .alu_rhs_o(issue_alu_rhs),
    .alu_shamt_o(issue_alu_shamt)
  );

  riscv32im_issue_prepare u_fast_issue_prepare (
    .insn_i(prefetch_insn),
    .pc_i(prefetch_pc),
    .decode_i(fast_decode_info),
    .rs1_value_i(fast_rs1_value),
    .rs2_value_i(fast_rs2_value),
    .alu_op_o(fast_alu_op),
    .alu_lhs_o(fast_alu_lhs),
    .alu_rhs_o(fast_alu_rhs),
    .alu_shamt_o(fast_alu_shamt)
  );

  riscv32im_alu_execute u_alu_execute (
    .insn_i(d_insn_q),
    .pc_i(d_pc_q),
    .pc_next_i(d_pc_next_q),
    .decode_i(d_decode_q),
    .fetch_error_i(d_fetch_error_q),
    .rs1_value_i(issue_rs1_value),
    .rs2_value_i(issue_rs2_value),
    .alu_result_i(issue_alu_result),
    .cmp_eq_i(issue_cmp_eq),
    .cmp_ne_i(issue_cmp_ne),
    .cmp_lts_i(issue_cmp_lts),
    .cmp_ges_i(issue_cmp_ges),
    .cmp_ltu_i(issue_cmp_ltu),
    .cmp_geu_i(issue_cmp_geu),
    .csr_rdata_i(csr_rdata),
    .csr_mepc_i(csr_mepc),
    .result_o(alu_exec_result)
  );

  riscv32im_alu_execute u_fast_alu_execute (
    .insn_i(prefetch_insn),
    .pc_i(prefetch_pc),
    .pc_next_i(prefetch_pc + 32'd4),
    .decode_i(fast_decode_info),
    .fetch_error_i(prefetch_err),
    .rs1_value_i(fast_rs1_value),
    .rs2_value_i(fast_rs2_value),
    .alu_result_i(fast_alu_result),
    .cmp_eq_i(fast_cmp_eq),
    .cmp_ne_i(fast_cmp_ne),
    .cmp_lts_i(fast_cmp_lts),
    .cmp_ges_i(fast_cmp_ges),
    .cmp_ltu_i(fast_cmp_ltu),
    .cmp_geu_i(fast_cmp_geu),
    .csr_rdata_i(csr_rdata),
    .csr_mepc_i(csr_mepc),
    .result_o(fast_alu_exec_result)
  );

  riscv32im_lsu u_lsu (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(lsu_start_q),
    .issue_i(lsu_issue),
    .issue_ready_o(lsu_issue_ready),
    .rsp_valid_o(lsu_rsp_valid),
    .rsp_ready_i(1'b1),
    .rsp_o(lsu_rsp),
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

  riscv32im_decode u_fast_decode (
    .fetch_error_i(prefetch_err),
    .insn_i(prefetch_insn),
    .decode_o(fast_decode_info)
  );

  riscv32im_prefetch #(
    .DEPTH(4),
    .RESET_VECTOR(RESET_VECTOR)
  ) u_prefetch (
    .clk(clk),
    .rst_n(rst_n),
    .fetch_enable_i(prefetch_fetch_enable),
    .consume_i(prefetch_consume),
    .consume_valid_o(prefetch_valid),
    .consume_insn_o(prefetch_insn),
    .consume_pc_o(prefetch_pc),
    .consume_predicted_pc_o(prefetch_predicted_pc),
    .consume_err_o(prefetch_err),
    .redirect_valid_i(retire_redirect),
    .redirect_pc_i(prefetch_redirect_pc),
    .imem_req_valid(imem_req_valid),
    .imem_req_ready(imem_req_ready),
    .imem_req_addr(imem_req_addr),
    .imem_rsp_valid(imem_rsp_valid),
    .imem_rsp_rdata(imem_rsp_rdata),
    .imem_rsp_err(imem_rsp_err)
  );

  riscv32im_csr_file #(
    .HART_ID(HART_ID)
  ) u_csr_file (
    .clk(clk),
    .rst_n(rst_n),
    .csr_addr_i(d_decode_q.csr_addr),
    .csr_rdata_o(csr_rdata),
    .csr_mtvec_o(csr_mtvec),
    .csr_mepc_o(csr_mepc),
    .write_valid_i(csr_write_valid),
    .write_addr_i(csr_write_addr),
    .write_data_i(csr_write_data),
    .trap_valid_i(csr_trap_valid),
    .trap_cause_i(csr_trap_cause),
    .trap_tval_i(csr_trap_tval),
    .trap_epc_i(csr_trap_epc),
    .retire_valid_i(rvfi_retire.valid)
  );

  riscv32im_rvfi_trace u_rvfi_trace (
    .clk(clk),
    .rst_n(rst_n),
    .retire_i(rvfi_retire),
    .rvfi_valid(rvfi_valid),
    .rvfi_order(rvfi_order),
    .rvfi_insn(rvfi_insn),
    .rvfi_trap(rvfi_trap),
    .rvfi_halt(rvfi_halt),
    .rvfi_intr(rvfi_intr),
    .rvfi_mode(rvfi_mode),
    .rvfi_ixl(rvfi_ixl),
    .rvfi_rs1_addr(rvfi_rs1_addr),
    .rvfi_rs2_addr(rvfi_rs2_addr),
    .rvfi_rs1_rdata(rvfi_rs1_rdata),
    .rvfi_rs2_rdata(rvfi_rs2_rdata),
    .rvfi_rd_addr(rvfi_rd_addr),
    .rvfi_rd_wdata(rvfi_rd_wdata),
    .rvfi_pc_rdata(rvfi_pc_rdata),
    .rvfi_pc_wdata(rvfi_pc_wdata),
    .rvfi_mem_addr(rvfi_mem_addr),
    .rvfi_mem_rmask(rvfi_mem_rmask),
    .rvfi_mem_wmask(rvfi_mem_wmask),
    .rvfi_mem_rdata(rvfi_mem_rdata),
    .rvfi_mem_wdata(rvfi_mem_wdata)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_PREFETCH;
      insn_q <= 32'h0000_0013;
      insn_pc_q <= RESET_VECTOR;
      insn_predicted_pc_q <= RESET_VECTOR + 32'd4;
      insn_fetch_err_q <= 1'b0;
      core_halt_q <= 1'b0;
      core_trap_q <= 1'b0;

      d_insn_q <= 32'h0000_0013;
      d_pc_q <= RESET_VECTOR;
      d_pc_next_q <= RESET_VECTOR + 32'd4;
      d_predicted_pc_q <= RESET_VECTOR + 32'd4;
      d_decode_q.opcode <= 7'b0010011;
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
      alu_predicted_pc_q <= RESET_VECTOR + 32'd4;
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

      lsu_start_q <= 1'b0;
    end else begin
      lsu_start_q <= 1'b0;

      if (lsu_wb_selected) begin
        if (lsu_rsp.trap) begin
          core_trap_q <= 1'b1;
        end
      end else if (muldiv_wb_selected) begin
      end else if (alu_wb_selected) begin
        if (alu_trap_q) begin
          core_trap_q <= 1'b1;
        end
        alu_busy_q <= 1'b0;
        alu_done_q <= 1'b0;
      end

      unique case (state_q)
        ST_PREFETCH: begin
          if (core_halt_q || scoreboard_status.control_busy) begin
            state_q <= ST_PREFETCH;
          end else if (fast_fire) begin
            state_q <= ST_PREFETCH;
          end else if (fast_branch_fire) begin
            state_q <= ST_PREFETCH;
          end else if (fast_muldiv_fire) begin
            state_q <= ST_PREFETCH;
          end else if (prefetch_valid) begin
            insn_q <= prefetch_insn;
            insn_pc_q <= prefetch_pc;
            insn_predicted_pc_q <= prefetch_predicted_pc;
            insn_fetch_err_q <= prefetch_err;
            state_q <= ST_DECODE;
          end
        end

        ST_DECODE: begin
          d_insn_q <= insn_q;
          d_pc_q <= insn_pc_q;
          d_pc_next_q <= insn_pc_q + 32'd4;
          d_predicted_pc_q <= insn_predicted_pc_q;
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
          if (issue_fire) begin
            if (d_decode_q.to_lsu) begin
              lsu_start_q <= 1'b1;
              state_q <= ST_PREFETCH;
            end else if (d_decode_q.to_muldiv) begin
              state_q <= ST_PREFETCH;
            end else begin
              alu_busy_q <= 1'b1;
              alu_done_q <= 1'b1;
              alu_control_q <= alu_exec_result.control;
              alu_trap_q <= alu_exec_result.trap;
              alu_trap_cause_q <= alu_exec_result.trap_cause;
              alu_trap_tval_q <= alu_exec_result.trap_tval;
              alu_insn_q <= alu_exec_result.insn;
              alu_pc_rdata_q <= alu_exec_result.pc_rdata;
              alu_pc_wdata_q <= alu_exec_result.pc_wdata;
              alu_predicted_pc_q <= d_predicted_pc_q;
              alu_rs1_addr_q <= alu_exec_result.rs1_addr;
              alu_rs2_addr_q <= alu_exec_result.rs2_addr;
              alu_rs1_rdata_q <= alu_exec_result.rs1_rdata;
              alu_rs2_rdata_q <= alu_exec_result.rs2_rdata;
              alu_rd_write_q <= alu_exec_result.rd_write;
              alu_rd_addr_q <= alu_exec_result.rd_addr;
              alu_rd_wdata_q <= alu_exec_result.rd_wdata;
              alu_csr_write_q <= alu_exec_result.csr_write;
              alu_csr_addr_q <= alu_exec_result.csr_addr;
              alu_csr_wdata_q <= alu_exec_result.csr_wdata;

              if (d_decode_q.serial) begin
                state_q <= ST_WRITE_BACK;
              end else begin
                state_q <= ST_PREFETCH;
              end
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
    end
  end

`ifndef SYNTHESIS
  default clocking riscv32im_core_cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  cover_retire:
    cover property (rvfi_valid && !rvfi_trap);

  cover_trap:
    cover property (rvfi_valid && rvfi_trap);

  cover_memory_write:
    cover property (rvfi_valid && (rvfi_mem_wmask != 4'h0));
`endif
endmodule
