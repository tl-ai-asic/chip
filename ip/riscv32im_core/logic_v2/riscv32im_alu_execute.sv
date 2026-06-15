`timescale 1ns/1ps

module riscv32im_alu_execute (
  input  logic [31:0] insn_i,
  input  logic [31:0] pc_i,
  input  logic [31:0] pc_next_i,
  input  riscv32im_decode_info_t decode_i,
  input  logic        fetch_error_i,
  input  logic [31:0] rs1_value_i,
  input  logic [31:0] rs2_value_i,
  input  logic [31:0] alu_result_i,
  input  logic        cmp_eq_i,
  input  logic        cmp_ne_i,
  input  logic        cmp_lts_i,
  input  logic        cmp_ges_i,
  input  logic        cmp_ltu_i,
  input  logic        cmp_geu_i,
  input  logic [31:0] csr_rdata_i,
  input  logic [31:0] csr_mepc_i,
  output riscv32im_alu_exec_result_t result_o
);
  localparam logic [6:0] OPCODE_LUI      = 7'b0110111;
  localparam logic [6:0] OPCODE_AUIPC    = 7'b0010111;
  localparam logic [6:0] OPCODE_JAL      = 7'b1101111;
  localparam logic [6:0] OPCODE_JALR     = 7'b1100111;
  localparam logic [6:0] OPCODE_BRANCH   = 7'b1100011;
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
  localparam logic [31:0] EXC_ECALL_MMODE           = 32'd11;

  function automatic logic [31:0] imm_i(input logic [31:0] insn);
    imm_i = {{20{insn[31]}}, insn[31:20]};
  endfunction

  function automatic logic [31:0] imm_b(input logic [31:0] insn);
    imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
  endfunction

  function automatic logic [31:0] imm_j(input logic [31:0] insn);
    imm_j = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
  endfunction

  always_comb begin
    logic [31:0] branch_target;
    logic        branch_taken;
    logic [31:0] csr_old;
    logic [31:0] csr_new;
    logic [31:0] csr_source;
    logic        csr_do_write;

    branch_target = 32'h0000_0000;
    branch_taken = 1'b0;
    csr_old = 32'h0000_0000;
    csr_new = 32'h0000_0000;
    csr_source = 32'h0000_0000;
    csr_do_write = 1'b0;

    result_o = '0;
    result_o.control = decode_i.serial;
    result_o.insn = insn_i;
    result_o.pc_rdata = pc_i;
    result_o.pc_wdata = pc_next_i;
    result_o.rs1_addr = decode_i.uses_rs1 ? decode_i.rs1 : 5'd0;
    result_o.rs2_addr = decode_i.uses_rs2 ? decode_i.rs2 : 5'd0;
    result_o.rs1_rdata = decode_i.uses_rs1 ? rs1_value_i : 32'h0000_0000;
    result_o.rs2_rdata = decode_i.uses_rs2 ? rs2_value_i : 32'h0000_0000;
    result_o.rd_write = decode_i.writes_rd;
    result_o.rd_addr = decode_i.rd;
    result_o.rd_wdata = alu_result_i;

    if (fetch_error_i) begin
      result_o.trap = 1'b1;
      result_o.trap_cause = EXC_INSTR_ACCESS_FAULT;
      result_o.trap_tval = pc_i;
      result_o.rd_write = 1'b0;
    end else if (decode_i.illegal) begin
      result_o.trap = 1'b1;
      result_o.trap_cause = EXC_ILLEGAL_INSTR;
      result_o.trap_tval = insn_i;
      result_o.rd_write = 1'b0;
    end else begin
      unique case (decode_i.opcode)
        OPCODE_LUI,
        OPCODE_AUIPC,
        OPCODE_OP_IMM,
        OPCODE_OP: begin
          result_o.rd_wdata = alu_result_i;
        end

        OPCODE_JAL: begin
          branch_target = pc_i + imm_j(insn_i);
          result_o.rd_wdata = pc_next_i;
          if (branch_target[1:0] != 2'b00) begin
            result_o.trap = 1'b1;
            result_o.trap_cause = EXC_INSTR_ADDR_MISALIGNED;
            result_o.trap_tval = branch_target;
            result_o.rd_write = 1'b0;
          end else begin
            result_o.pc_wdata = branch_target;
          end
        end

        OPCODE_JALR: begin
          branch_target = (rs1_value_i + imm_i(insn_i)) & 32'hffff_fffe;
          result_o.rd_wdata = pc_next_i;
          if (branch_target[1:0] != 2'b00) begin
            result_o.trap = 1'b1;
            result_o.trap_cause = EXC_INSTR_ADDR_MISALIGNED;
            result_o.trap_tval = branch_target;
            result_o.rd_write = 1'b0;
          end else begin
            result_o.pc_wdata = branch_target;
          end
        end

        OPCODE_BRANCH: begin
          unique case (decode_i.funct3)
            3'b000: branch_taken = cmp_eq_i;
            3'b001: branch_taken = cmp_ne_i;
            3'b100: branch_taken = cmp_lts_i;
            3'b101: branch_taken = cmp_ges_i;
            3'b110: branch_taken = cmp_ltu_i;
            3'b111: branch_taken = cmp_geu_i;
            default: branch_taken = 1'b0;
          endcase
          branch_target = branch_taken ? (pc_i + imm_b(insn_i)) : pc_next_i;
          result_o.rd_write = 1'b0;
          if (branch_taken && (branch_target[1:0] != 2'b00)) begin
            result_o.trap = 1'b1;
            result_o.trap_cause = EXC_INSTR_ADDR_MISALIGNED;
            result_o.trap_tval = branch_target;
          end else begin
            result_o.pc_wdata = branch_target;
          end
        end

        OPCODE_MISC_MEM: begin
          result_o.rd_write = 1'b0;
        end

        OPCODE_SYSTEM: begin
          if (decode_i.funct3 == 3'b000) begin
            unique case (insn_i)
              INSN_ECALL: begin
                result_o.trap = 1'b1;
                result_o.trap_cause = EXC_ECALL_MMODE;
                result_o.rd_write = 1'b0;
              end
              INSN_EBREAK: begin
                result_o.trap = 1'b1;
                result_o.trap_cause = EXC_BREAKPOINT;
                result_o.rd_write = 1'b0;
              end
              INSN_MRET: begin
                result_o.pc_wdata = csr_mepc_i;
                result_o.rd_write = 1'b0;
              end
              INSN_WFI: begin
                result_o.pc_wdata = pc_next_i;
                result_o.rd_write = 1'b0;
              end
              default: begin
                result_o.trap = 1'b1;
                result_o.trap_cause = EXC_ILLEGAL_INSTR;
                result_o.trap_tval = insn_i;
                result_o.rd_write = 1'b0;
              end
            endcase
          end else begin
            csr_old = csr_rdata_i;
            csr_source = decode_i.funct3[2] ? {27'h0000000, decode_i.rs1} : rs1_value_i;
            unique case (decode_i.funct3)
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
            result_o.rd_write = 1'b1;
            result_o.rd_wdata = csr_old;
            result_o.csr_write = csr_do_write;
            result_o.csr_addr = decode_i.csr_addr;
            result_o.csr_wdata = csr_new;
          end
        end

        default: begin
          result_o.trap = 1'b1;
          result_o.trap_cause = EXC_ILLEGAL_INSTR;
          result_o.trap_tval = insn_i;
          result_o.rd_write = 1'b0;
        end
      endcase
    end
  end
endmodule
