`timescale 1ns/1ps

module dma #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int MAX_OUTSTANDING_READS = 4,
  parameter int MAX_OUTSTANDING_WRITES = 4,
  parameter int MAX_TRANSFER_WORDS = 4096,
  parameter int ID_WIDTH = (MAX_OUTSTANDING_READS + MAX_OUTSTANDING_WRITES <= 1) ? 1 :
                           $clog2(MAX_OUTSTANDING_READS + MAX_OUTSTANDING_WRITES)
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  cfg_valid,
  input  logic                  cfg_write,
  input  logic [7:0]            cfg_addr,
  input  logic [31:0]           cfg_wdata,
  output logic                  cfg_ready,
  output logic                  cfg_rvalid,
  output logic [31:0]           cfg_rdata,

  output logic                  rd_req_valid,
  input  logic                  rd_req_ready,
  output logic [ID_WIDTH-1:0]   rd_req_id,
  output logic [ADDR_WIDTH-1:0] rd_req_addr,
  input  logic                  rd_rsp_valid,
  output logic                  rd_rsp_ready,
  input  logic [ID_WIDTH-1:0]   rd_rsp_id,
  input  logic [DATA_WIDTH-1:0] rd_rsp_data,

  output logic                  wr_req_valid,
  input  logic                  wr_req_ready,
  output logic [ID_WIDTH-1:0]   wr_req_id,
  output logic [ADDR_WIDTH-1:0] wr_req_addr,
  output logic [DATA_WIDTH-1:0] wr_req_data,
  input  logic                  wr_rsp_valid,
  output logic                  wr_rsp_ready,
  input  logic [ID_WIDTH-1:0]   wr_rsp_id,

  output logic                  irq_done,
  output logic                  irq_error
);
  localparam logic [7:0] REG_SRC_ADDR  = 8'h00;
  localparam logic [7:0] REG_DST_ADDR  = 8'h04;
  localparam logic [7:0] REG_LEN_WORDS = 8'h08;
  localparam logic [7:0] REG_CTRL      = 8'h0c;
  localparam logic [7:0] REG_STATUS    = 8'h10;

  localparam int BYTE_STRIDE = DATA_WIDTH / 8;
  localparam int BYTE_SHIFT = $clog2(BYTE_STRIDE);
  localparam int SLOT_COUNT = MAX_OUTSTANDING_READS + MAX_OUTSTANDING_WRITES;
  localparam int COUNT_WIDTH = (SLOT_COUNT <= 1) ? 1 : $clog2(SLOT_COUNT + 1);

  logic [ADDR_WIDTH-1:0] src_addr_q, src_addr_d;
  logic [ADDR_WIDTH-1:0] dst_addr_q, dst_addr_d;
  logic [31:0]           len_words_q, len_words_d;
  logic [31:0]           next_read_word_q, next_read_word_d;
  logic [31:0]           words_done_q, words_done_d;
  logic [COUNT_WIDTH-1:0] reads_outstanding_q, reads_outstanding_d;
  logic [COUNT_WIDTH-1:0] writes_outstanding_q, writes_outstanding_d;
  logic                  busy_q, busy_d;
  logic                  irq_en_q, irq_en_d;
  logic                  done_q, done_d;
  logic                  error_q, error_d;

  logic                  start_pulse;
  logic                  start_accepted;
  logic                  cfg_fire;
  logic                  cfg_addr_valid;
  logic                  rd_req_fire;
  logic                  rob_rd_rsp_fire;
  logic                  rob_wr_req_valid;
  logic                  rob_wr_req_fire;
  logic                  rob_wr_rsp_fire;
  logic                  id_alloc_valid;
  logic [ID_WIDTH-1:0]   id_alloc_id;

  logic [ADDR_WIDTH-1:0] next_read_offset;
  logic [ADDR_WIDTH-1:0] next_read_src_addr;
  logic [ADDR_WIDTH-1:0] next_read_dst_addr;
  logic [63:0]           transfer_byte_count;
  logic [63:0]           src_range_start;
  logic [63:0]           src_range_end;
  logic [63:0]           dst_range_start;
  logic [63:0]           dst_range_end;
  logic                  ranges_overlap;

  assign cfg_ready = 1'b1;
  assign cfg_fire = cfg_valid && cfg_ready;
  assign start_pulse = cfg_fire && cfg_write && (cfg_addr == REG_CTRL) && cfg_wdata[0];
  assign start_accepted = start_pulse && !busy_q;
  assign cfg_addr_valid = (cfg_addr == REG_SRC_ADDR) ||
                          (cfg_addr == REG_DST_ADDR) ||
                          (cfg_addr == REG_LEN_WORDS) ||
                          (cfg_addr == REG_CTRL) ||
                          (cfg_addr == REG_STATUS);

  assign irq_done = irq_en_q && done_q;
  assign irq_error = irq_en_q && error_q;

  assign next_read_offset = ADDR_WIDTH'(next_read_word_q) << BYTE_SHIFT;
  assign next_read_src_addr = src_addr_q + next_read_offset;
  assign next_read_dst_addr = dst_addr_q + next_read_offset;
  assign transfer_byte_count = 64'(len_words_q) << BYTE_SHIFT;
  assign src_range_start = 64'(src_addr_q);
  assign src_range_end = src_range_start + transfer_byte_count;
  assign dst_range_start = 64'(dst_addr_q);
  assign dst_range_end = dst_range_start + transfer_byte_count;
  assign ranges_overlap = (len_words_q != 32'h0) &&
                          (src_range_start < dst_range_end) &&
                          (dst_range_start < src_range_end);

  assign rd_req_valid = busy_q &&
                        (next_read_word_q < len_words_q) &&
                        (reads_outstanding_q < COUNT_WIDTH'(MAX_OUTSTANDING_READS)) &&
                        id_alloc_valid;
  assign rd_req_id = id_alloc_id;
  assign rd_req_addr = next_read_src_addr;
  assign rd_req_fire = rd_req_valid && rd_req_ready;

  assign wr_req_valid = rob_wr_req_valid &&
                        (writes_outstanding_q < COUNT_WIDTH'(MAX_OUTSTANDING_WRITES));

  dma_id_pool #(
    .SLOT_COUNT(SLOT_COUNT),
    .ID_WIDTH(ID_WIDTH)
  ) id_pool (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start_accepted),
    .alloc_valid(id_alloc_valid),
    .alloc_id(id_alloc_id),
    .alloc_fire(rd_req_fire),
    .free_valid(rob_wr_rsp_fire),
    .free_id(wr_rsp_id)
  );

  dma_reorder_buffer #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .SLOT_COUNT(SLOT_COUNT),
    .READ_SLOT_LIMIT(MAX_OUTSTANDING_READS),
    .WRITE_SLOT_LIMIT(MAX_OUTSTANDING_WRITES),
    .ID_WIDTH(ID_WIDTH)
  ) reorder_buffer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start_accepted),
    .read_alloc_fire(rd_req_fire),
    .read_alloc_id(rd_req_id),
    .read_alloc_dst_addr(next_read_dst_addr),
    .rd_rsp_valid(rd_rsp_valid),
    .rd_rsp_ready(rd_rsp_ready),
    .rd_rsp_id(rd_rsp_id),
    .rd_rsp_data(rd_rsp_data),
    .rd_rsp_fire(rob_rd_rsp_fire),
    .wr_req_valid(rob_wr_req_valid),
    .wr_req_ready(wr_req_ready && (writes_outstanding_q < COUNT_WIDTH'(MAX_OUTSTANDING_WRITES))),
    .wr_req_id(wr_req_id),
    .wr_req_addr(wr_req_addr),
    .wr_req_data(wr_req_data),
    .wr_req_fire(rob_wr_req_fire),
    .wr_rsp_valid(wr_rsp_valid),
    .wr_rsp_ready(wr_rsp_ready),
    .wr_rsp_id(wr_rsp_id),
    .wr_rsp_fire(rob_wr_rsp_fire)
  );

  always_comb begin
    cfg_rvalid = cfg_fire && !cfg_write;
    cfg_rdata = 32'h0;

    unique case (cfg_addr)
      REG_SRC_ADDR: begin
        cfg_rdata = {{(32-ADDR_WIDTH){1'b0}}, src_addr_q};
      end
      REG_DST_ADDR: begin
        cfg_rdata = {{(32-ADDR_WIDTH){1'b0}}, dst_addr_q};
      end
      REG_LEN_WORDS: begin
        cfg_rdata = len_words_q;
      end
      REG_CTRL: begin
        cfg_rdata = {30'h0, irq_en_q, 1'b0};
      end
      REG_STATUS: begin
        cfg_rdata = {29'h0, error_q, done_q, busy_q};
      end
      default: begin
        cfg_rdata = 32'h0;
      end
    endcase
  end

  always_comb begin
    src_addr_d = src_addr_q;
    dst_addr_d = dst_addr_q;
    len_words_d = len_words_q;
    next_read_word_d = next_read_word_q;
    words_done_d = words_done_q;
    reads_outstanding_d = reads_outstanding_q;
    writes_outstanding_d = writes_outstanding_q;
    busy_d = busy_q;
    irq_en_d = irq_en_q;
    done_d = done_q;
    error_d = error_q;

    if (cfg_fire && !cfg_addr_valid) begin
      error_d = 1'b1;
    end

    if (cfg_fire && cfg_write) begin
      unique case (cfg_addr)
        REG_SRC_ADDR: begin
          if (!busy_q) begin
            src_addr_d = cfg_wdata[ADDR_WIDTH-1:0];
          end else begin
            error_d = 1'b1;
          end
        end
        REG_DST_ADDR: begin
          if (!busy_q) begin
            dst_addr_d = cfg_wdata[ADDR_WIDTH-1:0];
          end else begin
            error_d = 1'b1;
          end
        end
        REG_LEN_WORDS: begin
          if (!busy_q) begin
            len_words_d = cfg_wdata;
          end else begin
            error_d = 1'b1;
          end
        end
        REG_CTRL: begin
          irq_en_d = cfg_wdata[1];
        end
        REG_STATUS: begin
          if (cfg_wdata[1]) begin
            done_d = 1'b0;
          end
          if (cfg_wdata[2]) begin
            error_d = 1'b0;
          end
        end
        default: begin
          error_d = 1'b1;
        end
      endcase
    end

    if (start_pulse) begin
      if (busy_q) begin
        error_d = 1'b1;
      end else begin
        done_d = 1'b0;
        next_read_word_d = 32'h0;
        words_done_d = 32'h0;
        reads_outstanding_d = '0;
        writes_outstanding_d = '0;
        if (len_words_q > 32'(MAX_TRANSFER_WORDS)) begin
          error_d = 1'b1;
        end else if (ranges_overlap) begin
          error_d = 1'b1;
        end else if (len_words_q == 32'h0) begin
          done_d = 1'b1;
        end else begin
          busy_d = 1'b1;
        end
      end
    end

    if (busy_q) begin
      if (rd_req_fire) begin
        next_read_word_d = next_read_word_q + 32'h1;
        reads_outstanding_d = reads_outstanding_d + COUNT_WIDTH'(1);
      end

      if (rob_rd_rsp_fire) begin
        reads_outstanding_d = reads_outstanding_d - COUNT_WIDTH'(1);
      end

      if (rob_wr_req_fire) begin
        writes_outstanding_d = writes_outstanding_d + COUNT_WIDTH'(1);
      end

      if (rob_wr_rsp_fire) begin
        writes_outstanding_d = writes_outstanding_d - COUNT_WIDTH'(1);
        words_done_d = words_done_q + 32'h1;

        if ((words_done_q + 32'h1) == len_words_q) begin
          busy_d = 1'b0;
          done_d = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      src_addr_q <= '0;
      dst_addr_q <= '0;
      len_words_q <= 32'h0;
      next_read_word_q <= 32'h0;
      words_done_q <= 32'h0;
      reads_outstanding_q <= '0;
      writes_outstanding_q <= '0;
      busy_q <= 1'b0;
      irq_en_q <= 1'b0;
      done_q <= 1'b0;
      error_q <= 1'b0;
    end else begin
      src_addr_q <= src_addr_d;
      dst_addr_q <= dst_addr_d;
      len_words_q <= len_words_d;
      next_read_word_q <= next_read_word_d;
      words_done_q <= words_done_d;
      reads_outstanding_q <= reads_outstanding_d;
      writes_outstanding_q <= writes_outstanding_d;
      busy_q <= busy_d;
      irq_en_q <= irq_en_d;
      done_q <= done_d;
      error_q <= error_d;
    end
  end

`ifndef SYNTHESIS
  default clocking dma_cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  cover_read_slots_full:
    cover property (busy_q && (reads_outstanding_q == COUNT_WIDTH'(MAX_OUTSTANDING_READS)));

  cover_write_slots_full:
    cover property (busy_q && (writes_outstanding_q == COUNT_WIDTH'(MAX_OUTSTANDING_WRITES)));

  cover_all_ids_allocated:
    cover property (busy_q && !id_alloc_valid);

  cover_read_issue_blocked_by_read_limit:
    cover property (
      busy_q &&
      (next_read_word_q < len_words_q) &&
      (reads_outstanding_q == COUNT_WIDTH'(MAX_OUTSTANDING_READS))
    );

  cover_write_issue_blocked_by_write_limit:
    cover property (rob_wr_req_valid && (writes_outstanding_q == COUNT_WIDTH'(MAX_OUTSTANDING_WRITES)));

  assert_read_fire_has_allocated_id:
    assert property (rd_req_fire |-> id_alloc_valid)
    else $error("DMA read request fired without an allocated ID");
`endif
endmodule
