`timescale 1ns/1ps

module riscv32im_prefetch #(
  parameter int unsigned DEPTH = 4,
  parameter logic [31:0] RESET_VECTOR = 32'h8000_0000
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        fetch_enable_i,
  input  logic        consume_i,
  output logic        consume_valid_o,
  output logic [31:0] consume_insn_o,
  output logic [31:0] consume_pc_o,
  output logic        consume_err_o,

  input  logic        redirect_valid_i,
  input  logic [31:0] redirect_pc_i,

  output logic        imem_req_valid,
  input  logic        imem_req_ready,
  output logic [31:0] imem_req_addr,
  input  logic        imem_rsp_valid,
  input  logic [31:0] imem_rsp_rdata,
  input  logic        imem_rsp_err
);
  localparam int unsigned PTR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
  localparam logic [PTR_W-1:0] PTR_LAST = PTR_W'(DEPTH - 1);
  localparam logic [PTR_W:0]   DEPTH_COUNT = (PTR_W + 1)'(DEPTH);

  logic [31:0] next_req_pc_q;

  logic [31:0] req_pc_q [DEPTH];
  logic [PTR_W-1:0] req_head_q;
  logic [PTR_W-1:0] req_tail_q;
  logic [PTR_W:0]   req_count_q;

  logic [31:0] rsp_insn_q [DEPTH];
  logic [31:0] rsp_pc_q [DEPTH];
  logic        rsp_err_q [DEPTH];
  logic [PTR_W-1:0] rsp_head_q;
  logic [PTR_W-1:0] rsp_tail_q;
  logic [PTR_W:0]   rsp_count_q;

  logic [PTR_W:0] flush_count_q;

  logic [PTR_W:0] total_fetch_q;
  logic [PTR_W:0] effective_total_fetch;
  logic           req_fire;
  logic           consume_fire;

  function automatic logic [PTR_W-1:0] ptr_inc(input logic [PTR_W-1:0] ptr_i);
    begin
      if (ptr_i == PTR_LAST) begin
        ptr_inc = '0;
      end else begin
        ptr_inc = ptr_i + {{(PTR_W-1){1'b0}}, 1'b1};
      end
    end
  endfunction

  assign total_fetch_q = req_count_q + rsp_count_q;
  assign consume_fire = consume_i && consume_valid_o;
  assign effective_total_fetch = total_fetch_q - {{PTR_W{1'b0}}, consume_fire};
  assign consume_valid_o = (rsp_count_q != '0);
  assign consume_insn_o = rsp_insn_q[rsp_head_q];
  assign consume_pc_o = rsp_pc_q[rsp_head_q];
  assign consume_err_o = rsp_err_q[rsp_head_q];

  assign imem_req_valid = fetch_enable_i &&
                          !redirect_valid_i &&
                          (flush_count_q == '0) &&
                          (effective_total_fetch < DEPTH_COUNT);
  assign imem_req_addr = next_req_pc_q;

  assign req_fire = imem_req_valid && imem_req_ready;

  integer reset_index;

  always_ff @(posedge clk or negedge rst_n) begin
    logic [31:0]      next_req_pc_next;
    logic [PTR_W-1:0] req_head_next;
    logic [PTR_W-1:0] req_tail_next;
    logic [PTR_W:0]   req_count_next;
    logic [PTR_W-1:0] rsp_head_next;
    logic [PTR_W-1:0] rsp_tail_next;
    logic [PTR_W:0]   rsp_count_next;
    logic [PTR_W:0]   flush_count_next;

    if (!rst_n) begin
      next_req_pc_q <= RESET_VECTOR;
      req_head_q <= '0;
      req_tail_q <= '0;
      req_count_q <= '0;
      rsp_head_q <= '0;
      rsp_tail_q <= '0;
      rsp_count_q <= '0;
      flush_count_q <= '0;

      for (reset_index = 0; reset_index < DEPTH; reset_index = reset_index + 1) begin
        req_pc_q[reset_index] <= 32'h0000_0000;
        rsp_insn_q[reset_index] <= 32'h0000_0013;
        rsp_pc_q[reset_index] <= 32'h0000_0000;
        rsp_err_q[reset_index] <= 1'b0;
      end
    end else if (redirect_valid_i) begin
      next_req_pc_q <= redirect_pc_i;
      req_head_q <= '0;
      req_tail_q <= '0;
      req_count_q <= '0;
      rsp_head_q <= '0;
      rsp_tail_q <= '0;
      rsp_count_q <= '0;

      if (imem_rsp_valid && (req_count_q != '0)) begin
        flush_count_q <= req_count_q - {{PTR_W{1'b0}}, 1'b1};
      end else begin
        flush_count_q <= req_count_q;
      end
    end else begin
      next_req_pc_next = next_req_pc_q;
      req_head_next = req_head_q;
      req_tail_next = req_tail_q;
      req_count_next = req_count_q;
      rsp_head_next = rsp_head_q;
      rsp_tail_next = rsp_tail_q;
      rsp_count_next = rsp_count_q;
      flush_count_next = flush_count_q;

      if (consume_fire) begin
        rsp_head_next = ptr_inc(rsp_head_q);
        rsp_count_next = rsp_count_next - {{PTR_W{1'b0}}, 1'b1};
      end

      if (imem_rsp_valid) begin
        if (flush_count_q != '0) begin
          flush_count_next = flush_count_q - {{PTR_W{1'b0}}, 1'b1};
        end else if (req_count_q != '0) begin
          req_head_next = ptr_inc(req_head_q);
          req_count_next = req_count_next - {{PTR_W{1'b0}}, 1'b1};

          rsp_insn_q[rsp_tail_q] <= imem_rsp_rdata;
          rsp_pc_q[rsp_tail_q] <= req_pc_q[req_head_q];
          rsp_err_q[rsp_tail_q] <= imem_rsp_err;
          rsp_tail_next = ptr_inc(rsp_tail_q);
          rsp_count_next = rsp_count_next + {{PTR_W{1'b0}}, 1'b1};
        end
      end

      if (req_fire) begin
        req_pc_q[req_tail_q] <= next_req_pc_q;
        req_tail_next = ptr_inc(req_tail_q);
        req_count_next = req_count_next + {{PTR_W{1'b0}}, 1'b1};
        next_req_pc_next = next_req_pc_q + 32'd4;
      end

      next_req_pc_q <= next_req_pc_next;
      req_head_q <= req_head_next;
      req_tail_q <= req_tail_next;
      req_count_q <= req_count_next;
      rsp_head_q <= rsp_head_next;
      rsp_tail_q <= rsp_tail_next;
      rsp_count_q <= rsp_count_next;
      flush_count_q <= flush_count_next;
    end
  end
endmodule
