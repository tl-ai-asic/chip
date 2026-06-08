`timescale 1ns/1ps

module dma_reorder_buffer #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int SLOT_COUNT = 8,
  parameter int READ_SLOT_LIMIT = SLOT_COUNT,
  parameter int WRITE_SLOT_LIMIT = SLOT_COUNT,
  parameter int ID_WIDTH = (SLOT_COUNT <= 1) ? 1 : $clog2(SLOT_COUNT)
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  clear,

  input  logic                  read_alloc_fire,
  input  logic [ID_WIDTH-1:0]   read_alloc_id,
  input  logic [ADDR_WIDTH-1:0] read_alloc_dst_addr,

  input  logic                  rd_rsp_valid,
  output logic                  rd_rsp_ready,
  input  logic [ID_WIDTH-1:0]   rd_rsp_id,
  input  logic [DATA_WIDTH-1:0] rd_rsp_data,
  output logic                  rd_rsp_fire,

  output logic                  wr_req_valid,
  input  logic                  wr_req_ready,
  output logic [ID_WIDTH-1:0]   wr_req_id,
  output logic [ADDR_WIDTH-1:0] wr_req_addr,
  output logic [DATA_WIDTH-1:0] wr_req_data,
  output logic                  wr_req_fire,

  input  logic                  wr_rsp_valid,
  output logic                  wr_rsp_ready,
  input  logic [ID_WIDTH-1:0]   wr_rsp_id,
  output logic                  wr_rsp_fire
);
  logic [SLOT_COUNT-1:0] slot_read_outstanding_q, slot_read_outstanding_d;
  logic [SLOT_COUNT-1:0] slot_write_pending_q, slot_write_pending_d;
  logic [SLOT_COUNT-1:0] slot_write_outstanding_q, slot_write_outstanding_d;
  logic [ADDR_WIDTH-1:0] slot_dst_addr_q [SLOT_COUNT];
  logic [ADDR_WIDTH-1:0] slot_dst_addr_d [SLOT_COUNT];
  logic [DATA_WIDTH-1:0] slot_data_q [SLOT_COUNT];
  logic [DATA_WIDTH-1:0] slot_data_d [SLOT_COUNT];

  logic                  rd_rsp_match_valid;
  logic [ID_WIDTH-1:0]   rd_rsp_match_id;
  logic                  wr_rsp_match_valid;
  logic [ID_WIDTH-1:0]   wr_rsp_match_id;
  logic                  wr_req_slot_valid;
  logic [ID_WIDTH-1:0]   wr_req_slot_id;

  always_comb begin
    rd_rsp_match_valid = 1'b0;
    rd_rsp_match_id = '0;
    wr_rsp_match_valid = 1'b0;
    wr_rsp_match_id = '0;
    wr_req_slot_valid = 1'b0;
    wr_req_slot_id = '0;

    for (int slot = 0; slot < SLOT_COUNT; slot++) begin
      if (!rd_rsp_match_valid &&
          (rd_rsp_id == ID_WIDTH'(slot)) &&
          slot_read_outstanding_q[slot]) begin
        rd_rsp_match_valid = 1'b1;
        rd_rsp_match_id = ID_WIDTH'(slot);
      end

      if (!wr_req_slot_valid && slot_write_pending_q[slot]) begin
        wr_req_slot_valid = 1'b1;
        wr_req_slot_id = ID_WIDTH'(slot);
      end

      if (!wr_rsp_match_valid &&
          (wr_rsp_id == ID_WIDTH'(slot)) &&
          slot_write_outstanding_q[slot]) begin
        wr_rsp_match_valid = 1'b1;
        wr_rsp_match_id = ID_WIDTH'(slot);
      end
    end
  end

  assign rd_rsp_ready = rd_rsp_match_valid;
  assign rd_rsp_fire = rd_rsp_valid && rd_rsp_ready;

  assign wr_req_valid = wr_req_slot_valid;
  assign wr_req_id = wr_req_slot_id;
  assign wr_req_addr = slot_dst_addr_q[wr_req_slot_id];
  assign wr_req_data = slot_data_q[wr_req_slot_id];
  assign wr_req_fire = wr_req_valid && wr_req_ready;

  assign wr_rsp_ready = wr_rsp_match_valid;
  assign wr_rsp_fire = wr_rsp_valid && wr_rsp_ready;

  always_comb begin
    slot_read_outstanding_d = slot_read_outstanding_q;
    slot_write_pending_d = slot_write_pending_q;
    slot_write_outstanding_d = slot_write_outstanding_q;

    for (int slot = 0; slot < SLOT_COUNT; slot++) begin
      slot_dst_addr_d[slot] = slot_dst_addr_q[slot];
      slot_data_d[slot] = slot_data_q[slot];
    end

    if (clear) begin
      slot_read_outstanding_d = '0;
      slot_write_pending_d = '0;
      slot_write_outstanding_d = '0;
    end else begin
      if (read_alloc_fire) begin
        slot_read_outstanding_d[read_alloc_id] = 1'b1;
        slot_write_pending_d[read_alloc_id] = 1'b0;
        slot_write_outstanding_d[read_alloc_id] = 1'b0;
        slot_dst_addr_d[read_alloc_id] = read_alloc_dst_addr;
        slot_data_d[read_alloc_id] = '0;
      end

      if (rd_rsp_fire) begin
        slot_read_outstanding_d[rd_rsp_match_id] = 1'b0;
        slot_write_pending_d[rd_rsp_match_id] = 1'b1;
        slot_data_d[rd_rsp_match_id] = rd_rsp_data;
      end

      if (wr_req_fire) begin
        slot_write_pending_d[wr_req_slot_id] = 1'b0;
        slot_write_outstanding_d[wr_req_slot_id] = 1'b1;
      end

      if (wr_rsp_fire) begin
        slot_write_outstanding_d[wr_rsp_match_id] = 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      slot_read_outstanding_q <= '0;
      slot_write_pending_q <= '0;
      slot_write_outstanding_q <= '0;
      for (int slot = 0; slot < SLOT_COUNT; slot++) begin
        slot_dst_addr_q[slot] <= '0;
        slot_data_q[slot] <= '0;
      end
    end else begin
      slot_read_outstanding_q <= slot_read_outstanding_d;
      slot_write_pending_q <= slot_write_pending_d;
      slot_write_outstanding_q <= slot_write_outstanding_d;
      for (int slot = 0; slot < SLOT_COUNT; slot++) begin
        slot_dst_addr_q[slot] <= slot_dst_addr_d[slot];
        slot_data_q[slot] <= slot_data_d[slot];
      end
    end
  end

`ifndef SYNTHESIS
  logic [SLOT_COUNT-1:0] slot_occupied;

  assign slot_occupied = slot_read_outstanding_q |
                         slot_write_pending_q |
                         slot_write_outstanding_q;

  default clocking rob_cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  cover_reorder_slots_full:
    cover property (slot_occupied == {SLOT_COUNT{1'b1}});

  cover_read_tracking_slots_full:
    cover property ($countones(slot_read_outstanding_q) == READ_SLOT_LIMIT);

  cover_write_pending_available:
    cover property (|slot_write_pending_q);

  cover_write_outstanding_slots_full:
    cover property ($countones(slot_write_outstanding_q) == WRITE_SLOT_LIMIT);

  assert_read_alloc_uses_free_slot:
    assert property (
      read_alloc_fire |->
      !slot_read_outstanding_q[read_alloc_id] &&
      !slot_write_pending_q[read_alloc_id] &&
      !slot_write_outstanding_q[read_alloc_id]
    )
    else $error("DMA reorder buffer allocated an occupied slot");

  assert_read_alloc_reserves_slot:
    assert property (
      read_alloc_fire |=>
      slot_read_outstanding_q[$past(read_alloc_id)] &&
      !slot_write_pending_q[$past(read_alloc_id)] &&
      !slot_write_outstanding_q[$past(read_alloc_id)]
    )
    else $error("DMA reorder buffer did not reserve a read slot after allocation");

  assert_read_rsp_retires_read_slot:
    assert property (
      rd_rsp_fire |=>
      !slot_read_outstanding_q[$past(rd_rsp_match_id)] &&
      slot_write_pending_q[$past(rd_rsp_match_id)]
    )
    else $error("DMA reorder buffer did not retire read slot into write-pending state");
`endif
endmodule
