`timescale 1ns/1ps

module multi_thread_dma #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int THREAD_COUNT = 4,
  parameter int MAX_OUTSTANDING_READS = 4,
  parameter int MAX_OUTSTANDING_WRITES = 4,
  parameter int MAX_TRANSFER_WORDS = 4096,
  parameter int ID_WIDTH = (MAX_OUTSTANDING_READS + MAX_OUTSTANDING_WRITES <= 1) ? 1 :
                           $clog2(MAX_OUTSTANDING_READS + MAX_OUTSTANDING_WRITES),
  parameter int THREAD_ID_WIDTH = (THREAD_COUNT <= 1) ? 1 : $clog2(THREAD_COUNT)
) (
  input  logic                         clk,
  input  logic                         rst_n,

  input  logic                         cfg_valid,
  input  logic                         cfg_write,
  input  logic [7:0]                   cfg_addr,
  input  logic [31:0]                  cfg_wdata,
  output logic                         cfg_ready,
  output logic                         cfg_rvalid,
  output logic [31:0]                  cfg_rdata,

  output logic                         rd_req_valid,
  input  logic                         rd_req_ready,
  output logic [ID_WIDTH-1:0]          rd_req_id,
  output logic [ADDR_WIDTH-1:0]        rd_req_addr,
  input  logic                         rd_rsp_valid,
  output logic                         rd_rsp_ready,
  input  logic [ID_WIDTH-1:0]          rd_rsp_id,
  input  logic [DATA_WIDTH-1:0]        rd_rsp_data,

  output logic                         wr_req_valid,
  input  logic                         wr_req_ready,
  output logic [ID_WIDTH-1:0]          wr_req_id,
  output logic [ADDR_WIDTH-1:0]        wr_req_addr,
  output logic [DATA_WIDTH-1:0]        wr_req_data,
  input  logic                         wr_rsp_valid,
  output logic                         wr_rsp_ready,
  input  logic [ID_WIDTH-1:0]          wr_rsp_id,

  output logic [THREAD_COUNT-1:0]      irq_done,
  output logic [THREAD_COUNT-1:0]      irq_error
);
  localparam logic [4:0] REG_SRC_ADDR   = 5'h00;
  localparam logic [4:0] REG_DST_ADDR   = 5'h04;
  localparam logic [4:0] REG_LEN_WORDS  = 5'h08;
  localparam logic [4:0] REG_CTRL       = 5'h0c;
  localparam logic [4:0] REG_STATUS     = 5'h10;
  localparam logic [4:0] REG_WORDS_DONE = 5'h14;

  localparam int BYTE_STRIDE = DATA_WIDTH / 8;
  localparam int BYTE_SHIFT = $clog2(BYTE_STRIDE);
  localparam int SLOT_COUNT = MAX_OUTSTANDING_READS + MAX_OUTSTANDING_WRITES;
  localparam int COUNT_WIDTH = (SLOT_COUNT <= 1) ? 1 : $clog2(SLOT_COUNT + 1);

  logic [ADDR_WIDTH-1:0] src_addr_q [THREAD_COUNT];
  logic [ADDR_WIDTH-1:0] src_addr_d [THREAD_COUNT];
  logic [ADDR_WIDTH-1:0] dst_addr_q [THREAD_COUNT];
  logic [ADDR_WIDTH-1:0] dst_addr_d [THREAD_COUNT];
  logic [31:0]           len_words_q [THREAD_COUNT];
  logic [31:0]           len_words_d [THREAD_COUNT];
  logic [31:0]           next_read_word_q [THREAD_COUNT];
  logic [31:0]           next_read_word_d [THREAD_COUNT];
  logic [31:0]           words_done_q [THREAD_COUNT];
  logic [31:0]           words_done_d [THREAD_COUNT];
  logic [COUNT_WIDTH-1:0] thread_reads_outstanding_q [THREAD_COUNT];
  logic [COUNT_WIDTH-1:0] thread_reads_outstanding_d [THREAD_COUNT];
  logic [COUNT_WIDTH-1:0] thread_writes_outstanding_q [THREAD_COUNT];
  logic [COUNT_WIDTH-1:0] thread_writes_outstanding_d [THREAD_COUNT];
  logic [THREAD_COUNT-1:0] busy_q, busy_d;
  logic [THREAD_COUNT-1:0] irq_en_q, irq_en_d;
  logic [THREAD_COUNT-1:0] done_q, done_d;
  logic [THREAD_COUNT-1:0] error_q, error_d;

  logic [COUNT_WIDTH-1:0] reads_outstanding_q, reads_outstanding_d;
  logic [COUNT_WIDTH-1:0] writes_outstanding_q, writes_outstanding_d;
  logic [THREAD_ID_WIDTH-1:0] rd_issue_thread_q, rd_issue_thread_d;

  logic cfg_fire;
  logic cfg_thread_valid;
  logic cfg_reg_valid;
  logic cfg_addr_valid;
  logic start_pulse;
  logic [2:0] cfg_thread_index;
  logic [4:0] cfg_reg_offset;
  logic [THREAD_ID_WIDTH-1:0] cfg_thread_id;
  logic [THREAD_ID_WIDTH-1:0] cfg_safe_thread_id;
  logic [THREAD_ID_WIDTH-1:0] cfg_error_thread_id;

  logic issue_valid;
  logic [THREAD_ID_WIDTH-1:0] issue_thread_id;
  logic rd_req_fire;
  logic rob_rd_rsp_fire;
  logic [THREAD_ID_WIDTH-1:0] rob_rd_rsp_thread_id;
  logic rob_wr_req_valid;
  logic rob_wr_req_fire;
  logic [THREAD_ID_WIDTH-1:0] rob_wr_req_thread_id;
  logic rob_wr_rsp_fire;
  logic [THREAD_ID_WIDTH-1:0] rob_wr_rsp_thread_id;
  logic id_alloc_valid;
  logic [ID_WIDTH-1:0] id_alloc_id;

  logic [ADDR_WIDTH-1:0] issue_read_offset;
  logic [ADDR_WIDTH-1:0] issue_read_src_addr;
  logic [ADDR_WIDTH-1:0] issue_read_dst_addr;
  logic [63:0] start_transfer_byte_count;
  logic [63:0] start_src_range_start;
  logic [63:0] start_src_range_end;
  logic [63:0] start_dst_range_start;
  logic [63:0] start_dst_range_end;
  logic start_ranges_overlap;

  function automatic logic [THREAD_ID_WIDTH-1:0] next_thread_id(
    input logic [THREAD_ID_WIDTH-1:0] thread_id
  );
    if (thread_id == THREAD_ID_WIDTH'(THREAD_COUNT - 1)) begin
      next_thread_id = '0;
    end else begin
      next_thread_id = thread_id + THREAD_ID_WIDTH'(1);
    end
  endfunction

  assign cfg_ready = 1'b1;
  assign cfg_fire = cfg_valid && cfg_ready;
  assign cfg_thread_index = cfg_addr[7:5];
  assign cfg_reg_offset = cfg_addr[4:0];
  assign cfg_thread_id = cfg_addr[5 +: THREAD_ID_WIDTH];
  assign cfg_thread_valid = int'(cfg_thread_index) < THREAD_COUNT;
  assign cfg_safe_thread_id = cfg_thread_valid ? cfg_thread_id : '0;
  assign cfg_reg_valid = (cfg_reg_offset == REG_SRC_ADDR) ||
                         (cfg_reg_offset == REG_DST_ADDR) ||
                         (cfg_reg_offset == REG_LEN_WORDS) ||
                         (cfg_reg_offset == REG_CTRL) ||
                         (cfg_reg_offset == REG_STATUS) ||
                         (cfg_reg_offset == REG_WORDS_DONE);
  assign cfg_addr_valid = cfg_thread_valid && cfg_reg_valid;
  assign cfg_error_thread_id = cfg_safe_thread_id;

  assign start_pulse = cfg_fire && cfg_write && cfg_thread_valid &&
                       (cfg_reg_offset == REG_CTRL) && cfg_wdata[0];
  assign start_transfer_byte_count = 64'(len_words_q[cfg_safe_thread_id]) << BYTE_SHIFT;
  assign start_src_range_start = 64'(src_addr_q[cfg_safe_thread_id]);
  assign start_src_range_end = start_src_range_start + start_transfer_byte_count;
  assign start_dst_range_start = 64'(dst_addr_q[cfg_safe_thread_id]);
  assign start_dst_range_end = start_dst_range_start + start_transfer_byte_count;
  assign start_ranges_overlap = (len_words_q[cfg_safe_thread_id] != 32'h0) &&
                                (start_src_range_start < start_dst_range_end) &&
                                (start_dst_range_start < start_src_range_end);

  assign irq_done = irq_en_q & done_q;
  assign irq_error = irq_en_q & error_q;

  always_comb begin
    issue_valid = 1'b0;
    issue_thread_id = '0;

    for (int offset = 0; offset < THREAD_COUNT; offset++) begin
      int candidate;
      candidate = int'(rd_issue_thread_q) + offset;
      if (candidate >= THREAD_COUNT) begin
        candidate = candidate - THREAD_COUNT;
      end

      if (!issue_valid &&
          busy_q[candidate] &&
          (next_read_word_q[candidate] < len_words_q[candidate])) begin
        issue_valid = 1'b1;
        issue_thread_id = THREAD_ID_WIDTH'(candidate);
      end
    end
  end

  assign issue_read_offset = ADDR_WIDTH'(next_read_word_q[issue_thread_id]) << BYTE_SHIFT;
  assign issue_read_src_addr = src_addr_q[issue_thread_id] + issue_read_offset;
  assign issue_read_dst_addr = dst_addr_q[issue_thread_id] + issue_read_offset;

  assign rd_req_valid = issue_valid &&
                        (reads_outstanding_q < COUNT_WIDTH'(MAX_OUTSTANDING_READS)) &&
                        id_alloc_valid;
  assign rd_req_id = id_alloc_id;
  assign rd_req_addr = issue_read_src_addr;
  assign rd_req_fire = rd_req_valid && rd_req_ready;

  assign wr_req_valid = rob_wr_req_valid &&
                        (writes_outstanding_q < COUNT_WIDTH'(MAX_OUTSTANDING_WRITES));

  multi_thread_dma_id_pool #(
    .SLOT_COUNT(SLOT_COUNT),
    .ID_WIDTH(ID_WIDTH)
  ) id_pool (
    .clk(clk),
    .rst_n(rst_n),
    .clear(1'b0),
    .alloc_valid(id_alloc_valid),
    .alloc_id(id_alloc_id),
    .alloc_fire(rd_req_fire),
    .free_valid(rob_wr_rsp_fire),
    .free_id(wr_rsp_id)
  );

  multi_thread_dma_reorder_buffer #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .THREAD_COUNT(THREAD_COUNT),
    .SLOT_COUNT(SLOT_COUNT),
    .READ_SLOT_LIMIT(MAX_OUTSTANDING_READS),
    .WRITE_SLOT_LIMIT(MAX_OUTSTANDING_WRITES),
    .ID_WIDTH(ID_WIDTH),
    .THREAD_ID_WIDTH(THREAD_ID_WIDTH)
  ) reorder_buffer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(1'b0),
    .read_alloc_fire(rd_req_fire),
    .read_alloc_id(rd_req_id),
    .read_alloc_thread_id(issue_thread_id),
    .read_alloc_dst_addr(issue_read_dst_addr),
    .rd_rsp_valid(rd_rsp_valid),
    .rd_rsp_ready(rd_rsp_ready),
    .rd_rsp_id(rd_rsp_id),
    .rd_rsp_data(rd_rsp_data),
    .rd_rsp_fire(rob_rd_rsp_fire),
    .rd_rsp_thread_id(rob_rd_rsp_thread_id),
    .wr_req_valid(rob_wr_req_valid),
    .wr_req_ready(wr_req_ready && (writes_outstanding_q < COUNT_WIDTH'(MAX_OUTSTANDING_WRITES))),
    .wr_req_id(wr_req_id),
    .wr_req_thread_id(rob_wr_req_thread_id),
    .wr_req_addr(wr_req_addr),
    .wr_req_data(wr_req_data),
    .wr_req_fire(rob_wr_req_fire),
    .wr_rsp_valid(wr_rsp_valid),
    .wr_rsp_ready(wr_rsp_ready),
    .wr_rsp_id(wr_rsp_id),
    .wr_rsp_fire(rob_wr_rsp_fire),
    .wr_rsp_thread_id(rob_wr_rsp_thread_id)
  );

  always_comb begin
    cfg_rvalid = cfg_fire && !cfg_write;
    cfg_rdata = 32'h0;

    if (cfg_thread_valid) begin
      unique case (cfg_reg_offset)
        REG_SRC_ADDR: begin
          cfg_rdata = {{(32-ADDR_WIDTH){1'b0}}, src_addr_q[cfg_safe_thread_id]};
        end
        REG_DST_ADDR: begin
          cfg_rdata = {{(32-ADDR_WIDTH){1'b0}}, dst_addr_q[cfg_safe_thread_id]};
        end
        REG_LEN_WORDS: begin
          cfg_rdata = len_words_q[cfg_safe_thread_id];
        end
        REG_CTRL: begin
          cfg_rdata = {30'h0, irq_en_q[cfg_safe_thread_id], 1'b0};
        end
        REG_STATUS: begin
          cfg_rdata = {
            29'h0,
            error_q[cfg_safe_thread_id],
            done_q[cfg_safe_thread_id],
            busy_q[cfg_safe_thread_id]
          };
        end
        REG_WORDS_DONE: begin
          cfg_rdata = words_done_q[cfg_safe_thread_id];
        end
        default: begin
          cfg_rdata = 32'h0;
        end
      endcase
    end
  end

  always_comb begin
    for (int thread = 0; thread < THREAD_COUNT; thread++) begin
      src_addr_d[thread] = src_addr_q[thread];
      dst_addr_d[thread] = dst_addr_q[thread];
      len_words_d[thread] = len_words_q[thread];
      next_read_word_d[thread] = next_read_word_q[thread];
      words_done_d[thread] = words_done_q[thread];
      thread_reads_outstanding_d[thread] = thread_reads_outstanding_q[thread];
      thread_writes_outstanding_d[thread] = thread_writes_outstanding_q[thread];
    end

    busy_d = busy_q;
    irq_en_d = irq_en_q;
    done_d = done_q;
    error_d = error_q;
    reads_outstanding_d = reads_outstanding_q;
    writes_outstanding_d = writes_outstanding_q;
    rd_issue_thread_d = rd_issue_thread_q;

    if (cfg_fire && !cfg_addr_valid) begin
      error_d[cfg_error_thread_id] = 1'b1;
    end

    if (cfg_fire && cfg_write && cfg_thread_valid) begin
      unique case (cfg_reg_offset)
        REG_SRC_ADDR: begin
          if (!busy_q[cfg_safe_thread_id]) begin
            src_addr_d[cfg_safe_thread_id] = cfg_wdata[ADDR_WIDTH-1:0];
          end else begin
            error_d[cfg_safe_thread_id] = 1'b1;
          end
        end
        REG_DST_ADDR: begin
          if (!busy_q[cfg_safe_thread_id]) begin
            dst_addr_d[cfg_safe_thread_id] = cfg_wdata[ADDR_WIDTH-1:0];
          end else begin
            error_d[cfg_safe_thread_id] = 1'b1;
          end
        end
        REG_LEN_WORDS: begin
          if (!busy_q[cfg_safe_thread_id]) begin
            len_words_d[cfg_safe_thread_id] = cfg_wdata;
          end else begin
            error_d[cfg_safe_thread_id] = 1'b1;
          end
        end
        REG_CTRL: begin
          irq_en_d[cfg_safe_thread_id] = cfg_wdata[1];
        end
        REG_STATUS: begin
          if (cfg_wdata[1]) begin
            done_d[cfg_safe_thread_id] = 1'b0;
          end
          if (cfg_wdata[2]) begin
            error_d[cfg_safe_thread_id] = 1'b0;
          end
        end
        REG_WORDS_DONE: begin
          error_d[cfg_safe_thread_id] = 1'b1;
        end
        default: begin
          error_d[cfg_safe_thread_id] = 1'b1;
        end
      endcase
    end

    if (start_pulse) begin
      if (busy_q[cfg_safe_thread_id]) begin
        error_d[cfg_safe_thread_id] = 1'b1;
      end else begin
        done_d[cfg_safe_thread_id] = 1'b0;
        next_read_word_d[cfg_safe_thread_id] = 32'h0;
        words_done_d[cfg_safe_thread_id] = 32'h0;
        thread_reads_outstanding_d[cfg_safe_thread_id] = '0;
        thread_writes_outstanding_d[cfg_safe_thread_id] = '0;
        if (len_words_q[cfg_safe_thread_id] > 32'(MAX_TRANSFER_WORDS)) begin
          error_d[cfg_safe_thread_id] = 1'b1;
        end else if (start_ranges_overlap) begin
          error_d[cfg_safe_thread_id] = 1'b1;
        end else if (len_words_q[cfg_safe_thread_id] == 32'h0) begin
          done_d[cfg_safe_thread_id] = 1'b1;
        end else begin
          busy_d[cfg_safe_thread_id] = 1'b1;
        end
      end
    end

    if (rd_req_fire) begin
      next_read_word_d[issue_thread_id] = next_read_word_q[issue_thread_id] + 32'h1;
      thread_reads_outstanding_d[issue_thread_id] =
        thread_reads_outstanding_d[issue_thread_id] + COUNT_WIDTH'(1);
      reads_outstanding_d = reads_outstanding_d + COUNT_WIDTH'(1);
      rd_issue_thread_d = next_thread_id(issue_thread_id);
    end

    if (rob_rd_rsp_fire) begin
      thread_reads_outstanding_d[rob_rd_rsp_thread_id] =
        thread_reads_outstanding_d[rob_rd_rsp_thread_id] - COUNT_WIDTH'(1);
      reads_outstanding_d = reads_outstanding_d - COUNT_WIDTH'(1);
    end

    if (rob_wr_req_fire) begin
      thread_writes_outstanding_d[rob_wr_req_thread_id] =
        thread_writes_outstanding_d[rob_wr_req_thread_id] + COUNT_WIDTH'(1);
      writes_outstanding_d = writes_outstanding_d + COUNT_WIDTH'(1);
    end

    if (rob_wr_rsp_fire) begin
      thread_writes_outstanding_d[rob_wr_rsp_thread_id] =
        thread_writes_outstanding_d[rob_wr_rsp_thread_id] - COUNT_WIDTH'(1);
      writes_outstanding_d = writes_outstanding_d - COUNT_WIDTH'(1);
      words_done_d[rob_wr_rsp_thread_id] = words_done_q[rob_wr_rsp_thread_id] + 32'h1;

      if ((words_done_q[rob_wr_rsp_thread_id] + 32'h1) ==
          len_words_q[rob_wr_rsp_thread_id]) begin
        busy_d[rob_wr_rsp_thread_id] = 1'b0;
        done_d[rob_wr_rsp_thread_id] = 1'b1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int thread = 0; thread < THREAD_COUNT; thread++) begin
        src_addr_q[thread] <= '0;
        dst_addr_q[thread] <= '0;
        len_words_q[thread] <= 32'h0;
        next_read_word_q[thread] <= 32'h0;
        words_done_q[thread] <= 32'h0;
        thread_reads_outstanding_q[thread] <= '0;
        thread_writes_outstanding_q[thread] <= '0;
      end
      busy_q <= '0;
      irq_en_q <= '0;
      done_q <= '0;
      error_q <= '0;
      reads_outstanding_q <= '0;
      writes_outstanding_q <= '0;
      rd_issue_thread_q <= '0;
    end else begin
      for (int thread = 0; thread < THREAD_COUNT; thread++) begin
        src_addr_q[thread] <= src_addr_d[thread];
        dst_addr_q[thread] <= dst_addr_d[thread];
        len_words_q[thread] <= len_words_d[thread];
        next_read_word_q[thread] <= next_read_word_d[thread];
        words_done_q[thread] <= words_done_d[thread];
        thread_reads_outstanding_q[thread] <= thread_reads_outstanding_d[thread];
        thread_writes_outstanding_q[thread] <= thread_writes_outstanding_d[thread];
      end
      busy_q <= busy_d;
      irq_en_q <= irq_en_d;
      done_q <= done_d;
      error_q <= error_d;
      reads_outstanding_q <= reads_outstanding_d;
      writes_outstanding_q <= writes_outstanding_d;
      rd_issue_thread_q <= rd_issue_thread_d;
    end
  end

`ifndef SYNTHESIS
  default clocking dma_cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  cover_multiple_threads_busy:
    cover property ($countones(busy_q) > 1);

  cover_read_slots_full:
    cover property (|busy_q && (reads_outstanding_q == COUNT_WIDTH'(MAX_OUTSTANDING_READS)));

  cover_write_slots_full:
    cover property (|busy_q && (writes_outstanding_q == COUNT_WIDTH'(MAX_OUTSTANDING_WRITES)));

  cover_all_ids_allocated:
    cover property (|busy_q && !id_alloc_valid);

  assert_read_fire_has_allocated_id:
    assert property (rd_req_fire |-> id_alloc_valid)
    else $error("multi_thread_dma read request fired without an allocated ID");

  assert_global_read_count_matches_threads:
    assert property (
      1'b1 |->
      reads_outstanding_q ==
        COUNT_WIDTH'($countones(reorder_buffer.slot_read_outstanding_q))
    )
    else $error("multi_thread_dma global read count does not match ROB state");

  assert_global_write_count_matches_threads:
    assert property (
      1'b1 |->
      writes_outstanding_q ==
        COUNT_WIDTH'($countones(reorder_buffer.slot_write_outstanding_q))
    )
    else $error("multi_thread_dma global write count does not match ROB state");
`endif
endmodule
