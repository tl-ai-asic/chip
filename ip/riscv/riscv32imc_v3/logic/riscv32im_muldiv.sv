`timescale 1ns/1ps

module riscv32im_muldiv #(
  parameter int PIPE_STAGES = 2
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         req_valid_i,
  output logic                         req_ready_o,
  input  riscv32im_muldiv_issue_info_t req_i,
  output logic                         rsp_valid_o,
  input  logic                         rsp_ready_i,
  output riscv32im_muldiv_rsp_info_t   rsp_o
);
  logic [PIPE_STAGES:0] valid_q;

  riscv32im_muldiv_rsp_info_t rsp_q [0:PIPE_STAGES];

  logic [2:0]  funct3_q [0:PIPE_STAGES];
  logic        is_div_q [0:PIPE_STAGES];
  logic        is_rem_q [0:PIPE_STAGES];

  logic [31:0] mul_lhs_abs_q [0:PIPE_STAGES];
  logic [31:0] mul_rhs_abs_q [0:PIPE_STAGES];
  logic [63:0] mul_product_abs_q [0:PIPE_STAGES];
  logic        mul_negative_q [0:PIPE_STAGES];
  logic        mul_high_q [0:PIPE_STAGES];

  logic [31:0] div_dividend_q [0:PIPE_STAGES];
  logic [31:0] div_divisor_q [0:PIPE_STAGES];
  logic [31:0] div_quotient_q [0:PIPE_STAGES];
  logic [32:0] div_remainder_q [0:PIPE_STAGES];
  logic        div_by_zero_q [0:PIPE_STAGES];
  logic        div_overflow_q [0:PIPE_STAGES];
  logic        div_quot_negative_q [0:PIPE_STAGES];
  logic        div_rem_negative_q [0:PIPE_STAGES];

  riscv32im_muldiv_rsp_info_t fifo_rsp_q [0:3];
  logic [1:0] fifo_rd_ptr_q;
  logic [1:0] fifo_wr_ptr_q;
  logic [2:0] fifo_count_q;

  logic        advance;
  logic        rsp_dequeue;
  logic        mul_produce;
  logic        div_produce;
  logic        req_is_div;
  logic        req_is_rem;
  logic        req_lhs_signed;
  logic        req_rhs_signed;
  logic        req_lhs_negative;
  logic        req_rhs_negative;
  logic [31:0] req_lhs_abs;
  logic [31:0] req_rhs_abs;

  integer pipe_index;
  integer init_index;
  integer mul_bit;
  integer div_bit_index;

  logic [63:0] mul_product_next;
  logic [63:0] mul_product_signed;
  logic [32:0] div_remainder_shift;
  logic [32:0] div_remainder_sub;
  logic [32:0] div_remainder_next;
  logic [31:0] div_quotient_next;
  logic [31:0] div_result_next;
  logic [1:0] fifo_wr_ptr_next;
  logic [2:0] fifo_count_next;
  logic [32:0] div_remainder_work;
  logic [31:0] div_quotient_work;

  localparam int MUL_STAGES = 2;
  localparam int MUL_BITS_PER_STAGE = 16;
  localparam int DIV_BITS_PER_STAGE = 16;
  localparam int DIV_STAGES = 2;

  assign rsp_dequeue = rsp_valid_o && rsp_ready_i;
  assign advance = (fifo_count_q <= 3'd2);
  assign req_ready_o = advance;
  assign rsp_valid_o = (fifo_count_q != 3'd0);
  assign rsp_o = fifo_rsp_q[fifo_rd_ptr_q];
  assign mul_produce = advance && valid_q[MUL_STAGES] && !is_div_q[MUL_STAGES];
  assign div_produce = advance && valid_q[DIV_STAGES] && is_div_q[DIV_STAGES];

  assign req_is_div = req_i.funct3[2];
  assign req_is_rem = req_i.funct3[2] && req_i.funct3[1];
  assign req_lhs_signed = (req_i.funct3 == 3'b001) ||
                          (req_i.funct3 == 3'b010) ||
                          (req_i.funct3 == 3'b100) ||
                          (req_i.funct3 == 3'b110);
  assign req_rhs_signed = (req_i.funct3 == 3'b001) ||
                          (req_i.funct3 == 3'b100) ||
                          (req_i.funct3 == 3'b110);
  assign req_lhs_negative = req_lhs_signed && req_i.lhs[31];
  assign req_rhs_negative = req_rhs_signed && req_i.rhs[31];
  assign req_lhs_abs = req_lhs_negative ? (~req_i.lhs + 32'd1) : req_i.lhs;
  assign req_rhs_abs = req_rhs_negative ? (~req_i.rhs + 32'd1) : req_i.rhs;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (init_index = 0; init_index <= PIPE_STAGES; init_index = init_index + 1) begin
        valid_q[init_index] <= 1'b0;
        rsp_q[init_index] <= '0;
        funct3_q[init_index] <= 3'b000;
        is_div_q[init_index] <= 1'b0;
        is_rem_q[init_index] <= 1'b0;
        mul_lhs_abs_q[init_index] <= 32'h0000_0000;
        mul_rhs_abs_q[init_index] <= 32'h0000_0000;
        mul_product_abs_q[init_index] <= 64'h0000_0000_0000_0000;
        mul_negative_q[init_index] <= 1'b0;
        mul_high_q[init_index] <= 1'b0;
        div_dividend_q[init_index] <= 32'h0000_0000;
        div_divisor_q[init_index] <= 32'h0000_0000;
        div_quotient_q[init_index] <= 32'h0000_0000;
        div_remainder_q[init_index] <= 33'h0;
        div_by_zero_q[init_index] <= 1'b0;
        div_overflow_q[init_index] <= 1'b0;
        div_quot_negative_q[init_index] <= 1'b0;
        div_rem_negative_q[init_index] <= 1'b0;
      end
      for (init_index = 0; init_index < 4; init_index = init_index + 1) begin
        fifo_rsp_q[init_index] <= '0;
      end
      fifo_rd_ptr_q <= 2'd0;
      fifo_wr_ptr_q <= 2'd0;
      fifo_count_q <= 3'd0;
    end else begin
      fifo_wr_ptr_next = fifo_wr_ptr_q;
      fifo_count_next = fifo_count_q;
      if (rsp_dequeue) begin
        fifo_rd_ptr_q <= fifo_rd_ptr_q + 2'd1;
        fifo_count_next = fifo_count_next - 3'd1;
      end
      if (div_produce) begin
        fifo_rsp_q[fifo_wr_ptr_next] <= rsp_q[DIV_STAGES];
        fifo_wr_ptr_next = fifo_wr_ptr_next + 2'd1;
        fifo_count_next = fifo_count_next + 3'd1;
      end
      if (mul_produce) begin
        fifo_rsp_q[fifo_wr_ptr_next] <= rsp_q[MUL_STAGES];
        fifo_wr_ptr_next = fifo_wr_ptr_next + 2'd1;
        fifo_count_next = fifo_count_next + 3'd1;
      end
      fifo_wr_ptr_q <= fifo_wr_ptr_next;
      fifo_count_q <= fifo_count_next;

      if (advance) begin
        valid_q[0] <= req_valid_i;
        rsp_q[0].insn <= req_i.insn;
        rsp_q[0].pc_rdata <= req_i.pc_rdata;
        rsp_q[0].pc_wdata <= req_i.pc_wdata;
        rsp_q[0].rs1_addr <= req_i.rs1_addr;
        rsp_q[0].rs2_addr <= req_i.rs2_addr;
        rsp_q[0].rs1_rdata <= req_i.rs1_rdata;
        rsp_q[0].rs2_rdata <= req_i.rs2_rdata;
        rsp_q[0].rd_write <= req_i.rd_write;
        rsp_q[0].rd_addr <= req_i.rd_addr;
        rsp_q[0].rd_wdata <= 32'h0000_0000;
        funct3_q[0] <= req_i.funct3;
        is_div_q[0] <= req_is_div;
        is_rem_q[0] <= req_is_rem;

        mul_lhs_abs_q[0] <= req_lhs_abs;
        mul_rhs_abs_q[0] <= req_rhs_abs;
        mul_product_abs_q[0] <= 64'h0000_0000_0000_0000;
        mul_negative_q[0] <= !req_is_div && (req_lhs_negative ^ req_rhs_negative);
        mul_high_q[0] <= !req_is_div && (req_i.funct3 != 3'b000);

        div_dividend_q[0] <= req_lhs_abs;
        div_divisor_q[0] <= req_rhs_abs;
        div_quotient_q[0] <= 32'h0000_0000;
        div_remainder_q[0] <= 33'h0;
        div_by_zero_q[0] <= req_is_div && (req_i.rhs == 32'h0000_0000);
        div_overflow_q[0] <= req_is_div &&
                             ((req_i.funct3 == 3'b100) || (req_i.funct3 == 3'b110)) &&
                             (req_i.lhs == 32'h8000_0000) &&
                             (req_i.rhs == 32'hffff_ffff);
        div_quot_negative_q[0] <= req_is_div && (req_i.funct3 == 3'b100) &&
                                  (req_i.lhs[31] ^ req_i.rhs[31]);
        div_rem_negative_q[0] <= req_is_div && (req_i.funct3 == 3'b110) && req_i.lhs[31];

        for (pipe_index = 0; pipe_index < PIPE_STAGES; pipe_index = pipe_index + 1) begin
          valid_q[pipe_index + 1] <= valid_q[pipe_index];
          rsp_q[pipe_index + 1] <= rsp_q[pipe_index];
          funct3_q[pipe_index + 1] <= funct3_q[pipe_index];
          is_div_q[pipe_index + 1] <= is_div_q[pipe_index];
          is_rem_q[pipe_index + 1] <= is_rem_q[pipe_index];

        mul_lhs_abs_q[pipe_index + 1] <= mul_lhs_abs_q[pipe_index];
        mul_rhs_abs_q[pipe_index + 1] <= mul_rhs_abs_q[pipe_index];
        mul_product_abs_q[pipe_index + 1] <= mul_product_abs_q[pipe_index];
        mul_negative_q[pipe_index + 1] <= mul_negative_q[pipe_index];
        mul_high_q[pipe_index + 1] <= mul_high_q[pipe_index];

        div_dividend_q[pipe_index + 1] <= div_dividend_q[pipe_index];
        div_divisor_q[pipe_index + 1] <= div_divisor_q[pipe_index];
        div_quotient_q[pipe_index + 1] <= div_quotient_q[pipe_index];
        div_remainder_q[pipe_index + 1] <= div_remainder_q[pipe_index];
        div_by_zero_q[pipe_index + 1] <= div_by_zero_q[pipe_index];
        div_overflow_q[pipe_index + 1] <= div_overflow_q[pipe_index];
        div_quot_negative_q[pipe_index + 1] <= div_quot_negative_q[pipe_index];
        div_rem_negative_q[pipe_index + 1] <= div_rem_negative_q[pipe_index];

        if (valid_q[pipe_index] && !is_div_q[pipe_index] && (pipe_index < MUL_STAGES)) begin
          mul_product_next = mul_product_abs_q[pipe_index];
          for (mul_bit = 0; mul_bit < MUL_BITS_PER_STAGE; mul_bit = mul_bit + 1) begin
            if (mul_rhs_abs_q[pipe_index][(pipe_index * MUL_BITS_PER_STAGE) + mul_bit]) begin
              mul_product_next = mul_product_next +
                                 ({32'h0000_0000, mul_lhs_abs_q[pipe_index]} <<
                                  ((pipe_index * MUL_BITS_PER_STAGE) + mul_bit));
            end
          end

          mul_product_abs_q[pipe_index + 1] <= mul_product_next;
          if (pipe_index == (MUL_STAGES - 1)) begin
            mul_product_signed = mul_negative_q[pipe_index] ? (~mul_product_next + 64'd1) : mul_product_next;
            rsp_q[pipe_index + 1].rd_wdata <= mul_high_q[pipe_index] ?
                                              mul_product_signed[63:32] :
                                              mul_product_signed[31:0];
          end
        end

        if (valid_q[pipe_index] && is_div_q[pipe_index] && (pipe_index < DIV_STAGES)) begin
          div_remainder_work = div_remainder_q[pipe_index];
          div_quotient_work = div_quotient_q[pipe_index];

          for (div_bit_index = 0; div_bit_index < DIV_BITS_PER_STAGE; div_bit_index = div_bit_index + 1) begin
            div_remainder_shift = {
              div_remainder_work[31:0],
              div_dividend_q[pipe_index][31 - ((pipe_index * DIV_BITS_PER_STAGE) + div_bit_index)]
            };
            div_remainder_work = div_remainder_shift;

            if (!div_by_zero_q[pipe_index] &&
                !div_overflow_q[pipe_index] &&
                (div_remainder_shift >= {1'b0, div_divisor_q[pipe_index]})) begin
              div_remainder_sub = div_remainder_shift - {1'b0, div_divisor_q[pipe_index]};
              div_quotient_work[31 - ((pipe_index * DIV_BITS_PER_STAGE) + div_bit_index)] = 1'b1;
              div_remainder_work = div_remainder_sub;
            end
          end

          div_remainder_q[pipe_index + 1] <= div_remainder_work;
          div_quotient_q[pipe_index + 1] <= div_quotient_work;

          if (pipe_index == (DIV_STAGES - 1)) begin
            if (div_by_zero_q[pipe_index]) begin
              div_result_next = is_rem_q[pipe_index] ? rsp_q[pipe_index].rs1_rdata : 32'hffff_ffff;
            end else if (div_overflow_q[pipe_index]) begin
              div_result_next = is_rem_q[pipe_index] ? 32'h0000_0000 : 32'h8000_0000;
            end else if (is_rem_q[pipe_index]) begin
              div_result_next = div_rem_negative_q[pipe_index] ?
                                (~div_remainder_work[31:0] + 32'd1) :
                                div_remainder_work[31:0];
            end else begin
              div_result_next = div_quot_negative_q[pipe_index] ?
                                (~div_quotient_work + 32'd1) :
                                div_quotient_work;
            end
            rsp_q[pipe_index + 1].rd_wdata <= div_result_next;
          end
        end
      end
    end
  end
  end
endmodule
