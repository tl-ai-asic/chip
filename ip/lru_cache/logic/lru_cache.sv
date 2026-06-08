`timescale 1ns/1ps

module lru_cache #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int SET_COUNT = 16,
  parameter int WAY_COUNT = 4,
  parameter int SET_INDEX_WIDTH = (SET_COUNT <= 1) ? 1 : $clog2(SET_COUNT),
  parameter int WAY_INDEX_WIDTH = (WAY_COUNT <= 1) ? 1 : $clog2(WAY_COUNT),
  parameter int DATA_BYTES = DATA_WIDTH / 8,
  parameter int BYTE_OFFSET_WIDTH = (DATA_BYTES <= 1) ? 1 : $clog2(DATA_BYTES),
  parameter int TAG_WIDTH = ADDR_WIDTH - SET_INDEX_WIDTH - BYTE_OFFSET_WIDTH
) (
  input  logic                       clk,
  input  logic                       rst_n,

  input  logic                       cpu_req_valid,
  output logic                       cpu_req_ready,
  input  logic                       cpu_req_write,
  input  logic [ADDR_WIDTH-1:0]      cpu_req_addr,
  input  logic [DATA_WIDTH-1:0]      cpu_req_wdata,
  input  logic [DATA_BYTES-1:0]      cpu_req_wstrb,

  output logic                       cpu_rsp_valid,
  input  logic                       cpu_rsp_ready,
  output logic [DATA_WIDTH-1:0]      cpu_rsp_rdata,
  output logic                       cpu_rsp_hit,
  output logic                       cpu_rsp_error,

  output logic                       mem_req_valid,
  input  logic                       mem_req_ready,
  output logic                       mem_req_write,
  output logic [ADDR_WIDTH-1:0]      mem_req_addr,
  output logic [DATA_WIDTH-1:0]      mem_req_wdata,
  output logic [DATA_BYTES-1:0]      mem_req_wstrb,

  input  logic                       mem_rsp_valid,
  output logic                       mem_rsp_ready,
  input  logic [DATA_WIDTH-1:0]      mem_rsp_rdata,
  input  logic                       mem_rsp_error
);
  typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_READ_REQ,
    STATE_READ_RSP,
    STATE_WRITE_REQ,
    STATE_WRITE_RSP
  } state_e;

  state_e state_q, state_d;

  logic [SET_COUNT-1:0][WAY_COUNT-1:0] valid_q, valid_d;
  logic [TAG_WIDTH-1:0]                tag_q [SET_COUNT][WAY_COUNT];
  logic [TAG_WIDTH-1:0]                tag_d [SET_COUNT][WAY_COUNT];
  logic [DATA_WIDTH-1:0]               data_q [SET_COUNT][WAY_COUNT];
  logic [DATA_WIDTH-1:0]               data_d [SET_COUNT][WAY_COUNT];
  logic [WAY_INDEX_WIDTH-1:0]          lru_order_q [SET_COUNT][WAY_COUNT];
  logic [WAY_INDEX_WIDTH-1:0]          lru_order_d [SET_COUNT][WAY_COUNT];

  logic                                rsp_valid_q, rsp_valid_d;
  logic [DATA_WIDTH-1:0]               rsp_rdata_q, rsp_rdata_d;
  logic                                rsp_hit_q, rsp_hit_d;
  logic                                rsp_error_q, rsp_error_d;

  logic [ADDR_WIDTH-1:0]               pending_addr_q, pending_addr_d;
  logic [DATA_WIDTH-1:0]               pending_wdata_q, pending_wdata_d;
  logic [DATA_BYTES-1:0]               pending_wstrb_q, pending_wstrb_d;
  logic [SET_INDEX_WIDTH-1:0]          pending_set_q, pending_set_d;
  logic [TAG_WIDTH-1:0]                pending_tag_q, pending_tag_d;
  logic [WAY_INDEX_WIDTH-1:0]          pending_way_q, pending_way_d;
  logic                                pending_hit_q, pending_hit_d;

  logic                                req_fire;
  logic                                rsp_fire;
  logic                                mem_req_fire;
  logic                                mem_rsp_fire;

  logic [SET_INDEX_WIDTH-1:0]          req_set;
  logic [TAG_WIDTH-1:0]                req_tag;
  logic [ADDR_WIDTH-1:0]               req_word_addr;

  logic                                hit_valid;
  logic [WAY_INDEX_WIDTH-1:0]          hit_way;
  logic                                invalid_valid;
  logic [WAY_INDEX_WIDTH-1:0]          invalid_way;
  logic [WAY_INDEX_WIDTH-1:0]          victim_way;
  logic [DATA_WIDTH-1:0]               hit_data;
  logic [DATA_WIDTH-1:0]               merged_write_data;

  assign cpu_req_ready = (state_q == STATE_IDLE) && (!rsp_valid_q || cpu_rsp_ready);
  assign cpu_rsp_valid = rsp_valid_q;
  assign cpu_rsp_rdata = rsp_rdata_q;
  assign cpu_rsp_hit = rsp_hit_q;
  assign cpu_rsp_error = rsp_error_q;

  assign rsp_fire = cpu_rsp_valid && cpu_rsp_ready;
  assign req_fire = cpu_req_valid && cpu_req_ready;
  assign mem_req_fire = mem_req_valid && mem_req_ready;
  assign mem_rsp_fire = mem_rsp_valid && mem_rsp_ready;

  assign req_set = cpu_req_addr[BYTE_OFFSET_WIDTH +: SET_INDEX_WIDTH];
  assign req_tag = cpu_req_addr[ADDR_WIDTH-1 -: TAG_WIDTH];
  assign req_word_addr = {{cpu_req_addr[ADDR_WIDTH-1:BYTE_OFFSET_WIDTH]},
                          {BYTE_OFFSET_WIDTH{1'b0}}};

  always_comb begin
    hit_valid = 1'b0;
    hit_way = '0;
    invalid_valid = 1'b0;
    invalid_way = '0;

    for (int way = 0; way < WAY_COUNT; way++) begin
      if (!hit_valid && valid_q[req_set][way] && (tag_q[req_set][way] == req_tag)) begin
        hit_valid = 1'b1;
        hit_way = WAY_INDEX_WIDTH'(way);
      end

      if (!invalid_valid && !valid_q[req_set][way]) begin
        invalid_valid = 1'b1;
        invalid_way = WAY_INDEX_WIDTH'(way);
      end
    end
  end

  assign victim_way = invalid_valid ? invalid_way : lru_order_q[req_set][WAY_COUNT-1];
  assign hit_data = data_q[req_set][hit_way];

  always_comb begin
    merged_write_data = hit_data;
    for (int byte_i = 0; byte_i < DATA_BYTES; byte_i++) begin
      if (cpu_req_wstrb[byte_i]) begin
        merged_write_data[(byte_i * 8) +: 8] =
          cpu_req_wdata[(byte_i * 8) +: 8];
      end
    end
  end

  always_comb begin
    mem_req_valid = 1'b0;
    mem_req_write = 1'b0;
    mem_req_addr = pending_addr_q;
    mem_req_wdata = pending_wdata_q;
    mem_req_wstrb = pending_wstrb_q;
    mem_rsp_ready = 1'b0;

    unique case (state_q)
      STATE_READ_REQ: begin
        mem_req_valid = 1'b1;
        mem_req_write = 1'b0;
      end

      STATE_READ_RSP: begin
        mem_rsp_ready = 1'b1;
      end

      STATE_WRITE_REQ: begin
        mem_req_valid = 1'b1;
        mem_req_write = 1'b1;
      end

      STATE_WRITE_RSP: begin
        mem_rsp_ready = 1'b1;
      end

      default: begin
      end
    endcase
  end

  always_comb begin
    state_d = state_q;
    valid_d = valid_q;
    rsp_valid_d = rsp_valid_q;
    rsp_rdata_d = rsp_rdata_q;
    rsp_hit_d = rsp_hit_q;
    rsp_error_d = rsp_error_q;
    pending_addr_d = pending_addr_q;
    pending_wdata_d = pending_wdata_q;
    pending_wstrb_d = pending_wstrb_q;
    pending_set_d = pending_set_q;
    pending_tag_d = pending_tag_q;
    pending_way_d = pending_way_q;
    pending_hit_d = pending_hit_q;

    for (int set_i = 0; set_i < SET_COUNT; set_i++) begin
      for (int way = 0; way < WAY_COUNT; way++) begin
        tag_d[set_i][way] = tag_q[set_i][way];
        data_d[set_i][way] = data_q[set_i][way];
        lru_order_d[set_i][way] = lru_order_q[set_i][way];
      end
    end

    if (rsp_fire) begin
      rsp_valid_d = 1'b0;
    end

    unique case (state_q)
      STATE_IDLE: begin
        if (req_fire) begin
          pending_addr_d = req_word_addr;
          pending_wstrb_d = cpu_req_write ? cpu_req_wstrb : '0;
          pending_set_d = req_set;
          pending_tag_d = req_tag;
          pending_way_d = hit_valid ? hit_way : victim_way;
          pending_hit_d = hit_valid;

          if (cpu_req_write) begin
            pending_wdata_d = hit_valid ? merged_write_data : cpu_req_wdata;
            state_d = STATE_WRITE_REQ;
          end else if (hit_valid) begin
            rsp_valid_d = 1'b1;
            rsp_rdata_d = hit_data;
            rsp_hit_d = 1'b1;
            rsp_error_d = 1'b0;
            for (int pos = 0; pos < WAY_COUNT; pos++) begin
              if (lru_order_q[req_set][pos] == hit_way) begin
                for (int shift = pos; shift > 0; shift--) begin
                  lru_order_d[req_set][shift] = lru_order_q[req_set][shift - 1];
                end
                lru_order_d[req_set][0] = hit_way;
              end
            end
          end else begin
            state_d = STATE_READ_REQ;
          end
        end
      end

      STATE_READ_REQ: begin
        if (mem_req_fire) begin
          state_d = STATE_READ_RSP;
        end
      end

      STATE_READ_RSP: begin
        if (mem_rsp_fire) begin
          rsp_valid_d = 1'b1;
          rsp_rdata_d = mem_rsp_rdata;
          rsp_hit_d = 1'b0;
          rsp_error_d = mem_rsp_error;
          state_d = STATE_IDLE;

          if (!mem_rsp_error) begin
            valid_d[pending_set_q][pending_way_q] = 1'b1;
            tag_d[pending_set_q][pending_way_q] = pending_tag_q;
            data_d[pending_set_q][pending_way_q] = mem_rsp_rdata;
            for (int pos = 0; pos < WAY_COUNT; pos++) begin
              if (lru_order_q[pending_set_q][pos] == pending_way_q) begin
                for (int shift = pos; shift > 0; shift--) begin
                  lru_order_d[pending_set_q][shift] =
                    lru_order_q[pending_set_q][shift - 1];
                end
                lru_order_d[pending_set_q][0] = pending_way_q;
              end
            end
          end
        end
      end

      STATE_WRITE_REQ: begin
        if (mem_req_fire) begin
          state_d = STATE_WRITE_RSP;
        end
      end

      STATE_WRITE_RSP: begin
        if (mem_rsp_fire) begin
          rsp_valid_d = 1'b1;
          rsp_rdata_d = '0;
          rsp_hit_d = pending_hit_q;
          rsp_error_d = mem_rsp_error;
          state_d = STATE_IDLE;

          if (pending_hit_q && !mem_rsp_error) begin
            data_d[pending_set_q][pending_way_q] = pending_wdata_q;
            for (int pos = 0; pos < WAY_COUNT; pos++) begin
              if (lru_order_q[pending_set_q][pos] == pending_way_q) begin
                for (int shift = pos; shift > 0; shift--) begin
                  lru_order_d[pending_set_q][shift] =
                    lru_order_q[pending_set_q][shift - 1];
                end
                lru_order_d[pending_set_q][0] = pending_way_q;
              end
            end
          end
        end
      end

      default: begin
        state_d = STATE_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= STATE_IDLE;
      valid_q <= '0;
      rsp_valid_q <= 1'b0;
      rsp_rdata_q <= '0;
      rsp_hit_q <= 1'b0;
      rsp_error_q <= 1'b0;
      pending_addr_q <= '0;
      pending_wdata_q <= '0;
      pending_wstrb_q <= '0;
      pending_set_q <= '0;
      pending_tag_q <= '0;
      pending_way_q <= '0;
      pending_hit_q <= 1'b0;

      for (int set_i = 0; set_i < SET_COUNT; set_i++) begin
        for (int way = 0; way < WAY_COUNT; way++) begin
          tag_q[set_i][way] <= '0;
          data_q[set_i][way] <= '0;
          lru_order_q[set_i][way] <= WAY_INDEX_WIDTH'(way);
        end
      end
    end else begin
      state_q <= state_d;
      valid_q <= valid_d;
      rsp_valid_q <= rsp_valid_d;
      rsp_rdata_q <= rsp_rdata_d;
      rsp_hit_q <= rsp_hit_d;
      rsp_error_q <= rsp_error_d;
      pending_addr_q <= pending_addr_d;
      pending_wdata_q <= pending_wdata_d;
      pending_wstrb_q <= pending_wstrb_d;
      pending_set_q <= pending_set_d;
      pending_tag_q <= pending_tag_d;
      pending_way_q <= pending_way_d;
      pending_hit_q <= pending_hit_d;

      for (int set_i = 0; set_i < SET_COUNT; set_i++) begin
        for (int way = 0; way < WAY_COUNT; way++) begin
          tag_q[set_i][way] <= tag_d[set_i][way];
          data_q[set_i][way] <= data_d[set_i][way];
          lru_order_q[set_i][way] <= lru_order_d[set_i][way];
        end
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    assert (ADDR_WIDTH > SET_INDEX_WIDTH + BYTE_OFFSET_WIDTH)
      else $fatal(1, "ADDR_WIDTH must leave at least one tag bit");
    assert (DATA_WIDTH % 8 == 0)
      else $fatal(1, "DATA_WIDTH must be byte-addressable");
    assert (DATA_BYTES >= 2 && (DATA_BYTES & (DATA_BYTES - 1)) == 0)
      else $fatal(1, "DATA_BYTES must be a power of two and at least 2");
    assert (SET_COUNT >= 2 && (SET_COUNT & (SET_COUNT - 1)) == 0)
      else $fatal(1, "SET_COUNT must be a power of two and at least 2");
    assert (WAY_COUNT >= 2)
      else $fatal(1, "WAY_COUNT must be at least 2");
  end

  default clocking lru_cache_cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  assert_one_hot_state:
    assert property (state_q inside {
      STATE_IDLE,
      STATE_READ_REQ,
      STATE_READ_RSP,
      STATE_WRITE_REQ,
      STATE_WRITE_RSP
    })
    else $error("LRU cache entered an invalid state");

  assert_no_cpu_accept_while_busy:
    assert property ((state_q != STATE_IDLE) |-> !cpu_req_ready)
    else $error("LRU cache accepted a CPU request while a miss/write was active");

  cover_read_hit:
    cover property (req_fire && !cpu_req_write && hit_valid);

  cover_read_miss:
    cover property (req_fire && !cpu_req_write && !hit_valid);

  cover_write_hit:
    cover property (req_fire && cpu_req_write && hit_valid);
`endif
endmodule
