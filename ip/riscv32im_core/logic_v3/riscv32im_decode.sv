`timescale 1ns/1ps

module riscv32im_decode (
  input  logic        fetch_error_i,
  input  logic [31:0] insn_i,

  output logic [6:0]  opcode_o,
  output logic [4:0]  rd_o,
  output logic [2:0]  funct3_o,
  output logic [4:0]  rs1_o,
  output logic [4:0]  rs2_o,
  output logic [6:0]  funct7_o,
  output logic [11:0] csr_addr_o,

  output logic        decode_illegal_o,
  output logic        uses_rs1_o,
  output logic        uses_rs2_o,
  output logic        writes_rd_o,
  output logic        serial_o,
  output logic        to_alu_o,
  output logic        to_muldiv_o,
  output logic        to_lsu_o,
  output logic        lsu_write_o
);
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

  logic valid_load;
  logic valid_store;

  assign opcode_o = insn_i[6:0];
  assign rd_o = insn_i[11:7];
  assign funct3_o = insn_i[14:12];
  assign rs1_o = insn_i[19:15];
  assign rs2_o = insn_i[24:20];
  assign funct7_o = insn_i[31:25];
  assign csr_addr_o = insn_i[31:20];

  assign valid_load = (funct3_o == 3'b000) ||
                      (funct3_o == 3'b001) ||
                      (funct3_o == 3'b010) ||
                      (funct3_o == 3'b100) ||
                      (funct3_o == 3'b101);

  assign valid_store = (funct3_o == 3'b000) ||
                       (funct3_o == 3'b001) ||
                       (funct3_o == 3'b010);

  always_comb begin
    decode_illegal_o = 1'b0;
    uses_rs1_o = 1'b0;
    uses_rs2_o = 1'b0;
    writes_rd_o = 1'b0;
    serial_o = fetch_error_i;
    to_lsu_o = 1'b0;
    to_muldiv_o = 1'b0;
    lsu_write_o = 1'b0;

    if (fetch_error_i) begin
      decode_illegal_o = 1'b0;
    end else if (insn_i[1:0] != 2'b11) begin
      decode_illegal_o = 1'b1;
    end else begin
      unique case (opcode_o)
        OPCODE_LUI,
        OPCODE_AUIPC: begin
          writes_rd_o = 1'b1;
        end

        OPCODE_JAL: begin
          writes_rd_o = 1'b1;
          serial_o = 1'b1;
        end

        OPCODE_JALR: begin
          uses_rs1_o = 1'b1;
          writes_rd_o = 1'b1;
          serial_o = 1'b1;
          decode_illegal_o = (funct3_o != 3'b000);
        end

        OPCODE_BRANCH: begin
          uses_rs1_o = 1'b1;
          uses_rs2_o = 1'b1;
          serial_o = 1'b1;
          decode_illegal_o = (funct3_o == 3'b010) || (funct3_o == 3'b011);
        end

        OPCODE_LOAD: begin
          uses_rs1_o = 1'b1;
          writes_rd_o = 1'b1;
          to_lsu_o = valid_load;
          decode_illegal_o = !valid_load;
        end

        OPCODE_STORE: begin
          uses_rs1_o = 1'b1;
          uses_rs2_o = 1'b1;
          to_lsu_o = valid_store;
          lsu_write_o = 1'b1;
          decode_illegal_o = !valid_store;
        end

        OPCODE_OP_IMM: begin
          uses_rs1_o = 1'b1;
          writes_rd_o = 1'b1;
          decode_illegal_o = ((funct3_o == 3'b001) && (funct7_o != 7'b0000000)) ||
                             ((funct3_o == 3'b101) && !((funct7_o == 7'b0000000) || (funct7_o == 7'b0100000)));
        end

        OPCODE_OP: begin
          uses_rs1_o = 1'b1;
          uses_rs2_o = 1'b1;
          writes_rd_o = 1'b1;
          to_muldiv_o = (funct7_o == 7'b0000001);
          decode_illegal_o = !((funct7_o == 7'b0000001) ||
                               (funct7_o == 7'b0000000) ||
                               ((funct7_o == 7'b0100000) && ((funct3_o == 3'b000) || (funct3_o == 3'b101))));
        end

        OPCODE_MISC_MEM: begin
          serial_o = 1'b1;
          decode_illegal_o = !((funct3_o == 3'b000) || (funct3_o == 3'b001));
        end

        OPCODE_SYSTEM: begin
          serial_o = 1'b1;
          if (funct3_o == 3'b000) begin
            decode_illegal_o = !((insn_i == INSN_ECALL) ||
                                 (insn_i == INSN_EBREAK) ||
                                 (insn_i == INSN_MRET) ||
                                 (insn_i == INSN_WFI));
          end else begin
            uses_rs1_o = !funct3_o[2];
            writes_rd_o = 1'b1;
            decode_illegal_o = (funct3_o == 3'b100);
          end
        end

        default: begin
          decode_illegal_o = 1'b1;
        end
      endcase
    end

    serial_o = serial_o || decode_illegal_o;
    to_alu_o = !(to_lsu_o || to_muldiv_o);
  end
endmodule
