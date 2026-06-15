`timescale 1ns/1ps

module riscv32im_decode (
  input  logic        fetch_error_i,
  input  logic [31:0] insn_i,

  output riscv32im_decode_info_t decode_o
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

  assign decode_o.opcode = insn_i[6:0];
  assign decode_o.rd = insn_i[11:7];
  assign decode_o.funct3 = insn_i[14:12];
  assign decode_o.rs1 = insn_i[19:15];
  assign decode_o.rs2 = insn_i[24:20];
  assign decode_o.funct7 = insn_i[31:25];
  assign decode_o.csr_addr = insn_i[31:20];

  assign valid_load = (decode_o.funct3 == 3'b000) ||
                      (decode_o.funct3 == 3'b001) ||
                      (decode_o.funct3 == 3'b010) ||
                      (decode_o.funct3 == 3'b100) ||
                      (decode_o.funct3 == 3'b101);

  assign valid_store = (decode_o.funct3 == 3'b000) ||
                       (decode_o.funct3 == 3'b001) ||
                       (decode_o.funct3 == 3'b010);

  always_comb begin
    decode_o.illegal = 1'b0;
    decode_o.uses_rs1 = 1'b0;
    decode_o.uses_rs2 = 1'b0;
    decode_o.writes_rd = 1'b0;
    decode_o.serial = fetch_error_i;
    decode_o.to_lsu = 1'b0;
    decode_o.to_muldiv = 1'b0;
    decode_o.lsu_write = 1'b0;

    if (fetch_error_i) begin
      decode_o.illegal = 1'b0;
    end else if (insn_i[1:0] != 2'b11) begin
      decode_o.illegal = 1'b1;
    end else begin
      unique case (decode_o.opcode)
        OPCODE_LUI,
        OPCODE_AUIPC: begin
          decode_o.writes_rd = 1'b1;
        end

        OPCODE_JAL: begin
          decode_o.writes_rd = 1'b1;
          decode_o.serial = 1'b1;
        end

        OPCODE_JALR: begin
          decode_o.uses_rs1 = 1'b1;
          decode_o.writes_rd = 1'b1;
          decode_o.serial = 1'b1;
          decode_o.illegal = (decode_o.funct3 != 3'b000);
        end

        OPCODE_BRANCH: begin
          decode_o.uses_rs1 = 1'b1;
          decode_o.uses_rs2 = 1'b1;
          decode_o.serial = 1'b1;
          decode_o.illegal = (decode_o.funct3 == 3'b010) || (decode_o.funct3 == 3'b011);
        end

        OPCODE_LOAD: begin
          decode_o.uses_rs1 = 1'b1;
          decode_o.writes_rd = 1'b1;
          decode_o.to_lsu = valid_load;
          decode_o.illegal = !valid_load;
        end

        OPCODE_STORE: begin
          decode_o.uses_rs1 = 1'b1;
          decode_o.uses_rs2 = 1'b1;
          decode_o.to_lsu = valid_store;
          decode_o.lsu_write = 1'b1;
          decode_o.illegal = !valid_store;
        end

        OPCODE_OP_IMM: begin
          decode_o.uses_rs1 = 1'b1;
          decode_o.writes_rd = 1'b1;
          decode_o.illegal = ((decode_o.funct3 == 3'b001) && (decode_o.funct7 != 7'b0000000)) ||
                             ((decode_o.funct3 == 3'b101) && !((decode_o.funct7 == 7'b0000000) || (decode_o.funct7 == 7'b0100000)));
        end

        OPCODE_OP: begin
          decode_o.uses_rs1 = 1'b1;
          decode_o.uses_rs2 = 1'b1;
          decode_o.writes_rd = 1'b1;
          decode_o.to_muldiv = (decode_o.funct7 == 7'b0000001);
          decode_o.illegal = !((decode_o.funct7 == 7'b0000001) ||
                               (decode_o.funct7 == 7'b0000000) ||
                               ((decode_o.funct7 == 7'b0100000) && ((decode_o.funct3 == 3'b000) || (decode_o.funct3 == 3'b101))));
        end

        OPCODE_MISC_MEM: begin
          decode_o.serial = 1'b1;
          decode_o.illegal = !((decode_o.funct3 == 3'b000) || (decode_o.funct3 == 3'b001));
        end

        OPCODE_SYSTEM: begin
          decode_o.serial = 1'b1;
          if (decode_o.funct3 == 3'b000) begin
            decode_o.illegal = !((insn_i == INSN_ECALL) ||
                                 (insn_i == INSN_EBREAK) ||
                                 (insn_i == INSN_MRET) ||
                                 (insn_i == INSN_WFI));
          end else begin
            decode_o.uses_rs1 = !decode_o.funct3[2];
            decode_o.writes_rd = 1'b1;
            decode_o.illegal = (decode_o.funct3 == 3'b100);
          end
        end

        default: begin
          decode_o.illegal = 1'b1;
        end
      endcase
    end

    decode_o.serial = decode_o.serial || decode_o.illegal;
    decode_o.to_alu = !(decode_o.to_lsu || decode_o.to_muldiv);
  end
endmodule
